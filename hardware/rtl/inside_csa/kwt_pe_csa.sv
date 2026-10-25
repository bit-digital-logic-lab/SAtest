// CSA计算单元：独立A12/W10端口→三拍乘法器→反馈三压二→两拍累计加法器。
// 最终结果驻留在加法器acc中；装入与排出沿同一寄存器链移动。
module kwt_pe_csa (
    input logic clk, rst_n,            // 时钟、低有效复位
    input logic signed [11:0] a,       // 横向到达的12位激活，独立输入端口
    input logic signed [9:0] b,        // 纵向到达的10位权重，独立输入端口
    input logic compute,              // A/B对应同一K位置的有效脉冲
    input logic init,                 // 按行序推入原部分和，并清除旧压缩状态
    input logic flush, shift,         // 反馈项收尾、最终部分和移位
    kwt_psum_if.sink psum_in,          // 排出时的后一级部分和
    kwt_psum_if.source psum_out       // 当前累计值，上传下载共用
);
    logic mul_valid,mul_enable;       // 乘法输出位置与零值更新使能
    logic signed [21:0] product;      // 只在单元内部传递的22位乘积
    logic add_valid;                  // 压缩器送出的一个32位数有效
    logic [31:0] add_data;            // 前送sum，收尾时为剩余carry

    kwt_mul u_mul(.clk(clk),.rst_n(rst_n),.a(a),.b(b),.in_valid(compute),
        .out_valid(mul_valid),.out_enable(mul_enable),.product(product));
    kwt_csa32 u_csa(.clk(clk),.rst_n(rst_n),.clear(init),
        .valid(mul_valid),.enable(mul_enable),.product(product),.flush(flush),
        .out_valid(add_valid),.out_data(add_data));
    kwt_acc32 u_acc(.clk(clk),.rst_n(rst_n),.load(init || shift),.load_data(psum_in.data),
        .valid(add_valid),.data(add_data),.sum(psum_out.data));

endmodule
