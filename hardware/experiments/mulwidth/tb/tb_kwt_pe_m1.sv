// 单乘PE逐拍独立参考：检查三级乘法、单拍CPA、零通道、空拍、装和/移位与28位回绕。
// 先跑本台确认时序模型，再用同一模型在tb_kwt_flat16中做256点比较。
module tb_kwt_pe_m1;
    logic clk=0,rst_n=0; // 固定时钟、低有效复位
    logic signed [11:0] a=0; // 激活值
    logic signed [9:0] b=0; // 权重
    logic compute=0,init=0,shift=0; // 发射和原和装载/移位
    kwt_psum_if psum_in(),psum_out(); // 行列链端点
    int signed q[0:2]; // 独立整型乘法参考的三级延迟
    bit valid_q[0:2]; // 参考有效位，无效拍仍占流水位置
    logic [27:0] expected_sum=0; // 独立模2^28参考
    int checks=0; // 实际逐拍检查数
    int unsigned rng=32'h1a2b3c4d; // 固定随机序列，便于复现
    always #5 clk=~clk; // 仅仿真时钟，不表示时序验收频率
    kwt_pe_m1 dut(.clk(clk),.rst_n(rst_n),.a(a),.b(b),
        .compute(compute),.init(init),.shift(shift),.psum_in(psum_in),.psum_out(psum_out));
    // 每个边沿先消费三拍前的乘积，再推进队列；装载优先于累加。
    task automatic tick;
        @(posedge clk);
        if(!rst_n) begin // 清空参考流水。
            expected_sum=0;
            for(int j=0;j<3;j++) begin q[j]=0;valid_q[j]=0;end
        end else begin
            if(init||shift) expected_sum=psum_in.data[27:0]; // 整行装和复用到同一寄存器
            else if(valid_q[2]) expected_sum=28'(int'(expected_sum)+q[2]); // 模2^28回绕
            for(int j=2;j>0;j--) begin q[j]=q[j-1];valid_q[j]=valid_q[j-1];end
            q[0]=int'(a)*int'(b);valid_q[0]=compute;
        end
        #1;
        if(psum_out.data!=={{4{expected_sum[27]}},expected_sum})
            $fatal(1,"acc cycle=%0d got=%h expected=%h",checks,psum_out.data,expected_sum);
        if(rst_n) begin
            if(dut.v!==valid_q[2]) $fatal(1,"three-stage valid cycle=%0d",checks);
            if(valid_q[2] && q[2]!=0 && int'(dut.product)!=q[2]) $fatal(1,"mul mismatch");
        end
        checks++;
        @(negedge clk);
    endtask
    initial begin
        psum_in.data=0;tick();rst_n=1;init=1;psum_in.data=32'h07fffffd;tick();init=0;
        for(int n=0;n<600;n++) begin // 随机流夹入零操作数、端点与空拍
            rng=1664525*rng+1013904223;a=12'(rng);
            rng=1664525*rng+1013904223;b=10'(rng);
            if(n%5==0) a=0; // 零A关闭本拍更新
            if(n%7==0) b=0; // 零B关闭本拍更新
            if(n%11==0) begin a=-2048;b=-512;end // 补码负端点，触发回绕
            if(n%13==0) begin a=2047;b=511;end // 正端点
            compute=n%17!=0; // 外部空拍原样延迟
            tick();
        end
        compute=0;repeat(4) tick(); // 排空三级流水
        shift=1;psum_in.data=32'hf8000000;tick();shift=0;tick(); // 原和低28位装回
        shift=1;psum_in.data=32'h0000007f;tick();shift=0;tick();
        $display("PE_PASS checks=%0d mul_cases=600 stages=3 acc_bits=28",checks);$finish;
    end
endmodule
