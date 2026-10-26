// 双乘PE：两个独立三级A12×W10乘法器→组合3:2→单拍28位CPA；每拍2MAC，归属同一输出。
// 由4×4块实例化；两个K通道各自做零值CE，部分和行通道与现有接口兼容。
module kwt_pe_dual (
    input logic clk,rst_n, // 时钟、低有效复位
    input logic signed [11:0] a0,a1, // 同一行K=2i、2i+1的两个激活
    input logic signed [9:0] b0,b1, // 同一列对应两个K的权重
    input logic compute,init,shift, // 固定发射、旧和上传、结果移位节拍
    kwt_psum_if.sink psum_in, // 同列下一行的旧和
    kwt_psum_if.source psum_out // 本PE原和，符号扩展为32位
);
    logic v0,v1,e0,e1; // 两条独立流水的有效与非零标记
    logic signed [21:0] product0,product1; // 两个完整12×10乘积
    logic [27:0] p0,p1,sum_bits,carry_bits,acc; // 乘积扩展、组合压缩结果与唯一驻留和
    assign p0=e0 ? {{6{product0[21]}},product0} : 28'b0; // 零通道必须屏蔽乘法器保留的旧数据。
    assign p1=e1 ? {{6{product1[21]}},product1} : 28'b0; // 两个零值使能独立，不能一并丢掉非零通道。
    assign psum_out.data={{4{acc[27]}},acc}; // 外部32位行总线携带有符号28位结果。
    // 两个实例同时接受操作数，各自三级流水，绝不复用同一个乘法器。
    kwt_mul u_mul0(.clk(clk),.rst_n(rst_n),.in_valid(compute),.a(a0),.b(b0),
        .out_valid(v0),.out_enable(e0),.product(product0));
    kwt_mul u_mul1(.clk(clk),.rst_n(rst_n),.in_valid(compute),.a(a1),.b(b1),
        .out_valid(v1),.out_enable(e1),.product(product1));
    kwt_csa28 u_csa(.old_sum(acc),.p0(p0),.p1(p1),.sum_bits(sum_bits),.carry_bits(carry_bits));
    kwt_acc28 u_acc(.clk(clk),.rst_n(rst_n),.load(init||shift),.load_data(psum_in.data),
        .valid(v0&&v1&&(e0||e1)),.sum_bits(sum_bits),.carry_bits(carry_bits),.sum(acc));
endmodule
