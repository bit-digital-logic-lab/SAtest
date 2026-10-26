// 4×4驻留块：A12、W10直接送到16个PE，不经column层；块内管理水平及上下行部分和通道。
// 部分和从底行上传，从顶行按行下载；所有移位使用PE原累计寄存器，无额外行间寄存器。
module kwt_quad4x4 (
    input logic clk, rst_n,          // 时钟、低有效复位
    input logic [47:0] a_rows,       // 独立A端口：四个12位行输入
    input logic [39:0] b_cols,       // 独立B端口：四个10位列输入
    input logic valid,              // 外层规定的A/B输入节拍
    input logic load,               // 按本块行序上传旧部分和
    input logic shift,               // 固定下载移位
    input logic row_issue, // CSA本块预定出行拍
    input logic [1:0] row_select, // 共享加法器当前处理行
    kwt_psum_row_if.sink block_in,       // 本块底行输入，来自下方4×4或外部输入行
    kwt_psum_row_if.source block_out    // 本块顶行四个原sum寄存器并行输出
);
    kwt_psum_if pe_out[0:15]();     // 16个原累计寄存器输出，索引=行×4+列
    logic [31:0] carries[0:15]; // CSA每个PE驻留进位
    logic [127:0] row_sums,row_carries,row_results; // 共享四路加法通路
    logic row_commit; // 两拍加法写回标记
    logic [1:0] commit_row; // 写回目标行
    begin : shared_add // 每个4×4只有四个最终加法器。
        for (genvar c=0;c<4;c++) begin : select_lane
            // interface索引静态展开后，再选择本拍行，避免动态interface寻址。
            logic [31:0] sums[0:3]; // 当前列四行sum连线
            for (genvar r=0;r<4;r++) begin : sum_rows
                assign sums[r]=pe_out[r*4+c].data; // 直接读PE原寄存器。
            end
            assign row_sums[c*32+:32]=sums[row_select]; // 选本拍送出的行。
            assign row_carries[c*32+:32]=carries[row_select*4+c]; // 选择对应进位。
        end
        kwt_row_adder u_add(.clk(clk),.rst_n(rst_n),.issue(row_issue),.row(row_select),
            .sums(row_sums),.carries(row_carries),.commit(row_commit),
            .commit_row(commit_row),.results(row_results));
    end
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
            begin : csa_pe // A/B都直接到达本PE，内部只有乘法→两数驻留压缩。
                kwt_pe_csa u_pe(.clk(clk),.rst_n(rst_n),
                    .a($signed(a_rows[r*12+:12])),.b($signed(b_cols[c*10+:10])),
                    .compute(valid),.init(load),.shift(shift),
                    .finalize(row_commit && commit_row==2'(r)),.final_data(row_results[c*32+:32]),
                    .carry_data(carries[r*4+c]),
                    .psum_in(next_sum),.psum_out(pe_out[r*4+c]));
            end
        end
    end
endmodule
