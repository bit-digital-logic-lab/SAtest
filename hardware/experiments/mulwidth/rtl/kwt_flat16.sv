// 16×16扁平阵列：256个单乘PE，A按行广播、B按列广播，统一valid驱动。
// 只做计算核心，psum_in全部接0、init/shift接0，不含驻留和上传/下载逻辑。
module kwt_flat16 (
    input logic clk,rst_n, // 时钟、低有效复位
    input logic signed [16*12-1:0] a_row, // 每行一个A12：[12*r +: 12]为第r行
    input logic signed [16*10-1:0] b_col, // 每列一个B10：[10*c +: 10]为第c列
    input logic valid, // 统一发射节拍，所有PE同拍计算
    output logic [256*32-1:0] out // 256个符号扩展INT32，[32*(16*r+c) +: 32]
);
    kwt_psum_if zero_psum(); // 公共零旧和；阵列内无上下行通道
    kwt_psum_if pe_psum [0:255](); // 每个PE自己的和输出端点
    assign zero_psum.data=32'b0; // 只测计算核心面积，旧和恒为0
    // 行列展开：同一行共享A，同一列共享B，索引r*16+c与输出切片一致。
    for (genvar r=0;r<16;r++) begin : g_row
        for (genvar c=0;c<16;c++) begin : g_col
            localparam int IDX=r*16+c; // 该PE在输出总线上的位置
            kwt_pe_m1 u_pe(.clk(clk),.rst_n(rst_n),
                .a(a_row[r*12 +: 12]),.b(b_col[c*10 +: 10]),
                .compute(valid),.init(1'b0),.shift(1'b0), // 不算上传/移位
                .psum_in(zero_psum),.psum_out(pe_psum[IDX]));
            assign out[IDX*32 +: 32]=pe_psum[IDX].data; // 32位符号扩展结果送到顶层总线
        end
    end
endmodule
