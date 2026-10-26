// 单PE m8逐拍独立参考：8路随机A/B、零通道、补码极值、连续背靠背、init/shift装载。
// 参考模型只用64位整数按模2^28加减，不复制RTL的7级XOR/AND压缩算法。
module tb_kwt_pe_m8;
    localparam int M = 8; // 本PE的K通道数
    logic clk=0,rst_n=0; // 固定时钟、低有效复位
    logic signed [11:0] a[0:M-1]; // 8路激活
    logic signed [9:0] b[0:M-1]; // 8路权重
    logic compute=0,init=0,shift=0; // 发射、上传、移位
    kwt_psum_if psum_in(),psum_out(); // 行链两端
    longint q[0:M-1][0:2]; // 每路乘积的三拍参考延迟
    bit en[0:M-1][0:2]; // 每路零值使能的三拍延迟
    bit vld[0:2]; // compute的三拍延迟
    logic [27:0] exp_sum=0; // 独立模2^28参考和
    int checks=0,valid_accs=0,zero_holds=0,loads=0,errors=0; // 统计与错误数
    int unsigned rng=32'h13579BDF; // 与m4不同的固定随机序列
    always #5 clk=~clk; // 仅仿真时钟

    kwt_pe_m8 dut(.clk(clk),.rst_n(rst_n),
        .a0(a[0]),.a1(a[1]),.a2(a[2]),.a3(a[3]),
        .a4(a[4]),.a5(a[5]),.a6(a[6]),.a7(a[7]),
        .b0(b[0]),.b1(b[1]),.b2(b[2]),.b3(b[3]),
        .b4(b[4]),.b5(b[5]),.b6(b[6]),.b7(b[7]),
        .compute(compute),.init(init),.shift(shift),
        .psum_in(psum_in),.psum_out(psum_out));

    // 复位时清空参考流水；否则先按三拍前的结果更新参考和，再推进本拍输入。
    task automatic tick;
        bit any_en;
        @(posedge clk);
        if(!rst_n) begin
            exp_sum=0;
            for(int i=0;i<M;i++) for(int j=0;j<3;j++) begin q[i][j]=0;en[i][j]=0; end
            for(int j=0;j<3;j++) vld[j]=0;
        end else begin
            if(init||shift) begin // 装载优先，复用原累计寄存器。
                exp_sum=psum_in.data[27:0];loads++;
            end else if(vld[2]) begin // 只有所有路有效位对齐后才看累加。
                longint total=0;
                any_en=1'b0;
                for(int i=0;i<M;i++) begin
                    if(en[i][2]) begin total+=q[i][2];any_en=1'b1;end // 零通道按0参与。
                end
                if(any_en) begin
                    exp_sum=28'((longint'(exp_sum)+total)&64'sh0FFFFFFF); // 模2^28回绕。
                    valid_accs++;
                end else zero_holds++; // 全零拍保持原和。
            end
            for(int i=0;i<M;i++) for(int j=2;j>0;j--) begin q[i][j]=q[i][j-1];en[i][j]=en[i][j-1];end
            for(int i=0;i<M;i++) begin
                q[i][0]=longint'(a[i])*longint'(b[i]); // 独立整数乘积。
                en[i][0]=compute&&(a[i]!=0)&&(b[i]!=0); // 与kwt_mul的nonzero定义一致。
            end
            for(int j=2;j>0;j--) vld[j]=vld[j-1];
            vld[0]=compute;
        end
        #1;
        checks++;
        if(psum_out.data!=={{4{exp_sum[27]}},exp_sum}) begin
            errors++;
            if(errors<=10) $display("ERROR top=kwt_pe_m8 cycle=%0d got=%h exp=%h",
                checks,psum_out.data,{{4{exp_sum[27]}},exp_sum});
        end
        @(negedge clk);
    endtask

    // 线性同余取随机操作数，截断到端口位宽即得补码范围内的值。
    task automatic rnd_a(int i); rng=1664525*rng+1013904223;a[i]=12'(rng); endtask
    task automatic rnd_b(int i); rng=1664525*rng+1013904223;b[i]=10'(rng); endtask

    initial begin
        for(int i=0;i<M;i++) begin a[i]=0;b[i]=0;end
        repeat(2) tick(); // 复位期间检查输出为0。
        rst_n=1;
        // 上传一个负数和，验证低28位截取与符号扩展。
        init=1;psum_in.data=32'hF8000000;tick();init=0;tick();
        // 随机段：空拍、单路零、全零混合。
        for(int n=0;n<300;n++) begin
            for(int i=0;i<M;i++) begin rnd_a(i);rnd_b(i);end
            if(n%9==0) a[0]=0; // 仅第0路零，其他路仍须累加。
            if(n%13==0) b[5]=0; // 仅第5路零，不能沿用旧乘积。
            if(n%17==0) for(int i=0;i<M;i++) begin a[i]=0;b[i]=0;end // 整拍全零保持。
            compute=(n%11!=0);tick(); // 空拍原样延迟，不产生幽灵乘积。
        end
        // 零通道段：每拍至少两路为零，轮换位置，另夹全零拍。
        for(int n=0;n<80;n++) begin
            for(int i=0;i<M;i++) begin rnd_a(i);rnd_b(i);end
            a[n%M]=0;
            b[(n+1)%M]=0;
            if(n%5==0) for(int i=0;i<M;i++) begin a[i]=0;b[i]=0;end
            compute=1;tick();
        end
        // 补码极值段：含(-2048)×(-512)等端点，必然触发多次回绕。
        for(int n=0;n<80;n++) begin
            for(int i=0;i<M;i++) begin
                case((n+i)%5)
                    0:a[i]=-2048;1:a[i]=2047;2:a[i]=-1;3:a[i]=1;default:a[i]=0;
                endcase
                case((n+2*i)%5)
                    0:b[i]=-512;1:b[i]=511;2:b[i]=-1;3:b[i]=1;default:b[i]=0;
                endcase
            end
            compute=1;tick();
        end
        // 背靠背段：compute每拍为1，检查无停顿连续累加。
        for(int n=0;n<300;n++) begin
            for(int i=0;i<M;i++) begin rnd_a(i);rnd_b(i);end
            compute=1;tick();
        end
        // 排空流水后做init和shift装载，验证load优先且复用寄存器。
        compute=0;repeat(3) tick();
        init=1;psum_in.data=32'h8123_4567;tick();init=0;tick();
        for(int n=0;n<3;n++) begin
            shift=1;psum_in.data=32'h55AA_0000|32'(n*32'h1234);tick();shift=0;tick();
        end
        if(errors==0) $display("PE_PASS top=kwt_pe_m8 checks=%0d valid_accs=%0d zero_holds=%0d loads=%0d errors=0",
            checks,valid_accs,zero_holds,loads);
        else begin
            $display("PE_FAIL top=kwt_pe_m8 checks=%0d valid_accs=%0d zero_holds=%0d loads=%0d errors=%0d",
                checks,valid_accs,zero_holds,loads,errors);
            $fatal(1,"tb_kwt_pe_m8 mismatch");
        end
        $finish;
    end
endmodule
