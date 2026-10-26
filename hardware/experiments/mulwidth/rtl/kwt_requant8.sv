// 8 路 32→16 位输出压缩：算术右移 + 饱和；每列一个 5 位幂次 scale。
// 只做 drain 末尾的 epilogue，不进入 PE 累加热路径；用于验证 16 位输出的硬件成本。
module kwt_requant8 (
    input logic signed [31:0] y0,y1,y2,y3,y4,y5,y6,y7,
    input logic [4:0] sh0,sh1,sh2,sh3,sh4,sh5,sh6,sh7,
    output logic signed [15:0] q0,q1,q2,q3,q4,q5,q6,q7
);
    function automatic logic signed [15:0] requant(input logic signed [31:0] y, input logic [4:0] sh);
        logic signed [31:0] t;
        begin
            t = y >>> sh; // 算术右移；负数向下取整，误差 < 1 LSB
            if (t > 32'sd32767) requant = 16'sd32767;
            else if (t < -32'sd32768) requant = -16'sd32768;
            else requant = t[15:0];
        end
    endfunction
    assign q0=requant(y0,sh0); assign q1=requant(y1,sh1);
    assign q2=requant(y2,sh2); assign q3=requant(y3,sh3);
    assign q4=requant(y4,sh4); assign q5=requant(y5,sh5);
    assign q6=requant(y6,sh6); assign q7=requant(y7,sh7);
endmodule
