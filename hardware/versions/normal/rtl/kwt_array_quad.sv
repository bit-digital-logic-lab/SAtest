// 8×8驻留阵列：四个4×4广播子块；大阵列只管理4×4块的连接和下载节拍，块内PE通道由各块管理。
// 每拍上传/下载一整行8个INT32，完整8×8各需8拍；左右块并行、上下块按同列移位。
module kwt_array_quad (
    input logic clk, rst_n,          // 时钟、低有效复位
    input logic [95:0] a_rows,       // 独立A端口：8行×12位
    input logic [79:0] b_cols,       // 独立B端口：8列×10位
    kwt_array_if.compute bus        // 控制、历史和上传及结果下载接口；A/B由独立端口提供
);
    logic draining;                 // 固定8拍连续下载阶段
    logic [2:0] drain_row;          // 当前下载行号0～7
    logic shift_en;                 // 下载阶段每拍移动一级，不接受反压
    kwt_psum_row_if block_in[0:3](),block_out[0:3](); // 各小块的四列整行通道
    assign block_in[0].data=block_out[2].data; // 左上块从左下块接收下一行。
    assign block_in[1].data=block_out[3].data; // 右上块从右下块接收下一行。
    assign block_in[2].data=bus.load ? bus.load_data[127:0] : 128'b0; // 新行左半注入最底部。
    assign block_in[3].data=bus.load ? bus.load_data[255:128] : 128'b0; // 新行右半同步注入。
    assign bus.out_data={block_out[1].data,block_out[0].data}; // 左右顶行拼成8个并行结果。
    assign bus.out_row=drain_row; // 输出行号随固定下载拍递增。
    assign shift_en=draining; // 下载8拍，每拍上下同列前移一行。

    for (genvar q=0;q<4;q++) begin : blocks // q=0左上、1右上、2左下、3右下，依块下载。
        kwt_quad4x4 u_block(.clk(clk),.rst_n(rst_n),
            .a_rows(a_rows[(q/2)*48+:48]),.b_cols(b_cols[(q%2)*40+:40]),
            .valid(bus.step),.load(bus.load),.shift(shift_en),
            .block_in(block_in[q]),.block_out(block_out[q]));
    end

    // 上层已等待三拍乘法和单拍累加；本阵列只负责固定8拍下载。
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin // 复位控制状态，C随后由8拍上传填满。
            draining<=0; drain_row<=0;
        end else begin // 没有ready/busy反馈，所有阶段由固定计数推进。
            if (bus.flush) begin // 普通累加已写回，下一拍即可直接输出整行。
                drain_row<=0; draining<=1;
            end
            if (shift_en) begin // 无条件移动原部分和链，外部必须按拍接收。
                if (drain_row==7) begin draining<=0; drain_row<=0; end // 恰好8行后停止。
                else drain_row<=drain_row+1'b1; // 输出下一行8个元素。
            end
        end
    end
endmodule
