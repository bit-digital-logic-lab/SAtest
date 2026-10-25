// 三个32×32块的存储和调度：C←C+A×B；通过interface驱动三种8×8计算阵列之一。
// 上层/DMA负责补零和搬运；B保留到下次显式装载，C也可保留供下一次累计。
module kwt_block32 #(parameter int ARCH=0 // 0=阵列外加法，1=驻留传统加法，2=驻留三压二
) (
    input logic clk, rst_n,           // 时钟、低有效异步复位
    input logic a_load_valid,         // A端口写入有效，与B端口独立
    input logic [9:0] a_load_addr,    // A块行优先地址
    input logic signed [11:0] a_load_data, // 独立12位激活端口
    input logic b_load_valid,         // B端口写入有效，可与A同拍写入
    input logic [9:0] b_load_addr,    // B块行优先地址
    input logic signed [9:0] b_load_data, // 独立10位权重端口
    input logic c_load_valid,         // 历史部分和上传有效
    input logic [9:0] c_load_addr,    // C块行优先地址
    input logic [31:0] c_load_data,   // bias或上一K块的部分和
    input logic start,                // 空闲时打一拍，按固定日程计算整块
    output logic busy, done,          // 计算中、整块完成脉冲
    input logic [9:0] c_addr,         // 空闲时读取C的局部地址
    output logic [31:0] c_data        // C的组合读结果
);
    typedef enum logic [2:0] {
        IDLE,  // 等待装载或开始
        LOAD,  // 把8×8历史C送入PE
        RUN,   // 连续提交32个K向量
        WAIT,  // 固定等待末向量的算术流水
        FLUSH, // 发出部分和排空命令
        TAIL,  // 三压二固定十拍尾项收尾
        STORE  // 固定64拍下载，写回C块
    } state_t;
    localparam int INPUT_II=(ARCH==0) ? 4 : ((ARCH==1) ? 3 : 1); // 三种架构的固定向量发射间隔。
    localparam int TAIL_CYCLES=10; // flush后：两块交替四行共8拍，加2拍固定收尾余量。
    localparam int LAST_WAIT=(ARCH==0) ? 8 : ((ARCH==1) ? 4 : 5); // 末向量发射后到加法提交的固定拍数。
    logic [1:0] issue_phase;          // 输入节拍相位，只由固定计数推进
    logic [3:0] wait_count;           // 末向量等待/尾项收尾的固定计数
    state_t state;                     // 当前块调度阶段
    logic signed [11:0] a_mem[0:1023]; // A块；仅由上层装载
    logic signed [9:0] b_mem[0:1023];  // B块；跨start驻留
    logic [31:0] c_mem[0:1023];        // C块；保存old_sum或计算结果
    logic [1:0] tile_i,tile_j;         // 当前8×8在32×32中的位置
    logic [5:0] slot;                  // 历史和装载/结果接收计数
    logic [4:0] k;                     // 块内归约索引0～31
    logic [5:0] upload_addr;           // 当前装入项在8×8内的实际行列地址
    logic [9:0] c_read_addr,c_write_addr; // C块读写地址
    logic [95:0] a_rows;              // A独立广播总线，8行×12位
    logic [79:0] b_cols;              // B独立广播总线，8列×10位
    kwt_array_if array_bus();          // 仅连接控制与部分和，不混入A/B数据

    if (ARCH!=0) begin : quad_version // ARCH为1或2时使用四个4×4组成的驻留阵列。
        kwt_array_quad #(.CSA(ARCH==2),.TAIL_CYCLES(TAIL_CYCLES)) u_array(.clk(clk),.rst_n(rst_n),
            .a_rows(a_rows),.b_cols(b_cols),.bus(array_bus));
    end else begin : pipe_version // ARCH为0时使用乘积流水、部分和轮转版本。
        kwt_array_pipe u_array(.clk(clk),.rst_n(rst_n),
            .a_rows(a_rows),.b_cols(b_cols),.bus(array_bus));
    end

    assign busy = state!=IDLE; // 整个块任务未回到空闲阶段就保持忙。
    // 拼接“块内8×8起点”和“8×8局部行列”，得到32×32地址。
    assign upload_addr = (ARCH==0) ? slot : {slot[5],slot[3:2],slot[4],slot[1:0]}; // 驻留版按块装入；阵列外版沿用行优先槽号。
    assign c_read_addr = state==LOAD ? {tile_i,upload_addr[5:3],tile_j,upload_addr[2:0]} : c_addr; // 装载阶段读当前8×8的C，其余阶段使用外部读地址。
    assign c_data = c_mem[c_read_addr]; // 按选定局部地址组合读取C块。
    assign c_write_addr = {tile_i,array_bus.out_addr[5:3],tile_j,array_bus.out_addr[2:0]}; // 拼接当前子块位置和输出行列，形成32×32写回地址。

    // 组合控制：局部C加载、A/B广播和部分和回收相互独立。
    always_comb begin
        array_bus.load = state==LOAD; // 仅在历史和装载阶段写入PE。
        array_bus.load_addr = slot; // 阵列外版使用此槽地址；驻留版按固定块序串行装入。
        array_bus.load_data = c_data; // 把C块读出的历史和作为PE初值。
        array_bus.step = state==RUN && issue_phase==0; // 只在预定相位发射，模块不能延长或缩短间隔。
        array_bus.flush = state==FLUSH; // 专用一拍状态发出统一排空命令。
        for (int r=0;r<8;r++) begin // 把行号限制为3位，再拼接子块号与K索引读取A/B。
            a_rows[r*12+:12] = a_mem[{tile_i,3'(r),k}];
            b_cols[r*10+:10] = b_mem[{k,tile_j,3'(r)}];
        end
    end

    // A/B使用不同数据端口和存储写使能，可以同拍装载；C上传与阵列结果回存复用C存储。
    always_ff @(posedge clk) begin
        if (a_load_valid && state==IDLE) a_mem[a_load_addr]<=a_load_data; // 空闲时接收12位A。
        if (b_load_valid && state==IDLE) b_mem[b_load_addr]<=b_load_data; // 独立接收10位B，计算后继续驻留。
        if (c_load_valid && state==IDLE) c_mem[c_load_addr]<=c_load_data; // 上传原部分和。
        else if (state==STORE) // 固定下载阶段每拍写回一个部分和，无反压握手。
            c_mem[c_write_addr]<=array_bus.out_data;
    end

    // 固定日程：上传64拍→32组向量按II发射→末向量等待→flush→CSA十拍收尾→下载64拍。
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin // 只复位控制，三个矩阵块随后由外部显式装载。
            state<=IDLE; tile_i<=0; tile_j<=0; slot<=0; k<=0;
            done<=0; issue_phase<=0; wait_count<=0;
        end else begin // done仅在最后一个8×8下载完成时打一拍。
            done<=0;
            case (state)
                IDLE: if (start) begin // 开始任务，不允许计算中途重启。
                    tile_i<=0; tile_j<=0; slot<=0; state<=LOAD;
                end
                LOAD: begin // 64个旧部分和连续推入原PE寄存器。
                    if (slot==63) begin // 上传结束，下一拍按相位0发射首个K向量。
                        slot<=0; k<=0; issue_phase<=0; state<=RUN;
                    end else slot<=slot+1'b1; // 按当前架构的块内顺序读取下一个旧C。
                end
                RUN: begin // 计算节奏只依赖ARCH和相位，不等待下游反馈。
                    if (issue_phase==2'(INPUT_II-1)) issue_phase<=0; // 到固定周期末尾，准备下一次发射。
                    else issue_phase<=issue_phase+1'b1; // 其余拍维持流水运行，不额外发射。
                    if (issue_phase==0) begin // 当前A/B向量在这一拍必定被采样。
                        if (k==31) begin state<=WAIT; wait_count<=4'(LAST_WAIT); end // 发完末向量后固定等待提交。
                        else k<=k+1'b1; // 下一组数据提前放到输入，等下一个固定发射位置。
                    end
                end
                WAIT: begin // 零乘数也消耗相同的流水拍数，不提前结束。
                    if (wait_count==1) state<=FLUSH; // 到达确定的最终写回时间。
                    else wait_count<=wait_count-1'b1; // 每拍递减，不读取busy/ready。
                end
                FLUSH: begin // 向阵列发出一拍排空命令。
                    if (ARCH==2) begin state<=TAIL; wait_count<=4'(TAIL_CYCLES); end // CSA需将各块共享加法结果写回PE。
                    else state<=STORE; // 传统及阵列外版本下一拍直接下载。
                end
                TAIL: begin // 与CSA阵列使用相同的十拍收尾日程。
                    if (wait_count==1) state<=STORE; // 下一拍开始连续接收64项。
                    else wait_count<=wait_count-1'b1; // 收尾拍数与数据内容无关。
                end
                STORE: begin // 每拍写C并推进计数，输出不支持停顿。
                    if (slot==63) begin // 当前8×8的64个结果已写完。
                        slot<=0;
                        if (tile_i!=3) begin tile_i<=tile_i+1'b1; state<=LOAD; end // 先遍历四个行子块。
                        else if (tile_j!=3) begin tile_i<=0; tile_j<=tile_j+1'b1; state<=LOAD; end // 再移到下一列子块。
                        else begin done<=1; state<=IDLE; end // 整个32×32任务固定日程结束。
                    end else slot<=slot+1'b1; // 继续下载同一子块的下一项。
                end
                default: state<=IDLE; // 未定义状态回到任务边界。
            endcase
        end
    end
endmodule
