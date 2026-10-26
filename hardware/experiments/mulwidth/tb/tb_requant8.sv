module tb_requant8;
    logic signed [31:0] y[0:7];
    logic [4:0] sh[0:7];
    logic signed [15:0] q[0:7];
    logic signed [31:0] yf[0:7999];
    logic [4:0] shf[0:7999];
    logic signed [15:0] qf[0:7999];
    int errors=0;
    kwt_requant8 dut(.y0(y[0]),.y1(y[1]),.y2(y[2]),.y3(y[3]),.y4(y[4]),.y5(y[5]),.y6(y[6]),.y7(y[7]),
        .sh0(sh[0]),.sh1(sh[1]),.sh2(sh[2]),.sh3(sh[3]),.sh4(sh[4]),.sh5(sh[5]),.sh6(sh[6]),.sh7(sh[7]),
        .q0(q[0]),.q1(q[1]),.q2(q[2]),.q3(q[3]),.q4(q[4]),.q5(q[5]),.q6(q[6]),.q7(q[7]));
    initial begin
        $readmemh("/home/yang/Desktop/ic设计竞赛/.build/exp_mulwidth/requant/tb/y.hex",yf);
        $readmemh("/home/yang/Desktop/ic设计竞赛/.build/exp_mulwidth/requant/tb/sh.hex",shf);
        $readmemh("/home/yang/Desktop/ic设计竞赛/.build/exp_mulwidth/requant/tb/q.hex",qf);
        for(int i=0;i<2000;i+=8) begin
            for(int j=0;j<8;j++) begin y[j]=yf[i+j]; sh[j]=shf[i+j]; end
            #1;
            for(int j=0;j<8;j++) if(q[j]!==qf[i+j]) begin
                $display("MISMATCH i=%0d lane=%0d y=%h sh=%0d got=%h exp=%h",i,j,y[j],sh[j],q[j],qf[i+j]);
                errors++;
            end
        end
        if(errors) $fatal(1,"errors=%0d",errors);
        $display("REQUANT_PASS checks=2000 errors=0");
        $finish;
    end
endmodule
