// 三个32×32块的存储和调度：C←C+A×B；通过interface驱动所选版本的8×8阵列。
// 上层/DMA负责补零和搬运；B保留到下次显式装载，C也可保留供下一次累计。
module kwt_block32 #(parameter int TAIL_CYCLES=10 // CSA收尾10拍；普通累加无收尾，设为0
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
        TAIL,  // 可选最终加法收尾，普通版跳过
        STORE  // 固定8拍下载，写回C块
    } state_t;
    localparam int LAST_WAIT=5; // 末向量发射后到压缩完成的固定拍数。
    logic [3:0] wait_count;           // 末向量等待/尾项收尾的固定计数
    state_t state;                     // 当前块调度阶段
    logic signed [11:0] a_mem[0:1023]; // A块；仅由上层装载
    logic signed [9:0] b_mem[0:1023];  // B块；跨start驻留
    logic [31:0] c_bank_data[0:7];     // 8个独立C bank的并行读数据
    logic [1:0] tile_i,tile_j;         // 当前8×8在32×32中的位置
    logic [2:0] slot;                  // 历史和装载/结果接收计数
    logic [4:0] k;                     // 块内归约索引0～31
    logic [6:0] c_read_addr,c_write_addr; // bank内地址：5位行号＋2位列组号
    logic [95:0] a_rows;              // A独立广播总线，8行×12位
    logic [79:0] b_cols;              // B独立广播总线，8列×10位
    kwt_array_if array_bus();          // 仅连接控制与部分和，不混入A/B数据

    // 连接编译时选定的阵列版本，算术模块不混用。
    kwt_array_quad u_array(.clk(clk),.rst_n(rst_n),
        .a_rows(a_rows),.b_cols(b_cols),.bus(array_bus));

    assign busy = state!=IDLE; // 整个块任务未回到空闲阶段就保持忙。
    assign c_read_addr = state==LOAD ? {tile_i,slot,tile_j} : {c_addr[9:5],c_addr[4:3]}; // LOAD读取当前整行，其余时间服务主机标量读。
    assign c_data = c_bank_data[c_addr[2:0]]; // 主机列低3位选择bank，外部标量端口不变。
    assign c_write_addr = {tile_i,array_bus.out_row,tile_j}; // 同一输出行的8个bank共用地址。

    // 组合控制：局部C加载、A/B广播和部分和回收相互独立。
    always_comb begin
        array_bus.load = state==LOAD; // 仅在历史和装载阶段写入PE。
        array_bus.step = state==RUN; // RUN阶段每拍发射，模块不能延长或缩短间隔。
        array_bus.flush = state==FLUSH; // 专用一拍状态发出统一排空命令。
        for (int r=0;r<8;r++) begin // 把行号限制为3位，再拼接子块号与K索引读取A/B。
            array_bus.load_data[r*32+:32] = c_bank_data[r]; // 8个bank并行提供旧部分和。
            a_rows[r*12+:12] = a_mem[{tile_i,3'(r),k}];
            b_cols[r*10+:10] = b_mem[{k,tile_j,3'(r)}];
        end
    end

    // A/B独立装载，计算结束后继续驻留。
    always_ff @(posedge clk) begin
        if (a_load_valid && state==IDLE) a_mem[a_load_addr]<=a_load_data; // 接收12位A。
        if (b_load_valid && state==IDLE) b_mem[b_load_addr]<=b_load_data; // 接收10位B。
    end

    for (genvar bank=0;bank<8;bank++) begin : c_banks // 常量bank索引，综合时保留8个独立存储。
        logic [31:0] words[0:127]; // 本bank：32行×4个列组，每拍只写一个字
        assign c_bank_data[bank]=words[c_read_addr]; // 8个bank在同一时钟并行供一整行。
        // 主机标量写与阵列整行写互斥，复用本bank唯一写口。
        always_ff @(posedge clk) begin
            if (state==IDLE && c_load_valid && c_load_addr[2:0]==3'(bank))
                words[{c_load_addr[9:5],c_load_addr[4:3]}]<=c_load_data; // 仅目标bank接收主机写入。
            else if (state==STORE)
                words[c_write_addr]<=array_bus.out_data[bank*32+:32]; // 结果行8个字同拍分别写入8个bank。
        end
    end

    // 固定日程：上传8拍→32组向量连续发射→末向量等待→flush→按版本收尾→下载8拍。
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin // 只复位控制，三个矩阵块随后由外部显式装载。
            state<=IDLE; tile_i<=0; tile_j<=0; slot<=0; k<=0;
            done<=0; wait_count<=0;
        end else begin // done仅在最后一个8×8下载完成时打一拍。
            done<=0;
            case (state)
                IDLE: if (start) begin // 开始任务，不允许计算中途重启。
                    tile_i<=0; tile_j<=0; slot<=0; state<=LOAD;
                end
                LOAD: begin // 8拍旧部分和整行推入原PE寄存器。
                    if (slot==7) begin // 上传结束，下一拍发射首个K向量。
                        slot<=0; k<=0; state<=RUN;
                    end else slot<=slot+1'b1; // 按块内行序读取下一个旧C。
                end
                RUN: begin // 每拍发射一组K向量，连续32拍，不等待下游反馈。
                    if (k==31) begin state<=WAIT; wait_count<=4'(LAST_WAIT); end // 末向量进入乘法流水。
                    else k<=k+1'b1; // 下一拍立即提交下一组A/B。
                end
                WAIT: begin // 零乘数也消耗相同的流水拍数，不提前结束。
                    if (wait_count==1) state<=FLUSH; // 到达确定的最终写回时间。
                    else wait_count<=wait_count-1'b1; // 每拍递减，不读取busy/ready。
                end
                FLUSH: begin // 向阵列发出一拍排空命令。
                    if(TAIL_CYCLES==0) state<=STORE; // 普通累加无剩余carry，直接下载。
                    else begin state<=TAIL; wait_count<=4'(TAIL_CYCLES); end // CSA先完成共享最终加法。
                end
                TAIL: begin // 等待CSA阵列固定收尾，普通版本不进入此阶段。
                    if (wait_count==1) state<=STORE; // 下一拍开始连续接收64项。
                    else wait_count<=wait_count-1'b1; // 收尾拍数与数据内容无关。
                end
                STORE: begin // 每拍写C并推进计数，输出不支持停顿。
                    if (slot==7) begin // 当前8×8的8行64个结果已写完。
                        slot<=0;
                        if (tile_i!=3) begin tile_i<=tile_i+1'b1; state<=LOAD; end // 先遍历四个行子块。
                        else if (tile_j!=3) begin tile_i<=0; tile_j<=tile_j+1'b1; state<=LOAD; end // 再移到下一列子块。
                        else begin done<=1; state<=IDLE; end // 整个32×32任务固定日程结束。
                    end else slot<=slot+1'b1; // 继续下载同一子块的下一行。
                end
                default: state<=IDLE; // 未定义状态回到任务边界。
            endcase
        end
    end
endmodule
