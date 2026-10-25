// 8×8驻留阵列：四个4×4广播子块；大阵列只管理4×4块的连接和下载节拍，块内PE通道由各块管理。
// 上层每次连续上传64项，按块序、块内行序提供旧部分和；四个块依次下载，每块内从(0,0)到(3,3)，开始后每个时钟移动一级，不插空拍。
module kwt_array_quad #(parameter bit CSA=0, parameter int TAIL_CYCLES=10) (
    input logic clk, rst_n,          // 时钟、低有效复位
    input logic [95:0] a_rows,       // 独立A端口：8行×12位
    input logic [79:0] b_cols,       // 独立B端口：8列×10位
    kwt_array_if.compute bus        // 控制、历史和上传及结果下载接口；A/B由独立端口提供
);
    logic draining;                 // 固定64拍连续下载阶段
    logic [5:0] drain_addr;         // 当前下载块号与块内行列索引
    logic [3:0] finish_count;       // CSA交替出行及两拍加法倒计数
    logic shift_en;                 // 下载阶段每拍移动一级，不接受反压
    kwt_psum_if block_links[0:4](); // 四个4×4块之间的串行部分和连接，不含寄存器
    assign block_links[4].data=bus.load ? bus.load_data : 32'b0; // 上传从最后一块尾部注入，下载时补零。
    assign bus.out_data=block_links[0].data; // 直接读取第一小块的链首原累计值。
    assign bus.out_addr={drain_addr[5],drain_addr[3:2],drain_addr[4],drain_addr[1:0]}; // 块号+块内行列转成8×8行优先地址。
    assign shift_en=draining; // 下载固定64拍，四小块按统一节拍推进。

    for (genvar q=0;q<4;q++) begin : blocks // q=0左上、1右上、2左下、3右下，依块下载。
        // 倒计数10/9送行0，8/7送行1；偶数块先出、奇数块下一拍出。
        kwt_quad4x4 #(.CSA(CSA)) u_block(.clk(clk),.rst_n(rst_n),
            .a_rows(a_rows[(q/2)*48+:48]),.b_cols(b_cols[(q%2)*40+:40]),
            .valid(bus.step),.load(bus.load),.shift(shift_en),
            .row_issue(CSA && finish_count>2 && (finish_count[0]==1'(q%2))),
            .row_select(2'((TAIL_CYCLES-int'(finish_count))/2)),
            .block_in(block_links[q+1]),.block_out(block_links[q]));
    end

    // 上层已按架构等待乘法与加法流水；阵列只执行预定收尾和下载拍数。
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin // 复位控制状态，C随后由64拍上传填满。
            draining<=0; drain_addr<=0; finish_count<=0;
        end else begin // 没有ready/busy反馈，所有阶段由固定计数推进。
            if (bus.flush) begin // 三压二八拍交替出行加两拍余量；传统版可立即进入下载。
                drain_addr<=0;
                if (CSA) finish_count<=4'(TAIL_CYCLES); // 相邻块交替出行，共八个出行拍和两拍收尾。
                else draining<=1; // 传统加法已由块控制器固定等待完成。
            end
            if (finish_count!=0) begin // 每拍倒数，不随零乘积或数据内容改变。
                finish_count<=finish_count-1'b1;
                if (finish_count==1) draining<=1; // 固定收尾完成后，下一拍起连续下载。
            end
            if (shift_en) begin // 无条件移动原部分和链，外部必须按拍接收。
                if (drain_addr==63) begin draining<=0; drain_addr<=0; end // 恰好64项后停止。
                else drain_addr<=drain_addr+1'b1; // 按块编号，每块内按行从左到右。
            end
        end
    end
endmodule
