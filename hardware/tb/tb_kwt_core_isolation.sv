// 核心零值隔离与PE连线回归：独立整数参考检查三级乘法、普通/CSA/双乘累加。
// 同时观察真实寄存器保持，空拍仍推进有效位置；不修改任何核心算术或阵列节拍。
module tb_kwt_core_isolation;
    logic clk=0,rst_n=0; // 测试时钟、低有效复位
    logic compute=0,load=0; // 输入有效位置、原和装载
    logic signed [11:0] a=0,a1=0; // 单乘输入及双乘第二路激活
    logic signed [9:0] b=0,b1=0; // 对应两路权重
    logic mv,me; // 独立乘法器的三级有效位和非零使能
    logic signed [21:0] mp; // 独立乘法器完整结果
    logic [31:0] carry_data,csa_value; // CSA驻留carry与只用于参考比较的二进制和
    kwt_psum_if pin(),normal_out(),csa_out(),dual_out(); // 真实PE的行移位接口
    logic [31:0] ref32=0; // 独立INT32参考
    logic [27:0] ref28=0; // 双乘的独立ACC28参考
    int signed p0[0:2],p1[0:2]; // 普通整数乘法的三级延迟参考
    bit valid_q[0:2]; // 空拍和零值都按同样时间推进
    int unsigned rng=32'h8035ace1; // 固定可复现激励
    int checks=0,stage1_holds=0,stage2_holds=0,stage3_holds=0,pe_holds=0; // 真实检查覆盖计数
    always #5 clk=~clk; // 仅仿真时间，频率验收由STA完成。
    assign csa_value=csa_out.data+carry_data; // 测试台解码sum/carry，不进入DUT数据通路。
    kwt_mul mul(.clk(clk),.rst_n(rst_n),.in_valid(compute),.a(a),.b(b),
        .out_valid(mv),.out_enable(me),.product(mp));
    kwt_pe_mac normal(.clk(clk),.rst_n(rst_n),.a(a),.b(b),.compute(compute),
        .init(load),.shift(1'b0),.psum_in(pin),.psum_out(normal_out));
    kwt_pe_csa csa(.clk(clk),.rst_n(rst_n),.a(a),.b(b),.compute(compute),
        .init(load),.shift(1'b0),.finalize(1'b0),.final_data(32'b0),
        .carry_data(carry_data),.psum_in(pin),.psum_out(csa_out));
    kwt_pe_dual dual(.clk(clk),.rst_n(rst_n),.a0(a),.b0(b),.a1(a1),.b1(b1),
        .compute(compute),.init(load),.shift(1'b0),.psum_in(pin),.psum_out(dual_out));

    // 边沿前保存真实状态；参考只用普通整数乘加，不复刻CSA逐位算法。
    task automatic tick;
        logic signed [11:0] old_a;
        logic signed [9:0] old_b;
        logic signed [17:0] old_low;
        logic signed [16:0] old_high;
        logic signed [21:0] old_product;
        logic [31:0] old_normal,old_csa_sum,old_csa_carry;
        bit en0,en1,keep_pe;
        @(posedge clk);
        old_a=mul.a_q;old_b=mul.b_q;old_low=mul.low_q;old_high=mul.high_q;old_product=mp;
        en0=mul.enable_q[0];en1=mul.enable_q[1];
        old_normal=normal_out.data;old_csa_sum=csa_out.data;old_csa_carry=carry_data;
        keep_pe=!load && (!valid_q[2] || p0[2]==0);
        if(!rst_n) begin // 清空流水中的旧有效位置，复位后的零输入不能产生旧乘积。
            ref32=0;ref28=0;
            for(int j=0;j<3;j++) begin p0[j]=0;p1[j]=0;valid_q[j]=0;end
        end else begin // 行装载优先，计算消费三拍前的输入位置。
            if(load) begin ref32=pin.data;ref28=pin.data[27:0];end
            else if(valid_q[2]) begin
                ref32=ref32+32'(p0[2]); // 普通与CSA同一输出参考。
                ref28=28'(int'(ref28)+p0[2]+p1[2]); // 两个相邻K属于同一个输出。
            end
            for(int j=2;j>0;j--) begin p0[j]=p0[j-1];p1[j]=p1[j-1];valid_q[j]=valid_q[j-1];end
            p0[0]=int'(a)*int'(b);p1[0]=int'(a1)*int'(b1);valid_q[0]=compute;
        end
        #1;
        if(normal_out.data!==ref32 || csa_value!==ref32 || dual_out.data!=={{4{ref28[27]}},ref28})
            $fatal(1,"PE link mismatch cycle=%0d normal=%h csa=%h dual=%h ref32=%h ref28=%h",checks,normal_out.data,csa_value,dual_out.data,ref32,ref28);
        if(rst_n) begin // 保持条件分别采用各级原使能，不能用当前输入使能阻断旧流水。
            if(mv!==valid_q[2] || me!==(valid_q[2] && p0[2]!=0)) $fatal(1,"valid alignment");
            if(me && int'(mp)!=p0[2]) $fatal(1,"product mismatch");
            if(!compute || a==0 || b==0) begin // 零值或空拍冻结首级，任意另一乘数变化也不能传入。
                if(mul.a_q!==old_a || mul.b_q!==old_b) $fatal(1,"stage1 isolation");
                stage1_holds++;
            end
            if(!en0) begin // 上一位置无非零输入，部分积寄存器保持。
                if(mul.low_q!==old_low || mul.high_q!==old_high) $fatal(1,"stage2 isolation");
                stage2_holds++;
            end
            if(!en1) begin // 对应乘积无使能时保持旧数据，下游必须屏蔽。
                if(mp!==old_product) $fatal(1,"stage3 isolation");
                stage3_holds++;
            end
            if(keep_pe) begin // 普通sum与CSA的sum/carry都必须保持，不误加冻结乘积。
                if(normal_out.data!==old_normal || csa_out.data!==old_csa_sum || carry_data!==old_csa_carry)
                    $fatal(1,"PE isolation");
                pe_holds++;
            end
        end
        checks++;@(negedge clk);
    endtask

    // 混合流验证零/非零/空拍交错；连续零段中仍改变外部另一乘数，观察真实隔离。
    initial begin
        pin.data=0;tick();rst_n=1;load=1;pin.data=32'h07ffffe1;tick();load=0;
        for(int n=0;n<1024;n++) begin
            rng=1664525*rng+1013904223;a=12'(rng);
            rng=1664525*rng+1013904223;b=10'(rng);
            rng=1664525*rng+1013904223;a1=12'(rng);
            rng=1664525*rng+1013904223;b1=10'(rng);
            compute=n%11!=0;
            case(n%8) // 独立两路零使能：一条零不能吞掉另一条非零乘积。
                0,1:a=0;
                2:b=0;
                3:a1=0;
                4:b1=0;
                5:begin a=0;b1=0;end
                default:begin end // 保留随机非零通道。
            endcase
            tick();
        end
        for(int n=0;n<32;n++) begin compute=1;a=0;b=10'(n*17);a1=12'(n);b1=0;tick();end
        compute=0;repeat(4)tick();
        load=1;pin.data=32'hf8000000;tick();load=0;tick(); // 验证复用原和装载后的符号/位宽。
        compute=1;a=2047;b=-512;a1=-2048;b1=511;tick();rst_n=0;tick(); // 在飞行中复位，消除旧有效位置。
        rst_n=1;compute=0;repeat(4)tick();
        if(stage1_holds<100 || stage2_holds<100 || stage3_holds<100 || pe_holds<100) $fatal(1,"coverage");
        $display("ISOLATION_PASS checks=%0d stage1_holds=%0d stage2_holds=%0d stage3_holds=%0d pe_holds=%0d",checks,stage1_holds,stage2_holds,stage3_holds,pe_holds);$finish;
    end
endmodule
