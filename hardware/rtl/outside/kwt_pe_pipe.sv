// 加法PE保存四个轮转部分和。
module kwt_pe_pipe (
    input logic clk,                         // 时钟
    input logic rst_n,                       // 低有效复位
    input logic load,                        // 部分和装载
    input logic [1:0] load_slot,             // 装载槽号
    input logic [31:0] load_data,             // 装载数据
    input logic compute_step,                 // 推进一个乘积节拍
    input logic product_enable,               // 当前乘积有效
    input logic signed [21:0] product,        // 有符号乘积
    input logic drain_select,                 // 选择本PE输出
    input logic drain_step,                 // 固定下载节拍
    output logic [31:0] drain_data             // 当前部分和
);
    logic [31:0] sum [0:3];                  // 四个轮转部分和
    logic [1:0] head;                        // 排空槽指针
    logic [1:0] slot_ptr;                    // 乘积写回槽指针
    logic stage_valid;                       // 第二拍提交有效
    logic [1:0] stage_slot;                  // 延迟写回槽记录
    logic [16:0] stage_low;                  // 低半字和及进位
    logic [16:0] stage_high_sum;             // 高半字预加结果
    logic [31:0] operand_sum;                // 完整回绕结果
    logic [16:0] high_sum;                   // 高半字加进位
    logic [16:0] high_a;                     // 部分和高半字
    logic [16:0] high_b;                     // 乘积高半字
    logic signed [31:0] product_ext;         // 乘积符号扩展
    logic [16:0] low_sum_ext;                // 低半字扩展加法

    // 低半字和高半字操作数分拍寄存。
    always_comb begin
        product_ext = {{10{product[21]}}, product}; // 复制乘积符号位，扩展为32位加法操作数。
        low_sum_ext = {1'b0, sum[slot_ptr][15:0]} + {1'b0, product_ext[15:0]}; // 选中轮转槽的低16位与乘积相加，额外一位保留进位。
        high_a = {1'b0, sum[slot_ptr][31:16]}; // 部分和高16位补零，供高半字预加。
        high_b = {1'b0, product_ext[31:16]}; // 乘积高16位补零，供高半字预加。
        high_sum = stage_high_sum + {16'b0, stage_low[16]}; // 第二拍把低半字进位加到已寄存的高半字预加结果。
        operand_sum = {high_sum[15:0], stage_low[15:0]}; // 拼接高低16位，丢弃INT32之外的进位。
        drain_data = sum[head]; // 输出取当前排空读槽，下载未开始时head不变。
    end

    // 每拍轮转槽号；无效乘积只推进指针，不触碰加法流水寄存器。
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin // 复位四个部分和槽及读写指针，清除加法有效位。
            sum[0] <= '0; sum[1] <= '0; sum[2] <= '0; sum[3] <= '0;
            head <= '0; slot_ptr <= '0;
            stage_valid <= 1'b0; stage_slot <= '0;
            stage_low <= '0; stage_high_sum <= '0;
        end else begin // 正常运行时允许上拍提交与本拍发射重叠。
            if (stage_valid) sum[stage_slot] <= operand_sum; // 按延迟槽号写回，避免使用已经前进的轮转指针。
            if (load) sum[load_slot] <= load_data; // 上层装入该槽的历史部分和。
            if (drain_select && drain_step) head <= head + 1'b1; // 本PE对应的下载拍到来时，切换到下一读槽。
            if (compute_step) begin // 每个乘积位置都推进写槽，包括零乘积位置。
                slot_ptr <= slot_ptr + 1'b1;
                if (product_enable) begin // 乘积非零才锁存加法数据及写回槽号。
                    stage_valid <= 1'b1;
                    stage_slot <= slot_ptr;
                    stage_low <= low_sum_ext;
                    stage_high_sum <= high_a + high_b;
                end else begin // 零乘积不发射加法，部分和与算术寄存器保持。
                    stage_valid <= 1'b0;
                end
            end else begin // 无消费节拍时不发射新加法；旧提交仍可完成。
                stage_valid <= 1'b0;
            end
        end
    end
endmodule
