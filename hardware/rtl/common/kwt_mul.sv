// 三拍有符号12×10乘法器：操作数寄存→两段部分积→合并；由乘法列实例化。
module kwt_mul (
    input logic clk, rst_n,             // 时钟、低有效复位
    input logic in_valid,              // 输入向量有效，零值也占用流水位置
    input logic signed [11:0] a,        // 激活值
    input logic signed [9:0] b,         // 权重值
    output logic out_valid,            // 三拍后的向量有效位
    output logic out_enable,           // 此乘积非零，允许下游更新算术寄存器
    output logic signed [21:0] product // 完整有符号乘积；enable=0时保持旧值
);
    logic [2:0] valid_q, enable_q;      // 有效位与零值使能逐拍对齐
    logic signed [11:0] a_q;           // 第一级激活寄存器
    logic signed [9:0] b_q;            // 第一级权重寄存器
    logic signed [17:0] low_q;         // A乘B的低5位（补符号0）
    logic signed [16:0] high_q;        // A乘B的高5位（有符号）
    logic nonzero;                     // 零A关闭本行，零B关闭本列的乘法更新
    assign nonzero = (a!=0) && (b!=0); // 任一乘数为零，关闭该乘法通道的数据更新。
    assign out_valid = valid_q[2]; // 输出有效位与第三级乘积寄存器对齐。
    assign out_enable = enable_q[2]; // 非零标记同样延迟三拍，供下游屏蔽旧乘积。

    // 仅控制位无条件前进；零乘数冻结数据寄存器，不改变后续时序。
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin // 复位清空流水标记和数据寄存器。
            valid_q<='0; enable_q<='0;
            a_q<='0; b_q<='0; low_q<='0; high_q<='0; product<='0;
        end else begin // 有效位始终前进，数据通路按各级使能更新。
            valid_q <= {valid_q[1:0],in_valid}; // 有效位每拍前进，包括零乘积位置。
            enable_q <= {enable_q[1:0],in_valid && nonzero}; // 数据更新使能与有效位保持相同延迟。
            if (in_valid && nonzero) begin a_q<=a; b_q<=b; end // 第一级仅锁存有效且非零的操作数。
            if (enable_q[0]) begin // 第二级计算低5位与高5位对应的两个部分积。
                low_q <= a_q * $signed({1'b0,b_q[4:0]}); // 低5位原本无符号，补0后按有符号数相乘。
                high_q <= a_q * $signed(b_q[9:5]); // 高5位保留原权重符号，后一级再左移5位。
            end
            // B=低5位+有符号高5位×32，拼接前先扩展以保留负数。
            if (enable_q[1]) product <= {{4{low_q[17]}},low_q} // 第三级合并两个部分积；无使能时保持旧结果。
                                      + ({{5{high_q[16]}},high_q} << 5);
        end
    end
endmodule
