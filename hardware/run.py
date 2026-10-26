#!/usr/bin/env python3
"""CSA、普通及双乘版本的整数逐点回归与周期测量。"""
from __future__ import annotations

import argparse
import json
import random
import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
HW = ROOT / "hardware"
RTL = HW / "rtl"
TB = HW / "tb" / "tb_kwt_block32.sv"
BUILD = ROOT / ".build" / "simulation"


def sources_for(version: str) -> list[Path]:
    """接口先读，其他模块统一收集；只编译所选版本，两个版本的同名模块绝不混读。"""
    interface = RTL / "kwt_interfaces.sv"
    return [interface, *sorted(p for p in RTL.glob("*.sv") if p != interface),
            *sorted((HW / "versions" / version / "rtl").glob("*.sv"))]


def write_hex(path: Path, values, width: int) -> None:
    mask = (1 << width) - 1
    path.write_text("".join(f"{int(v) & mask:0{(width + 3) // 4}x}\n" for v in values))


def vectors(directory: Path, m: int, k: int, n: int, seed: int, pattern: str = "random", acc_bits: int = 32) -> dict[str, str]:
    rng = random.Random(seed)
    a = [[rng.randrange(-2048, 2048) for _ in range(k)] for _ in range(m)]
    b = [[rng.randrange(-512, 512) for _ in range(n)] for _ in range(k)]
    bias = [rng.randrange(-(1 << 29), 1 << 29) for _ in range(n)]
    # 零值、稀疏和补码边界验证CE不改变节拍，以及INT32自然回绕。
    if pattern == "zero":
        a = [[0 for _ in range(k)] for _ in range(m)]
    elif pattern == "sparse":
        a = [[0 if (r + t) % 4 else a[r][t] for t in range(k)] for r in range(m)]
        b = [[0 if (t + c) % 3 else b[t][c] for c in range(n)] for t in range(k)]
    elif pattern == "extremes":
        av, bv = [-2048, -2047, -1, 0, 1, 2047], [-512, -511, -1, 0, 1, 511]
        a = [[av[(r + 2*t) % len(av)] for t in range(k)] for r in range(m)]
        b = [[bv[(3*t + c) % len(bv)] for c in range(n)] for t in range(k)]
        bias = [[-(1 << 31), (1 << 31)-1, 0][c % 3] for c in range(n)]
    expected = [
        (bias[c] + sum(a[r][t] * b[t][c] for t in range(k))) & 0xFFFFFFFF
        for r in range(m) for c in range(n)
    ]
    # 将宽整数独立参考按所选累加位宽回绕，再符号扩展到外部32位行接口。
    expected = [(((v + (1 << (acc_bits-1))) % (1 << acc_bits)) - (1 << (acc_bits-1))) & 0xFFFFFFFF for v in expected]
    directory.mkdir(parents=True, exist_ok=True)
    files = {"A": directory / "a.hex", "B": directory / "b.hex",
             "BIAS": directory / "bias.hex", "EXPECTED": directory / "expected.hex",
             "OUT": directory / "output.txt"}
    write_hex(files["A"], (x for row in a for x in row), 12)
    write_hex(files["B"], (x for row in b for x in row), 10)
    write_hex(files["BIAS"], bias, 32)
    write_hex(files["EXPECTED"], expected, 32)
    return {name: str(path.resolve()) for name, path in files.items()} | {
        "M": str(m), "K": str(k), "N": str(n)
    }


def real_vectors(directory: Path, layer: int = 1, sample: int = 0, acc_bits: int = 32) -> dict[str, str]:
    params = np.load(ROOT / "software" / "parameters.npz")
    validation = np.load(ROOT / "software" / "validation.npz")
    prefix = f"layer{layer:02d}"
    x = validation[f"{prefix}_x"][sample]
    a = np.clip(np.rint(x / float(params[f"{prefix}_activation_scale"])), -2047, 2047).astype(np.int64)
    b = params[f"{prefix}_weight"].astype(np.int64)
    bias = params[f"{prefix}_bias"].astype(np.int64)
    m, k = a.shape
    _, n = b.shape
    expected = [
        (int(bias[c]) + sum(int(a[r, t]) * int(b[t, c]) for t in range(k))) & 0xFFFFFFFF
        for r in range(m) for c in range(n)
    ]
    # 将宽整数独立参考按所选累加位宽回绕，再符号扩展到外部32位行接口。
    expected = [(((v + (1 << (acc_bits-1))) % (1 << acc_bits)) - (1 << (acc_bits-1))) & 0xFFFFFFFF for v in expected]
    directory.mkdir(parents=True, exist_ok=True)
    files = {"A": directory / "a.hex", "B": directory / "b.hex",
             "BIAS": directory / "bias.hex", "EXPECTED": directory / "expected.hex",
             "OUT": directory / "output.txt"}
    write_hex(files["A"], a.flat, 12)
    write_hex(files["B"], b.flat, 10)
    write_hex(files["BIAS"], bias, 32)
    write_hex(files["EXPECTED"], expected, 32)
    return {name: str(path.resolve()) for name, path in files.items()} | {
        "M": str(m), "K": str(k), "N": str(n)
    }


def compile_version(version: str) -> tuple[Path, Path]:
    out = BUILD / version
    out.mkdir(parents=True, exist_ok=True)
    binary = out / "Vtb_kwt_block32"
    log = out / "compile.log"
    command = ["verilator", "--binary", "--timing", "--assert", "-Wno-fatal", "-j", "4",
               "--top-module", "tb_kwt_block32", "-GTAIL_CYCLES=" + ("10" if version=="csa" else "0"),
               "-GK_LANES=" + ("2" if version=="dual" else "1"),
               "-GACC_BITS=" + ("28" if version=="dual" else "32"),
               "--Mdir", str(out / "obj"), "-o", str(binary)]
    command += [str(path) for path in sources_for(version)] + [str(TB)]
    with log.open("w") as stream:
        result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"compile {version} failed; see {log}")
    return binary, log


def check_dual_pe() -> None:
    """双乘版逐拍检查两个独立三级乘法和28位累加，日志与整层回归同目录。"""
    out = BUILD / "dual" / "pe"
    out.mkdir(parents=True, exist_ok=True)
    binary = out / "Vtb_kwt_pe_dual"
    command = ["verilator", "--binary", "--timing", "--assert", "-Wno-fatal", "-j", "4",
               "--top-module", "tb_kwt_pe_dual", "--Mdir", str(out / "obj"), "-o", str(binary)]
    command += [str(path) for path in sources_for("dual")]
    command += [str(HW / "versions/dual/tb/tb_kwt_pe_dual.sv")]
    with (out / "compile.log").open("w") as stream:
        subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, check=True)
    with (out / "run.log").open("w") as stream:
        subprocess.run([str(binary)], cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, check=True)
    print((out / "run.log").read_text().splitlines()[0], flush=True)


def run_case(binary: Path, version: str, name: str, args: dict[str, str]) -> dict:
    log = BUILD / version / name / "run.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    command = [str(binary), *(f"+{key}={value}" for key, value in args.items())]
    with log.open("w") as stream:
        result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
    content = log.read_text(errors="replace")
    if result.returncode:
        print(content[-4000:], file=sys.stderr)
        raise RuntimeError(f"{version}/{name} failed exit={result.returncode}; see {log}")
    line = next((line for line in content.splitlines() if line.startswith("PASS ")), "")
    print(line)
    parts = dict(item.split("=", 1) for item in line.split() if "=" in item)
    timing = next(line for line in content.splitlines() if line.startswith("TIMING "))
    phases = {key: int(value) for key, value in
              (item.split("=", 1) for item in timing.split() if "=" in item)}
    return {"version": version, "case": name, "log": str(log),
            **{key: value if key == "shape" else int(value) for key, value in parts.items()},
            "phases": phases}


def synth(version: str) -> None:
    out = BUILD / version
    out.mkdir(parents=True, exist_ok=True)
    netlist = out / "kwt_block32.json"
    log = out / "synth.log"
    files = " ".join(str(path) for path in sources_for(version))
    script = (f"read_slang --top kwt_block32 -GK_LANES={2 if version=='dual' else 1} -GTAIL_CYCLES={10 if version=='csa' else 0} {files}; hierarchy -check -top kwt_block32; "
              f"flatten; proc; opt; wreduce; opt; check -assert; write_json {netlist}")
    with log.open("w") as stream:
        result = subprocess.run(["yosys", "-m", "slang", "-p", script], cwd=ROOT,
                                stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"synth {version} failed; see {log}")
    print(f"SYNTH_PASS version={version} netlist={netlist} report=see {log}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version",choices=("csa","normal","dual","all"),default="csa")
    parser.add_argument("--full", action="store_true", help="追加12层、每层2个冻结真实样本回归")
    parser.add_argument("--synth", action="store_true", help="执行Slang/Yosys结构检查")
    parser.add_argument("--seed", type=int, default=0x8A1210)
    parser.add_argument("--output", type=Path, help="独立回归结果目录")
    args = parser.parse_args()
    global BUILD
    if args.output: BUILD = args.output.resolve()
    versions = ["csa","normal","dual"] if args.version=="all" else [args.version]
    required = [TB]
    for version in versions:
        required.extend(sources_for(version))
    missing = [path for path in required if not path.is_file()]
    if missing:
        print("missing: " + ", ".join(str(path) for path in missing), file=sys.stderr)
        return 2
    results = []
    try:
        for version in versions:
            if version == "dual": check_dual_pe()
            binary, _ = compile_version(version)
            default = vectors(BUILD / version / "matrix_35x37x40", 35, 37, 40, args.seed, acc_bits=28 if version=="dual" else 32)
            stats = [run_case(binary, version, "matrix_35x37x40", default)]
            for pattern in ("zero", "sparse", "extremes"):
                name = f"{pattern}_32x64x32"
                stats.append(run_case(binary, version, name,
                    vectors(BUILD / version / name, 32, 64, 32, args.seed, pattern, acc_bits=28 if version=="dual" else 32)))
            if args.full:
                for layer in range(1, 13):
                    for sample in range(2):
                        name = f"real_layer{layer:02d}_sample{sample}"
                        stats.append(run_case(binary, version, name,
                            real_vectors(BUILD / version / name, layer, sample, acc_bits=28 if version=="dual" else 32)))
            if args.synth:
                synth(version)
            results.extend(stats)
            print(f"SUMMARY version={version} cases={len(stats)} cycles={sum(x['cycles'] for x in stats)} "
                  f"host_writes={sum(x['host_writes'] for x in stats)} artifacts={BUILD / version}")
    except (RuntimeError, OSError, ValueError, KeyError) as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        return 1
    (BUILD / "results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
