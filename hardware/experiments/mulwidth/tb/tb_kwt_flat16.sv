// 16×16阵列功能台：16×16×K8逐点独立64位整数参考，比较256个输出。
// 覆盖全零、单点非零、随机小矩阵、满量程随机与零通道混合；乘法三级流水与valid按拍对齐。
module tb_kwt_flat16;
    localparam int K=8; // 每个测试用例的深度
    logic clk=0,rst_n=0; // 固定时钟、低有效复位
    logic signed [16*12-1:0] a_row=0; // 行广播A
    logic signed [16*10-1:0] b_col=0; // 列广播B
    logic valid=0; // 统一发射
    logic [256*32-1:0] out; // 256个INT32
    longint ref_acc[0:255]; // 独立64位整数累加参考
    int q[0:255][0:2]; // 每个PE独立的三级乘积延迟
    bit valid_q[0:2]; // 参考有效位
    int checks=0; // 已比较的逐点数
    int errs=0; // 输出失配数
    int unsigned rng=32'h5eed1234; // 固定随机序列
    int ai[0:15][0:7]; // 激励用的A矩阵，[行][K]
    int bi[0:15][0:7]; // 激励用的B矩阵，[列][K]
    always #5 clk=~clk;
    kwt_flat16 dut(.clk(clk),.rst_n(rst_n),.a_row(a_row),.b_col(b_col),.valid(valid),.out(out));

    // 每拍：消费三拍前的256个乘积→推进队列→压入本拍256个乘积→比较全部输出。
    task automatic tick;
        logic [27:0] exp; // 单点28位参考
        @(posedge clk);
        if(!rst_n) begin // 复位清空参考。
            for(int i=0;i<256;i++) begin ref_acc[i]=0;q[i][0]=0;q[i][1]=0;q[i][2]=0;end
            valid_q[0]=0;valid_q[1]=0;valid_q[2]=0;
        end else begin
            if(valid_q[2]) for(int i=0;i<256;i++) ref_acc[i]+=q[i][2]; // 与DUT同拍累加
            for(int i=0;i<256;i++) begin q[i][2]=q[i][1];q[i][1]=q[i][0];end
            valid_q[2]=valid_q[1];valid_q[1]=valid_q[0];valid_q[0]=valid;
            for(int r=0;r<16;r++) for(int c=0;c<16;c++) // 装入本拍广播后的乘积
                q[r*16+c][0]=int'($signed(a_row[r*12 +: 12]))*int'($signed(b_col[c*10 +: 10]));
        end
        #1;
        for(int i=0;i<256;i++) begin
            exp=28'(ref_acc[i]); // 模2^28截断回绕
            if(out[i*32 +: 32]!=={{4{exp[27]}},exp}) begin
                errs++;
                if(errs<=10) $display("MISMATCH idx=%0d r=%0d c=%0d got=%h exp=%h ref=%0d",
                    i,i/16,i%16,out[i*32 +: 32],{{4{exp[27]}},exp},ref_acc[i]);
            end
            checks++;
        end
        @(negedge clk);
    endtask

    // 按矩阵内容发一拍：同行共享A，同列共享B，与RTL切片约定一致。
    task automatic apply(int k);
        for(int r=0;r<16;r++) a_row[r*12 +: 12]=12'(ai[r][k]);
        for(int c=0;c<16;c++) b_col[c*10 +: 10]=10'(bi[c][k]);
        valid=1;tick();
    endtask

    // 复位后按K拍连续发射，再排空三级流水。
    task automatic run_case;
        valid=0;rst_n=0;tick();rst_n=1; // 清参考与DUT全部寄存器
        for(int k=0;k<K;k++) apply(k);
        valid=0;repeat(4) tick(); // 等三级流水排空
    endtask

    // 激励矩阵清零。
    task automatic clear_mat;
        for(int r=0;r<16;r++) for(int k=0;k<K;k++) begin ai[r][k]=0;bi[r][k]=0;end
    endtask

    // 字面值点检：不依赖参考模型，防止参考与DUT同错时测试空转。
    task automatic expect_point(int idx,int value);
        checks++;
        if(out[idx*32 +: 32]!==32'(value)) begin
            errs++;
            $display("LITERAL_MISMATCH idx=%0d got=%h exp=%h",idx,out[idx*32 +: 32],32'(value));
        end
    endtask

    initial begin
        // 用例1：全零矩阵，输出必须保持0。
        clear_mat;run_case;
        for(int i=0;i<256;i++) expect_point(i,0); // 全零必须逐点为0
        $display("CASE zero done checks=%0d",checks);
        // 用例2：单点非零(r=3,c=11,K=0..1)，其余点保持0。
        clear_mat;ai[3][0]=7;ai[3][1]=-5;bi[11][0]=-3;bi[11][1]=9;run_case;
        expect_point(3*16+11,7*(-3)+(-5)*9); // 期望-66，其余点仍为0
        for(int i=0;i<256;i++) if(i!=3*16+11) expect_point(i,0);
        $display("CASE single done checks=%0d",checks);
        // 用例3：随机小矩阵，A∈[-8,7]、B∈[-4,3]。
        clear_mat;
        for(int r=0;r<16;r++) for(int k=0;k<K;k++) begin
            rng=1664525*rng+1013904223;ai[r][k]=int'(rng%16)-8;
            rng=1664525*rng+1013904223;bi[r][k]=int'(rng%8)-4;
        end
        run_case;
        $display("CASE small done checks=%0d",checks);
        // 用例4：满量程随机，含正负值，检验符号扩展与三拍对齐。
        clear_mat;
        for(int r=0;r<16;r++) for(int k=0;k<K;k++) begin
            rng=1664525*rng+1013904223;ai[r][k]=int'(rng%4096)-2048;
            rng=1664525*rng+1013904223;bi[r][k]=int'(rng%1024)-512;
        end
        run_case;
        $display("CASE full done checks=%0d",checks);
        // 用例5：全部A=-2048、B=-512，每拍每点加2^20。
        clear_mat;
        for(int r=0;r<16;r++) for(int k=0;k<K;k++) begin ai[r][k]=-2048;bi[r][k]=-512;end
        run_case;
        for(int i=0;i<256;i++) expect_point(i,8*2048*512); // 字面值：8×2^20=0x800000
        $display("CASE extrema done checks=%0d",checks);
        // 用例6：零A零B混合，验证零通道不吞掉同拍其他非零乘积。
        clear_mat;
        for(int r=0;r<16;r++) for(int k=0;k<K;k++) begin
            ai[r][k]=(k%3==0)?0:301; // 部分拍的A为零
            bi[r][k]=(r%4==0)?0:-77; // 部分列的B为零
        end
        run_case;
        $display("CASE mixed_zero done checks=%0d",checks);
        if(errs==0) $display("FLAT16_PASS checks=%0d errs=%0d cases=6 k=%0d pe=256",checks,errs,K);
        else $fatal(1,"FLAT16_FAIL checks=%0d errs=%0d",checks,errs);
        $finish;
    end
endmodule
