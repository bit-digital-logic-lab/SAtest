// 普通PE：独立A12/B10端口→三拍乘法器→单拍普通累加器。
// 供4×4块实例化；没有三压二、carry寄存器或最终共享加法阶段。
module kwt_pe_mac (
    input logic clk,rst_n, // 时钟、低有效复位
    input logic signed [11:0] a, // 激活独立输入
    input logic signed [9:0] b, // 权重独立输入
    input logic compute, // 本拍乘数有效
    input logic init,shift, // 原部分和上传、下载移位
    kwt_psum_if.sink psum_in, // 下一行同列的部分和
    kwt_psum_if.source psum_out // 本PE原sum寄存器
);
    logic mul_valid,mul_enable; // 三拍有效位置与非零更新标记
    logic signed [21:0] product; // 完整乘积
    kwt_mul u_mul(.clk(clk),.rst_n(rst_n),.a(a),.b(b),.in_valid(compute),
        .out_valid(mul_valid),.out_enable(mul_enable),.product(product));
    kwt_acc32 u_acc(.clk(clk),.rst_n(rst_n),.load(init || shift),.load_data(psum_in.data),
        .valid(mul_valid && mul_enable),.product(product),.sum(psum_out.data));
endmodule
