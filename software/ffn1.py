"""A12W10 的量化与整数参考；参数供 hardware/run.py 验证正式阵列。"""
from pathlib import Path
import argparse
import numpy as np

ROOT = Path(__file__).resolve().parent


def quantize(x, scale):
    """按冻结尺度取最近偶数并截到对称12位码域。"""
    return np.clip(np.rint(x / scale), -2047, 2047).astype(np.int16)


def integer_gemm(a, w, bias):
    """宽整数计算后转INT32，与RTL的补码回绕一致。"""
    return (a.astype(np.int64) @ w.astype(np.int64) + bias).astype(np.int32)


def compute(x, layer):
    """计算一层FFN1，返回整数结果和按列尺度还原的浮点结果。"""
    with np.load(ROOT / 'parameters.npz') as params:
        key = f'layer{layer:02d}'
        sx = params[key + '_activation_scale']  # 本层输入尺度
        sw = params[key + '_weight_scales']     # 各输出列的权重尺度
        a = quantize(x, sx)
        y = integer_gemm(a, params[key + '_weight'], params[key + '_bias'])
        return y, y.astype(np.float64) * sx * sw


def check():
    """用保留的两个验证样本检查12层量化误差，不重新标定。"""
    errors = []
    with np.load(ROOT / 'validation.npz') as data:
        for layer in range(1, 13):
            key = f'layer{layer:02d}'
            for x, expected in zip(data[key + '_x'], data[key + '_fp32']):
                _, actual = compute(x, layer)
                errors.append(100 * np.linalg.norm(actual - expected) /
                              np.linalg.norm(expected))
    peak = max(errors)
    print(f'A12W10：24个验证任务，最大NRMSE={peak:.6f}%（要求<0.3%）')
    return 0 if peak < 0.3 else 1


def main():
    """运行误差检查，或把给定FP32输入计算为整数/还原结果。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='检查冻结样本误差')
    parser.add_argument('--input', type=Path, help='本层FP32输入.npy，形状M×64')
    parser.add_argument('--layer', type=int, choices=range(1, 13), default=1)
    parser.add_argument('--output', type=Path, default=Path('.build/ffn1_output.npz'))
    args = parser.parse_args()
    if args.check:
        return check()
    if args.input is None:
        parser.error('请提供 --input 或 --check')
    y, restored = compute(np.load(args.input), args.layer)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    np.savez(args.output, integer=y, restored=restored)
    print(args.output)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
