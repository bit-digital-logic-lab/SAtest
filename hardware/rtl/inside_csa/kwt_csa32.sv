// 反馈三压二：两拍收集两个乘积；sum前送累计器，carry留在本模块第三操作数寄存器。
// flush先补齐单项，再送出反馈carry；不保存双上下文或完整输出矩阵。
module kwt_csa32 (
    input logic clk, rst_n,            // 时钟、低有效复位
    input logic clear,                 // 装载新部分和时清除旧压缩状态
    input logic valid, enable,         // 乘积位置有效、非零数据使能
    input logic signed [21:0] product, // 独立乘法器的三拍结果
    input logic flush,                // 停止输入后，送出剩余项与反馈进位
    output logic out_valid,           // 本拍有一个32位数送往累计加法器
    output logic [31:0] out_data      // 正常为压缩sum，最后为剩余carry
);
    typedef enum logic [2:0] {
        RUN,  // 正常收集两个乘积
        PAD,  // 把最后的单项与零配对
        GAP,  // 留出累计器两拍反馈所需间隔
        TAIL, // 送出第三操作数寄存器中剩余的carry
        DONE  // 等最后一个前送数进入累计器
    } state_t;
    state_t state;                    // 压缩与收尾阶段
    logic first_valid, first_enable;  // 首项占位与非零标记
    logic [21:0] first_product;        // 只缓存22位首项，不额外扩成32位寄存器
    logic [31:0] feedback;            // 三压二第三输入：上一轮的carry
    logic [31:0] x,y;                 // 两个乘积的INT32组合扩展
    logic [31:0] sum_bits,carry_bits; // 无跨位进位的压缩结果

    assign x = first_enable ? {{10{first_product[21]}},first_product} : 32'b0; // 首项零值不使用旧数据。
    assign y = (state==RUN && valid && enable) ? {{10{product[21]}},product} : 32'b0; // 收尾第二项补零。
    assign sum_bits = x ^ y ^ feedback; // sum直接前送，不反馈完整部分和。
    assign carry_bits = ((x&y)|(x&feedback)|(y&feedback)) << 1; // carry左移对齐，回到第三输入寄存器。

    // 仅两项中有非零乘积时更新压缩数据；零值位置仍推进配对节拍。
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin // 复位清空反馈和所有有效位。
            state<=RUN; first_valid<=0; first_enable<=0;
            first_product<=0; feedback<=0; out_valid<=0; out_data<=0;
        end else if (clear) begin // 原部分和重装后，从全新的压缩序列开始。
            state<=RUN; first_valid<=0; first_enable<=0; feedback<=0; out_valid<=0;
        end else begin // 默认无前送数据；只有完成一对或送尾项时置有效。
            out_valid<=0;
            case (state)
                RUN: begin // 每两拍产生一个sum，carry就地反馈。
                    if (flush) state<=PAD; // 收尾命令优先，乘法流水应已由上层排净。
                    else if (valid) begin // 只按有效乘积位置计数，允许上游间隔发射。
                        if (!first_valid) begin // 第一项占位；零乘积不更新数据寄存器。
                            first_valid<=1; first_enable<=enable;
                            if (enable) first_product<=product; // 非零时才锁存22位乘积。
                        end else begin // 第二项到达，消费配对并释放首项位置。
                            first_valid<=0;
                            if (first_enable || enable) begin // 全零对保持反馈，不启动后级算术。
                                out_data<=sum_bits; out_valid<=1; feedback<=carry_bits;
                            end
                        end
                    end
                end
                PAD: begin // 奇数个乘积时，最后首项与0及反馈一起压缩。
                    if (first_valid && first_enable) begin // 零首项无需算术，反馈留到TAIL处理。
                        out_data<=sum_bits; out_valid<=1; feedback<=carry_bits;
                    end
                    first_valid<=0; first_enable<=0; state<=GAP;
                end
                GAP: state<=TAIL; // 前送sum被累计器接收，下一拍才发尾项。
                TAIL: begin // 剩余carry必须累计一次，不能直接丢弃。
                    if (feedback!=0) begin out_data<=feedback; out_valid<=1; end // 零尾项跳过更新。
                    feedback<=0; state<=DONE;
                end
                DONE: state<=RUN; // 最后前送数据已交给累计器，累计器按固定两拍日程完成最后写回。
                default: state<=RUN; // 未定义控制状态回到接收阶段。
            endcase
        end
    end
endmodule
