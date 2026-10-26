// 普通4×4块：A/B按行列直接广播到16个PE，每个PE单拍普通累加。
// 部分和从底行上传，从顶行按行下载；所有移位使用PE原累计寄存器，无额外行间寄存器。
module kwt_quad4x4 (
    input logic clk, rst_n,          // 时钟、低有效复位
    input logic [47:0] a_rows,       // 独立A端口：四个12位行输入
    input logic [39:0] b_cols,       // 独立B端口：四个10位列输入
    input logic valid,              // 外层规定的A/B输入节拍
    input logic load,               // 按本块行序上传旧部分和
    input logic shift,               // 固定下载移位
    kwt_psum_row_if.sink block_in,       // 本块底行输入，来自下方4×4或外部输入行
    kwt_psum_row_if.source block_out    // 本块顶行四个原sum寄存器并行输出
);
    kwt_psum_if pe_out[0:15]();     // 16个原累计寄存器输出，索引=行×4+列
    for (genvar c=0;c<4;c++) begin : output_row // 顶行四列并行排出，不添加输出缓存。
        assign block_out.data[c*32+:32]=pe_out[c].data; // 直接读取顶行原sum。
    end

    for (genvar r=0;r<4;r++) begin : rows // 按行组织PE，块直接负责所有相邻通道。
        for (genvar c=0;c<4;c++) begin : cells
            kwt_psum_if next_sum(); // 本PE上传/下载共用的后继部分和连线，不新增寄存器
            if (r<3) begin : vertical // 同列下一级送上一级，一拍整行前移。
                assign next_sum.data=pe_out[(r+1)*4+c].data; // 复用下一行同列sum，不横向串行跳转。
            end else begin : bottom // 最底行连接下一小块或外部输入行。
                assign next_sum.data=block_in.data[c*32+:32]; // 四列同时注入一整行。
            end
            begin : mac_pe // 单元由独立乘法模块和普通累加模块组成。
                kwt_pe_mac u_pe(.clk(clk),.rst_n(rst_n),
                    .a($signed(a_rows[r*12+:12])),.b($signed(b_cols[c*10+:10])),
                    .compute(valid),.init(load),.shift(shift),
                    .psum_in(next_sum),.psum_out(pe_out[r*4+c]));
            end
        end
    end
endmodule
