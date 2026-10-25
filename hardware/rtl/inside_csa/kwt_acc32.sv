// 两拍累计加法器：接收压缩sum及最终carry；自身acc寄存器兼作部分和装入/排出节点。
module kwt_acc32 (
    input logic clk, rst_n,           // 时钟、低有效复位
    input logic load,                // 空闲装入或统一移位，复用acc本身
    input logic [31:0] load_data,     // 行序链的后一级部分和
    input logic valid,               // 新加数有效，间隔至少两拍
    input logic [31:0] data,         // 压缩sum或最后反馈carry
    output logic [31:0] sum         // 驻留的最终INT32部分和，也是链输出
);
    logic [31:0] acc;                // 唯一完整累计结果寄存器，兼作移位节点
    logic stage_valid;                // 第二拍写回标记
    logic [15:0] low_q, high_a,high_b; // 首拍低位和、高位操作数
    logic carry_q;                    // 低16位向高16位的进位
    logic [16:0] low_full;            // 组合低位加法，保留第17位
    logic [15:0] high_sum;            // 第二拍高位加法，INT32之外进位丢弃
    assign low_full={1'b0,acc[15:0]}+{1'b0,data[15:0]}; // 首拍计算低位和及进位。
    assign high_sum=high_a+high_b+carry_q; // 次拍把低位进位并入高位。
    assign sum=acc; // 直接连接原累计寄存器，无导出影子副本。

    // 上传、下载都写同一acc；计算时只有两拍加法中间寄存器参与流水。
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin // 复位清除累计值和流水有效位。
            acc<=0; stage_valid<=0; low_q<=0; high_a<=0; high_b<=0; carry_q<=0;
        end else if (load) begin // 移位仅在算术已空时进行，直接替换原acc。
            acc<=load_data; stage_valid<=0;
        end else begin // 普通计算阶段接收新加数或提交上拍结果。
            stage_valid<=valid;
            if (stage_valid) acc<={high_sum,low_q}; // 第二拍完成高位加法并回到驻留位置。
            if (valid) begin // 第一拍锁存低位结果与下一拍所需高位操作数。
                low_q<=low_full[15:0]; carry_q<=low_full[16];
                high_a<=acc[31:16]; high_b<=data[31:16];
            end
        end
    end
endmodule
