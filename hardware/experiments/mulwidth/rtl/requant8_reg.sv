// 寄存器包边，用于 150MHz 核心时序/面积；逻辑仍是 8 路 requant。
module requant8_reg (
    input logic clk,rst_n,
    input logic signed [31:0] y0,y1,y2,y3,y4,y5,y6,y7,
    input logic [4:0] sh0,sh1,sh2,sh3,sh4,sh5,sh6,sh7,
    output logic signed [15:0] q0,q1,q2,q3,q4,q5,q6,q7
);
    logic signed [31:0] yr0,yr1,yr2,yr3,yr4,yr5,yr6,yr7;
    logic [4:0] sr0,sr1,sr2,sr3,sr4,sr5,sr6,sr7;
    logic signed [15:0] qc0,qc1,qc2,qc3,qc4,qc5,qc6,qc7;
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            yr0<=0;yr1<=0;yr2<=0;yr3<=0;yr4<=0;yr5<=0;yr6<=0;yr7<=0;
            sr0<=0;sr1<=0;sr2<=0;sr3<=0;sr4<=0;sr5<=0;sr6<=0;sr7<=0;
            q0<=0;q1<=0;q2<=0;q3<=0;q4<=0;q5<=0;q6<=0;q7<=0;
        end else begin
            yr0<=y0;yr1<=y1;yr2<=y2;yr3<=y3;yr4<=y4;yr5<=y5;yr6<=y6;yr7<=y7;
            sr0<=sh0;sr1<=sh1;sr2<=sh2;sr3<=sh3;sr4<=sh4;sr5<=sh5;sr6<=sh6;sr7<=sh7;
            q0<=qc0;q1<=qc1;q2<=qc2;q3<=qc3;q4<=qc4;q5<=qc5;q6<=qc6;q7<=qc7;
        end
    end
    kwt_requant8 u(.y0(yr0),.y1(yr1),.y2(yr2),.y3(yr3),.y4(yr4),.y5(yr5),.y6(yr6),.y7(yr7),
        .sh0(sr0),.sh1(sr1),.sh2(sr2),.sh3(sr3),.sh4(sr4),.sh5(sr5),.sh6(sr6),.sh7(sr7),
        .q0(qc0),.q1(qc1),.q2(qc2),.q3(qc3),.q4(qc4),.q5(qc5),.q6(qc6),.q7(qc7));
endmodule
