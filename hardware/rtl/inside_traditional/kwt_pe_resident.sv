// 传统驻留PE：低、高半字分两拍相加并回写INT32部分和。
module kwt_pe_resident (
    input logic clk, rst_n,                 // 时钟、低有效复位
    input logic init,                       // 装入历史部分和
    input logic compute, enable,            // 乘积有效、非零使能
    input logic signed [21:0] product,      // A12×W10完整乘积
    input logic shift,                      // 排空时移入链前级
    kwt_psum_if.sink psum_in,               // 前级部分和
    kwt_psum_if.source psum_out             // 本级部分和
);
    logic [31:0] sum;                       // 驻留INT32部分和
    logic add_v;                            // 第二拍提交有效
    logic [15:0] add_low;                   // 第一级低半字和
    logic [15:0] add_high_a,add_high_b;     // 第二级高半字操作数
    logic add_carry;                        // 低半字进位

    assign psum_out.data=sum; // 向后级部分和链提供本PE的驻留值。

    // 首拍计算低位并锁存高位操作数，次拍完成高位和并提交。
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin // 复位清空部分和及两拍加法的中间状态。
            sum<='0; add_v<=1'b0; add_low<='0; add_high_a<='0;
            add_high_b<='0; add_carry<=1'b0;
        end else begin // 正常运行：有非零乘积才发射加法。
            add_v<=compute && enable;
            if (compute && enable) begin // 加法首拍：低16位求和，锁存进位和高位操作数。
                add_low<=sum[15:0]+product[15:0];
                add_carry<=({1'b0,sum[15:0]}+{1'b0,product[15:0]})>>16;
                add_high_a<=sum[31:16];
                add_high_b<={{10{product[21]}},product[21:16]};
            end else if (add_v) begin // 无新发射且上拍有效时，完成高位加法并写回。
                sum<={add_high_a+add_high_b+add_carry,add_low};
            end
            if (init) begin // 装载历史和优先于算术提交，同时取消旧流水有效位。
                sum<=psum_in.data;
                add_v<=1'b0;
            end else if (shift && !add_v && !(compute && enable)) sum<=psum_in.data; // 排空且加法空闲时，移入前级部分和。
        end
    end
endmodule
