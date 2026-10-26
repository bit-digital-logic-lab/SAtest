// 单乘PE：一个三级A12×W10乘法器直达单拍28位CPA；每拍1个MAC，只持有一个驻留和。
// 由kwt_flat16按16×16阵列实例化；与dual版PE相比删掉第二乘法器和三压二，面积按每PE 1乘缩放。
module kwt_pe_m1 (
    input logic clk,rst_n, // 时钟、低有效复位
    input logic signed [11:0] a, // 本行K位置的激活值
    input logic signed [9:0] b, // 本列同一K位置的权重
    input logic compute,init,shift, // 固定发射、旧和上传、结果整行移位节拍
    kwt_psum_if.sink psum_in, // 同列下一行的旧和（阵列中接0）
    kwt_psum_if.source psum_out // 本PE唯一驻留和，符号扩展为32位
);
    logic v,e; // 三级流水的有效位与零值使能
    logic signed [21:0] product; // 完整有符号12×10乘积
    logic [27:0] p,acc; // 乘积的28位符号扩展、驻留和
    // 零值使能必须屏蔽乘法器保留的旧数据，否则空拍会重复累加历史乘积。
    assign p=e ? {{6{product[21]}},product} : 28'b0;
    // 外部32位行总线携带有符号28位结果。
    assign psum_out.data={{4{acc[27]}},acc};
    // 唯一的乘法器，三级流水；不接受第二路操作数。
    kwt_mul u_mul(.clk(clk),.rst_n(rst_n),.in_valid(compute),.a(a),.b(b),
        .out_valid(v),.out_enable(e),.product(product));
    // 单拍CPA：sum_bits取驻留和，carry_bits取本拍乘积，acc+product在同一拍完成。
    // load(init||shift)优先于累加；valid=v&&e，零乘积拍保持原和。
    kwt_acc28 u_acc(.clk(clk),.rst_n(rst_n),.load(init||shift),.load_data(psum_in.data),
        .valid(v&&e),.sum_bits(acc),.carry_bits(p),.sum(acc));
endmodule
