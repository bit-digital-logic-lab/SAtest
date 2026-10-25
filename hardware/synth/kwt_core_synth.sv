// 综合用平面端口封装：仅暴露8×8核心，排除32×32 A/B/C块存储，供当前CSA核心面积映射。
module kwt_core_synth (
    input logic clk,rst_n,           // 时钟、低有效复位
    input logic [95:0] a_rows,       // 独立A12行输入
    input logic [79:0] b_cols,       // 独立W10列输入
    input logic load,               // 旧部分和上传节拍
    input logic [31:0] load_data,    // 上传的INT32旧部分和
    input logic step,flush,          // 外部确定的发射与收尾节拍
    output logic [5:0] out_addr,     // 下载元素的8×8局部地址
    output logic [31:0] out_data     // 原部分和寄存器中的下载数据
);
    kwt_array_if bus();             // 仅连接控制与部分和，A/B使用独立数据端口
    assign bus.load=load; // 上传使能直接进入核心，不另加状态机。
    assign bus.load_data=load_data; // 旧部分和直接送入原累计寄存器。
    assign bus.step=step; // 发射节拍由上层保证，封装不引入反压。
    assign bus.flush=flush; // 三压二收尾及统一下载使用原控制信号。
    assign out_addr=bus.out_addr; // 保留核心的实际下载地址。
    assign out_data=bus.out_data; // 核心结果不增加额外输出寄存器。
    // 核心直接连接四个4×4共享加法子块。
    kwt_array_quad u_core(.clk(clk),.rst_n(rst_n),.a_rows(a_rows),.b_cols(b_cols),.bus(bus));
endmodule
