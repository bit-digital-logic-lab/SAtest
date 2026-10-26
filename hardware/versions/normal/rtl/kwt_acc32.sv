// 普通单拍累加器：32位部分和与符号扩展乘积直接相加，没有CSA或carry驻留状态。
// 供kwt_pe_mac使用，上传/下载复用同一个sum寄存器。
module kwt_acc32 (
    input logic clk,rst_n, // 时钟、低有效复位
    input logic load, // 上传或下载时移动原部分和
    input logic [31:0] load_data, // 下一行同列的原部分和
    input logic valid, // 非零乘积更新使能
    input logic signed [21:0] product, // 三拍乘法器结果
    output logic [31:0] sum // 唯一驻留部分和，也是移位输出
);
    logic [31:0] product32; // 有符号乘积扩展到INT32
    assign product32={{10{product[21]}},product}; // 高位复制符号位。
    // 上传/移位优先；计算每拍直接加一次，INT32之外的进位丢弃。
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) sum<=0; // 复位原部分和。
        else if(load) sum<=load_data; // 整行推入旧和或推出结果，不增加影子寄存器。
        else if(valid) sum<=sum+product32; // 一个时钟周期完成普通二输入加法并写回。
        // 零乘积和空拍保持数据，外部节拍继续推进。
    end
endmodule
