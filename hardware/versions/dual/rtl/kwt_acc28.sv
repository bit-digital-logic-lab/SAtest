// 双乘PE的单拍28位CPA与唯一驻留和；三压二保持组合，上传和下载复用sum寄存器。
module kwt_acc28 (
    input logic clk,rst_n, // 时钟、低有效复位
    input logic load,valid, // 行移位优先于有效非零乘积的累加
    input logic [31:0] load_data, // 原部分和，取低28位；输出再符号扩展回32位
    input logic [27:0] sum_bits,carry_bits, // 三压二组合输出的两数
    output logic [27:0] sum // 唯一驻留部分和，补码模2^28回绕
);
    // 无反压：每拍可接收一对乘积；零对保持数据，移位复用原寄存器。
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) sum<=0; // 清空历史和。
        else if(load) sum<=load_data[27:0]; // 上传或下载时整行前移。
        else if(valid) sum<=sum_bits+carry_bits; // 单拍CPA，下一对乘积无需停顿。
    end
endmodule
