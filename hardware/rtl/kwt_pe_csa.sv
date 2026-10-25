// CSA PE：三拍乘法后以sum/carry两数驻留累计；不含进位传播加法器。
// 4×4块负责选择输出行，并把共享加法器的最终结果写回本PE原sum寄存器。
module kwt_pe_csa (
    input logic clk, rst_n, // 时钟、低有效复位
    input logic signed [11:0] a, // 独立激活输入
    input logic signed [9:0] b, // 独立权重输入
    input logic compute, init, shift, // 发射、旧和装入、结果移位
    input logic finalize, // 本行共享加法结果写回
    input logic [31:0] final_data, // 共享加法器的INT32结果
    output logic [31:0] carry_data, // 驻留进位，送共享加法器
    kwt_psum_if.sink psum_in, // 上传下载共用链输入
    kwt_psum_if.source psum_out // 原sum寄存器输出
);
    logic mul_valid, mul_enable; // 乘积位置和非零使能
    logic signed [21:0] product; // 三拍有符号乘积
    kwt_mul u_mul(.clk(clk),.rst_n(rst_n),.a(a),.b(b),.in_valid(compute),
        .out_valid(mul_valid),.out_enable(mul_enable),.product(product));
    kwt_csa32 u_csa(.clk(clk),.rst_n(rst_n),.load(init || shift),.load_data(psum_in.data),
        .valid(mul_valid && mul_enable),.product(product),.finalize(finalize),
        .final_data(final_data),.sum_data(psum_out.data),.carry_data(carry_data));
endmodule
