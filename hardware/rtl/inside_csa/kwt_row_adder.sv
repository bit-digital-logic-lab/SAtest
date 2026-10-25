// 四路共享两拍加法器：4×4每次送一行sum/carry，结果直接写回选中的原PE行。
// 第1拍计算低16位并锁存高位，第2拍由PE采样高位加法与低位拼接结果。
module kwt_row_adder (
    input logic clk, rst_n, // 时钟、低有效复位
    input logic issue, // 本块本拍送出一行，固定隔拍发射
    input logic [1:0] row, // 当前发送行号
    input logic [127:0] sums, carries, // 四个PE的两数表示
    output logic commit, // 次拍边沿写回四个PE
    output logic [1:0] commit_row, // 与流水结果对齐的行号
    output logic [127:0] results // 四个INT32最终结果
);
    logic [15:0] low_q[0:3], hi_a[0:3], hi_b[0:3]; // 四路首拍结果及高位
    logic [3:0] carry_q; // 四路低半字进位
    for (genvar c=0;c<4;c++) begin : lanes // 一行四路，每块仅此四个CPA。
        logic [16:0] low_full; // 保留低位进位
        logic [15:0] high_sum; // 丢弃INT32之外溢出
        assign low_full={1'b0,sums[c*32+:16]}+{1'b0,carries[c*32+:16]}; // 首拍低位加法。
        assign high_sum=hi_a[c]+hi_b[c]+carry_q[c]; // 次拍高位带入低位进位。
        assign results[c*32+:32]={high_sum,low_q[c]}; // 第二拍结果直接回原PE。
        // 只在预定出行拍更新加法中间数据。
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin // 复位流水数据。
                low_q[c]<=0; hi_a[c]<=0; hi_b[c]<=0; carry_q[c]<=0;
            end else if (issue) begin // 第一拍锁存本行四个操作数的分段结果。
                low_q[c]<=low_full[15:0]; carry_q[c]<=low_full[16];
                hi_a[c]<=sums[c*32+16+:16]; hi_b[c]<=carries[c*32+16+:16];
            end // 间隔拍保持数据供第二拍写回。
        end
    end
    // 行号和写回标记随首拍锁存，下一边沿完成第二拍写回。
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin commit<=0; commit_row<=0; end // 复位无待写回行。
        else begin // 按固定issue日程推进，无反压。
            commit<=issue;
            if (issue) commit_row<=row; // 只在出行时更新目标行。
        end
    end
endmodule
