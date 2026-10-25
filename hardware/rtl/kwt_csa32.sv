// 驻留三压二：每拍把一个乘积与原sum、carry压成两个数，进位始终延后传播。
// 与kwt_pe_csa连接；最终两数之和交给4×4共享加法组，结果复用sum寄存器。
module kwt_csa32 (
    input logic clk, rst_n, // 时钟、低有效复位
    input logic load, // 上传或下载时移动原sum
    input logic [31:0] load_data, // 链后继部分和
    input logic valid, // 非零乘积更新使能，零位置保持数据
    input logic signed [21:0] product, // 完整乘积
    input logic finalize, // 最终加法写回使能
    input logic [31:0] final_data, // 共享加法结果
    output logic [31:0] sum_data, carry_data // 两个驻留压缩操作数
);
    logic [31:0] p32; // 乘积符号扩展
    assign p32={{10{product[21]}},product}; // 扩成INT32参与逐位压缩。
    // 装入优先于收尾，收尾优先于新乘积；上层按固定日程避免阶段重叠。
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin // 复位两数状态。
            sum_data<=0; carry_data<=0;
        end else if (load) begin // 上传下载复用原sum，进位清零。
            sum_data<=load_data; carry_data<=0;
        end else if (finalize) begin // 最终CPA结果回到原sum，无影子输出页。
            sum_data<=final_data; carry_data<=0;
        end else if (valid) begin // 三数变两数，没有跨位进位链。
            sum_data<=sum_data ^ carry_data ^ p32;
            carry_data<=((sum_data & carry_data)|(sum_data & p32)|(carry_data & p32))<<1;
        end // 零乘积或无输入时保持两数，时钟日程仍继续。
    end
endmodule
