// 4×4驻留块：A12、W10直接送到16个PE，不经column层；块内管理水平及上下行部分和通道。
// 部分和从链尾上传，从链首按行下载；所有移位使用PE原累计寄存器，无额外行间寄存器。
module kwt_quad4x4 #(parameter bit CSA=0) (
    input logic clk, rst_n,          // 时钟、低有效复位
    input logic [47:0] a_rows,       // 独立A端口：四个12位行输入
    input logic [39:0] b_cols,       // 独立B端口：四个10位列输入
    input logic valid,              // 外层规定的A/B输入节拍
    input logic load,               // 按本块行序上传旧部分和
    input logic flush, shift,        // CSA尾项收尾、固定下载移位
    kwt_psum_if.sink block_in,       // 本块链尾输入，来自下一个4×4块
    kwt_psum_if.source block_out    // 本块链首输出，即第0行第0列原累计值
);
    kwt_psum_if pe_out[0:15]();     // 16个原累计寄存器输出，索引=行×4+列
    assign block_out.data=pe_out[0].data; // 块内行序的第一项，不经过列汇总或影子副本。

    for (genvar r=0;r<4;r++) begin : rows // 按行组织PE，块直接负责所有相邻通道。
        for (genvar c=0;c<4;c++) begin : cells
            kwt_psum_if next_sum(); // 本PE上传/下载共用的后继部分和连线，不新增寄存器
            if (c<3) begin : horizontal // 同一行内向左推进，右侧寄存器送入当前PE。
                assign next_sum.data=pe_out[r*4+c+1].data; // 水平相邻PE直接相连。
            end else if (r<3) begin : vertical // 行尾折到下一行链首，保留上下行通道。
                assign next_sum.data=pe_out[(r+1)*4].data; // 上下行的折返由4×4块内部管理。
            end else begin : tail // 最后一行末尾连接下一小块，不在大阵列展开PE通道。
                assign next_sum.data=block_in.data; // 新上传数据由大阵列从块尾逐项推入。
            end
            if (CSA) begin : csa_pe // A/B都直接到达本PE，内部是乘法→反馈压缩→累计。
                kwt_pe_csa u_pe(.clk(clk),.rst_n(rst_n),
                    .a($signed(a_rows[r*12+:12])),.b($signed(b_cols[c*10+:10])),
                    .compute(valid),.init(load),.flush(flush),.shift(shift),
                    .psum_in(next_sum),.psum_out(pe_out[r*4+c]));
            end else begin : traditional_pe // 传统加法版本也直接由块实例化PE，不再按列管理。
                logic mul_valid,mul_enable; // 三拍乘法位置和零值更新使能
                logic signed [21:0] product; // 仅本PE附近传递的完整乘积
                kwt_mul u_mul(.clk(clk),.rst_n(rst_n),.a($signed(a_rows[r*12+:12])),
                    .b($signed(b_cols[c*10+:10])),.in_valid(valid),
                    .out_valid(mul_valid),.out_enable(mul_enable),.product(product));
                kwt_pe_resident u_pe(.clk(clk),.rst_n(rst_n),.init(load),
                    .compute(mul_valid),.enable(mul_enable),.product(product),.shift(shift),
                    .psum_in(next_sum),.psum_out(pe_out[r*4+c]));
            end
        end
    end
endmodule
