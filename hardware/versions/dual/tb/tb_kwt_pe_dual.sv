// 双乘PE逐拍独立参考：检查两条三级乘法、单拍CPA、零通道、空拍和28位回绕。
// hardware/run.py选择dual时先运行本台，再运行完整32×32及真实层回归。
module tb_kwt_pe_dual;
    logic clk=0,rst_n=0; // 固定时钟、低有效复位
    logic signed [11:0] a0=0,a1=0; // 相邻两个K的激活
    logic signed [9:0] b0=0,b1=0; // 相邻两个K的权重
    logic compute=0,init=0,shift=0; // 发射和原和装载/移位
    kwt_psum_if psum_in(),psum_out(); // 复用原寄存器的行链端点
    int signed q0[0:2],q1[0:2]; // 独立整型乘法参考的三级延迟
    bit valid_q[0:2]; // 参考有效位，无效拍仍占流水位置
    logic [27:0] expected_sum=0; // 独立模2^28参考
    int checks=0; // 实际逐拍检查数
    int unsigned rng=32'h19283746; // 固定随机序列，便于复现
    always #5 clk=~clk; // 仅仿真时钟，不表示时序验收频率。
    kwt_pe_dual dut(.clk(clk),.rst_n(rst_n),.a0(a0),.a1(a1),.b0(b0),.b1(b1),
        .compute(compute),.init(init),.shift(shift),.psum_in(psum_in),.psum_out(psum_out));
    // 每个边沿先消费旧队尾，再把本拍独立乘法结果推进队列，末尾比较DUT。
    task automatic tick;
        @(posedge clk);
        if(!rst_n) begin // 清空参考流水。
            expected_sum=0;
            for(int j=0;j<3;j++) begin q0[j]=0;q1[j]=0;valid_q[j]=0;end
        end else begin // 行装载优先，其余边沿消费三拍前接收的两个乘积。
            if(init||shift) expected_sum=psum_in.data[27:0];
            else if(valid_q[2]) expected_sum=28'(int'(expected_sum)+q0[2]+q1[2]);
            for(int j=2;j>0;j--) begin q0[j]=q0[j-1];q1[j]=q1[j-1];valid_q[j]=valid_q[j-1];end
            q0[0]=int'(a0)*int'(b0);q1[0]=int'(a1)*int'(b1);valid_q[0]=compute;
        end
        #1;
        if(psum_out.data!=={{4{expected_sum[27]}},expected_sum})
            $fatal(1,"acc cycle=%0d got=%h expected=%h",checks,psum_out.data,expected_sum);
        if(rst_n) begin // 两条独立乘法都恰好三级，零值时不比较冻结的数据。
            if(dut.v0!==valid_q[2] || dut.v1!==valid_q[2]) $fatal(1,"three-stage valid");
            if(valid_q[2] && q0[2]!=0 && int'(dut.product0)!=q0[2]) $fatal(1,"mul0 mismatch");
            if(valid_q[2] && q1[2]!=0 && int'(dut.product1)!=q1[2]) $fatal(1,"mul1 mismatch");
        end
        checks++;
        @(negedge clk);
    endtask
    // 连续流夹入零通道与空拍，再验证排空后的原和移位。
    initial begin
        psum_in.data=0;tick();rst_n=1;init=1;psum_in.data=32'h07fffffd;tick();init=0;
        for(int n=0;n<512;n++) begin // 让相邻两路经常取不同符号，抓住路号或K配对错误。
            rng=1664525*rng+1013904223;a0=12'(rng);
            rng=1664525*rng+1013904223;b0=10'(rng);
            rng=1664525*rng+1013904223;a1=12'(rng);
            rng=1664525*rng+1013904223;b1=10'(rng);
            if(n%5==0) a0=0; // 仅第0路零，另一乘积仍必须累加。
            if(n%7==0) b1=0; // 仅第1路零，不能沿用其旧乘积。
            if(n%11==0) begin a0=-2048;b0=-512;a1=2047;b1=511;end // 补码端点并触发累计回绕。
            compute=n%13!=0;tick(); // 外部空拍原样延迟，不能产生幽灵乘积。
        end
        compute=0;repeat(4) tick();shift=1;psum_in.data=32'hf8000000;tick();shift=0;tick();
        $display("PE_PASS checks=%0d pairs=512 mul_stages=3 acc_bits=28",checks);$finish;
    end
endmodule
