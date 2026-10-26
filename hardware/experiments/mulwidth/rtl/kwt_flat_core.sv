// 实验用扁平 PE 阵列：不实现 4×4 行移位，只测“每 PE M 个乘法器”的核心面积。
// M=1/2/4/8 分别对应 1/2/4/8 个 A12×W10 乘法器；ROWS×COLS 为输出 tile。
module kwt_flat_core #(
    parameter int ROWS=8,
    parameter int COLS=8,
    parameter int M=1
) (
    input logic clk, rst_n,
    input logic [ROWS*M*12-1:0] a_rows, // 每行 M 个相邻 K 的 A12
    input logic [COLS*M*10-1:0] b_cols, // 每列 M 个相邻 K 的 W10
    input logic valid,                  // 固定节拍，无反压
    output logic [ROWS*COLS*32-1:0] out_data // 每个输出 32 位符号扩展结果
);
    for (genvar r=0;r<ROWS;r++) begin : rows
        for (genvar c=0;c<COLS;c++) begin : cols
            kwt_psum_if pin(), pout(); // 实验核心不做行移位，psum_in 固定 0
            assign pin.data=32'b0;
            assign out_data[(r*COLS+c)*32+:32]=pout.data;
            if (M==1) begin : m1
                kwt_pe_m1 u_pe(.clk(clk),.rst_n(rst_n),
                    .a($signed(a_rows[(r*M+0)*12+:12])),
                    .b($signed(b_cols[(c*M+0)*10+:10])),
                    .compute(valid),.init(1'b0),.shift(1'b0),
                    .psum_in(pin),.psum_out(pout));
            end else if (M==2) begin : m2
                kwt_pe_dual u_pe(.clk(clk),.rst_n(rst_n),
                    .a0($signed(a_rows[(r*M+0)*12+:12])),
                    .a1($signed(a_rows[(r*M+1)*12+:12])),
                    .b0($signed(b_cols[(c*M+0)*10+:10])),
                    .b1($signed(b_cols[(c*M+1)*10+:10])),
                    .compute(valid),.init(1'b0),.shift(1'b0),
                    .psum_in(pin),.psum_out(pout));
            end else if (M==4) begin : m4
                kwt_pe_m4 u_pe(.clk(clk),.rst_n(rst_n),
                    .a0($signed(a_rows[(r*M+0)*12+:12])),
                    .a1($signed(a_rows[(r*M+1)*12+:12])),
                    .a2($signed(a_rows[(r*M+2)*12+:12])),
                    .a3($signed(a_rows[(r*M+3)*12+:12])),
                    .b0($signed(b_cols[(c*M+0)*10+:10])),
                    .b1($signed(b_cols[(c*M+1)*10+:10])),
                    .b2($signed(b_cols[(c*M+2)*10+:10])),
                    .b3($signed(b_cols[(c*M+3)*10+:10])),
                    .compute(valid),.init(1'b0),.shift(1'b0),
                    .psum_in(pin),.psum_out(pout));
            end else if (M==8) begin : m8
                kwt_pe_m8 u_pe(.clk(clk),.rst_n(rst_n),
                    .a0($signed(a_rows[(r*M+0)*12+:12])),
                    .a1($signed(a_rows[(r*M+1)*12+:12])),
                    .a2($signed(a_rows[(r*M+2)*12+:12])),
                    .a3($signed(a_rows[(r*M+3)*12+:12])),
                    .a4($signed(a_rows[(r*M+4)*12+:12])),
                    .a5($signed(a_rows[(r*M+5)*12+:12])),
                    .a6($signed(a_rows[(r*M+6)*12+:12])),
                    .a7($signed(a_rows[(r*M+7)*12+:12])),
                    .b0($signed(b_cols[(c*M+0)*10+:10])),
                    .b1($signed(b_cols[(c*M+1)*10+:10])),
                    .b2($signed(b_cols[(c*M+2)*10+:10])),
                    .b3($signed(b_cols[(c*M+3)*10+:10])),
                    .b4($signed(b_cols[(c*M+4)*10+:10])),
                    .b5($signed(b_cols[(c*M+5)*10+:10])),
                    .b6($signed(b_cols[(c*M+6)*10+:10])),
                    .b7($signed(b_cols[(c*M+7)*10+:10])),
                    .compute(valid),.init(1'b0),.shift(1'b0),
                    .psum_in(pin),.psum_out(pout));
            end else begin : bad
                // 非法 M 在综合前由脚本拒绝；此分支只避免空 generate。
                assign pout.data=32'b0;
            end
        end
    end
endmodule

// 固定端口顶层：一个 tile 的核心，不含 A/B/C 存储。
module kwt_core_8_m1(input logic clk,rst_n,input logic [95:0] a_rows,
    input logic [79:0] b_cols,input logic valid,output logic [2047:0] out_data);
    kwt_flat_core #(.ROWS(8),.COLS(8),.M(1)) u(.clk(clk),.rst_n(rst_n),
        .a_rows(a_rows),.b_cols(b_cols),.valid(valid),.out_data(out_data));
endmodule

module kwt_core_8_m2(input logic clk,rst_n,input logic [191:0] a_rows,
    input logic [159:0] b_cols,input logic valid,output logic [2047:0] out_data);
    kwt_flat_core #(.ROWS(8),.COLS(8),.M(2)) u(.clk(clk),.rst_n(rst_n),
        .a_rows(a_rows),.b_cols(b_cols),.valid(valid),.out_data(out_data));
endmodule

module kwt_core_8_m4(input logic clk,rst_n,input logic [383:0] a_rows,
    input logic [319:0] b_cols,input logic valid,output logic [2047:0] out_data);
    kwt_flat_core #(.ROWS(8),.COLS(8),.M(4)) u(.clk(clk),.rst_n(rst_n),
        .a_rows(a_rows),.b_cols(b_cols),.valid(valid),.out_data(out_data));
endmodule

module kwt_core_8_m8(input logic clk,rst_n,input logic [767:0] a_rows,
    input logic [639:0] b_cols,input logic valid,output logic [2047:0] out_data);
    kwt_flat_core #(.ROWS(8),.COLS(8),.M(8)) u(.clk(clk),.rst_n(rst_n),
        .a_rows(a_rows),.b_cols(b_cols),.valid(valid),.out_data(out_data));
endmodule

module kwt_core_16_m1(input logic clk,rst_n,input logic [191:0] a_rows,
    input logic [159:0] b_cols,input logic valid,output logic [8191:0] out_data);
    kwt_flat_core #(.ROWS(16),.COLS(16),.M(1)) u(.clk(clk),.rst_n(rst_n),
        .a_rows(a_rows),.b_cols(b_cols),.valid(valid),.out_data(out_data));
endmodule

module kwt_core_16x32_m1(input logic clk,rst_n,input logic [191:0] a_rows,
    input logic [319:0] b_cols,input logic valid,output logic [16383:0] out_data);
    kwt_flat_core #(.ROWS(16),.COLS(32),.M(1)) u(.clk(clk),.rst_n(rst_n),
        .a_rows(a_rows),.b_cols(b_cols),.valid(valid),.out_data(out_data));
endmodule

module kwt_core_32x16_m1(input logic clk,rst_n,input logic [383:0] a_rows,
    input logic [159:0] b_cols,input logic valid,output logic [16383:0] out_data);
    kwt_flat_core #(.ROWS(32),.COLS(16),.M(1)) u(.clk(clk),.rst_n(rst_n),
        .a_rows(a_rows),.b_cols(b_cols),.valid(valid),.out_data(out_data));
endmodule
