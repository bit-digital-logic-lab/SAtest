// 32×32块阵列逐点回归台；由 hardware/run.py 选择 ARCH、编译并传入数据文件。
module tb_kwt_block32 #(
    // 与 kwt_block32 的架构编码一致：0/1/2。
    parameter int ARCH = 0
);
    // 时钟与复位。
    logic clk = 0;
    logic rst_n = 0;
    // A12、B10与C32独立装载端口，测试任务选择其中一个驱动。
    logic a_load_valid=0,b_load_valid=0,c_load_valid=0;
    logic [9:0] a_load_addr=0,b_load_addr=0,c_load_addr=0;
    logic signed [11:0] a_load_data=0;
    logic signed [9:0] b_load_data=0;
    logic [31:0] c_load_data=0;
    // 计算启动与状态接口。
    logic start = 0;
    logic busy, done;
    // C阵列逐地址读取接口。
    logic [9:0] c_addr = 0;
    logic [31:0] c_data;

    // 矩阵形状、周期及事务统计。
    int m_len, k_len, n_len;
    int cycle_count = 0;
    int a_writes = 0, b_writes = 0, c_writes = 0;
    int blocks = 0, outputs = 0, gap_count = 0;
    // 输入文件路径与期望/部分和缓存。
    string a_path, b_path, bias_path, expected_path, output_path;
    logic [11:0] a_file [0:99999];
    logic [9:0] b_file [0:99999];
    logic [31:0] bias_file [0:1023];
    logic [31:0] expected_file [0:32767];
    logic [31:0] partial_sum [0:32767];
    // 输出记录文件句柄。
    int output_fd;

    int phase_cycles[0:6];          // 实测LOAD/RUN/WAIT/FLUSH/TAIL/STORE各阶段拍数
    int compute_cycles=0;          // 累计任务活动拍数，不含主机装载及读回
    int steps=0,last_step_cycle=0; // 验证每个K向量均按固定间隔发射
    int block_start_cycle;          // 任务起点，用于交叉核对状态计数
    localparam int EXPECT_II=(ARCH==0)?4:((ARCH==1)?3:1); // 独立调度合同，不读取DUT参数
    localparam int EXPECT_BLOCK=(ARCH==0)?4192:((ARCH==1)?3632:2736); // 16个8×8子块的约定拍数

    // 按实际执行状态计数，并检查相邻K位置的发射间隔，零输入也必须遵守。
    always @(posedge clk) begin
        if (rst_n && busy) begin // 只计任务内部周期，排除主机端的空闲等待。
            phase_cycles[int'(dut.state)]++;
            compute_cycles++;
            if (dut.array_bus.step) begin // valid是固定节拍标记，不是反压握手。
                if (dut.k!=0 && cycle_count-last_step_cycle!=EXPECT_II)
                    $fatal(1,"issue interval arch=%0d got=%0d expected=%0d",ARCH,cycle_count-last_step_cycle,EXPECT_II);
                last_step_cycle=cycle_count;
                steps++;
            end
        end
    end

    // 周期时钟、活动周期计数和仿真超时保护。
    always #5 clk = ~clk;
    always @(posedge clk) if (rst_n) cycle_count <= cycle_count + 1;
    always @(posedge clk) if (rst_n && cycle_count > 2000000) $fatal(1, "timeout");

    // DUT使用选定架构，端口由测试台驱动并观测。
    kwt_block32 #(.ARCH(ARCH)) dut (
        .clk(clk), .rst_n(rst_n),
        .a_load_valid(a_load_valid),.a_load_addr(a_load_addr),.a_load_data(a_load_data),
        .b_load_valid(b_load_valid),.b_load_addr(b_load_addr),.b_load_data(b_load_data),
        .c_load_valid(c_load_valid),.c_load_addr(c_load_addr),.c_load_data(c_load_data),
        .start(start), .busy(busy), .done(done),
        .c_addr(c_addr), .c_data(c_data)
    );

    // 在任务空闲边界写入一个A、B或C字，并周期性插入空拍。
    task automatic load_word(input int matrix, input int address, input logic [31:0] value);
        @(negedge clk);
        while (busy) @(negedge clk); // 仅在任务边界等空闲，内部运算不接受反压。
        case (matrix) // 数据在测试任务中分发到独立物理端口，不合并A/B总线。
            0: begin a_load_addr=10'(address); a_load_data=value[11:0]; a_load_valid=1; end
            1: begin b_load_addr=10'(address); b_load_data=value[9:0]; b_load_valid=1; end
            2: begin c_load_addr=10'(address); c_load_data=value; c_load_valid=1; end
        endcase
        @(posedge clk);
        if (matrix == 0) a_writes++;
        else if (matrix == 1) b_writes++;
        else c_writes++;
        @(negedge clk);
        a_load_valid=0; b_load_valid=0; c_load_valid=0; // 本次独立端口写事务结束。
        if ((a_writes + b_writes + c_writes) % 73 == 0) begin
            repeat (2) @(negedge clk);
            gap_count++;
        end
    endtask

    // 将主机B矩阵对应区域映射到32×32块，块外元素补零。
    task automatic load_b_tile(input int k0, input int j0);
        for (int kk = 0; kk < 32; kk++) begin
            for (int cc = 0; cc < 32; cc++) begin
                logic [31:0] value;
                value = 0;
                if (k0 + kk < k_len && j0 + cc < n_len)
                    value = {22'b0, b_file[(k0 + kk) * n_len + j0 + cc]};
                load_word(1, kk * 32 + cc, value);
            end
        end
    endtask

    // 将主机A矩阵对应区域映射到32×32块，块外元素补零。
    task automatic load_a_tile(input int i0, input int k0);
        for (int rr = 0; rr < 32; rr++) begin
            for (int kk = 0; kk < 32; kk++) begin
                logic [31:0] value;
                value = 0;
                if (i0 + rr < m_len && k0 + kk < k_len)
                    value = {20'b0, a_file[(i0 + rr) * k_len + k0 + kk]};
                load_word(0, rr * 32 + kk, value);
            end
        end
    endtask

    // 首个K块装载bias，后续K块装载上次回读的部分和。
    task automatic load_c_tile(input int i0, input int j0, input int k0);
        for (int rr = 0; rr < 32; rr++) begin
            for (int cc = 0; cc < 32; cc++) begin
                logic [31:0] value;
                value = 0;
                if (i0 + rr < m_len && j0 + cc < n_len) begin
                    if (k0 == 0) value = bias_file[j0 + cc];
                    else value = partial_sum[(i0 + rr) * n_len + j0 + cc];
                end
                load_word(2, rr * 32 + cc, value);
            end
        end
    endtask

    // 在任务边界提交启动脉冲，再等待整块done状态。
    task automatic start_block();
        @(negedge clk);
        while (busy) @(negedge clk); // 新任务只在上一个任务完成后启动。
        for (int st=0;st<7;st++) phase_cycles[st]=0; // 每次任务单独记录各阶段。
        steps=0;
        block_start_cycle=cycle_count+1; // 下一上升沿接受start，不把启动前半拍计入任务。
        start = 1;
        @(negedge clk);
        start = 0;
        while (1) begin
            @(negedge clk);
            if (done) break;
        end
        if (cycle_count-block_start_cycle!=EXPECT_BLOCK)
            $fatal(1,"task cycles arch=%0d got=%0d expected=%0d",ARCH,cycle_count-block_start_cycle,EXPECT_BLOCK);
        if (steps!=512) $fatal(1,"issue count=%0d expected=512",steps);
        if (blocks==0) $display("TIMING arch=%0d block=%0d load=%0d run=%0d wait=%0d flush=%0d tail=%0d store=%0d steps=%0d",
            ARCH,cycle_count-block_start_cycle,phase_cycles[1],phase_cycles[2],phase_cycles[3],phase_cycles[4],phase_cycles[5],phase_cycles[6],steps);
        blocks++;
    endtask

    // 读取C块有效元素，保存部分和并在末K块逐位比较参考值。
    task automatic save_c_tile(input int i0, input int j0, input bit final_k);
        for (int rr = 0; rr < 32; rr++) begin
            for (int cc = 0; cc < 32; cc++) begin
                if (i0 + rr < m_len && j0 + cc < n_len) begin
                    int index;
                    logic [31:0] got;
                    index = (i0 + rr) * n_len + j0 + cc;
                    @(negedge clk);
                    c_addr = 10'(rr * 32 + cc);
                    #1;
                    got = c_data;
                    partial_sum[index] = got;
                    if (final_k && got !== expected_file[index])
                        $fatal(1, "mismatch row=%0d col=%0d got=%08h expected=%08h",
                               i0 + rr, j0 + cc, got, expected_file[index]);
                    if (final_k && output_fd != 0)
                        $fdisplay(output_fd, "%0d %0d %08h", i0 + rr, j0 + cc, got);
                    if (final_k) outputs++;
                end
            end
        end
    endtask

    // 重启最后一块，额外验证已完成块中的C驻留值可继续累加。
    task automatic repeat_last_tile(input int i0, input int j0, input int k0);
        start_block();
        for (int rr = 0; rr < 32; rr++) begin
            for (int cc = 0; cc < 32; cc++) begin
                if (i0 + rr < m_len && j0 + cc < n_len) begin
                    int index;
                    longint signed acc;
                    logic [31:0] got;
                    index = (i0 + rr) * n_len + j0 + cc;
                    acc = 64'($signed(expected_file[index])); // 先解释为有符号32位，再扩展到64位参考累加器。
                    for (int kk = k0; kk < k_len; kk++)
                        acc += int'($signed(a_file[(i0 + rr) * k_len + kk])) *
                               int'($signed(b_file[kk * n_len + j0 + cc]));
                    @(negedge clk);
                    c_addr = 10'(rr * 32 + cc);
                    #1;
                    got = c_data;
                    if (got !== acc[31:0])
                        $fatal(1, "repeat mismatch row=%0d col=%0d got=%08h expected=%08h",
                               i0 + rr, j0 + cc, got, acc[31:0]);
                end
            end
        end
    endtask

    // 读取命令行文件与形状，按N/K/M块顺序装载、计算、核对并汇总。
    initial begin
        int j0, k0, i0;
        if (!$value$plusargs("M=%d", m_len) || !$value$plusargs("K=%d", k_len) ||
            !$value$plusargs("N=%d", n_len) || !$value$plusargs("A=%s", a_path) ||
            !$value$plusargs("B=%s", b_path) || !$value$plusargs("BIAS=%s", bias_path) ||
            !$value$plusargs("EXPECTED=%s", expected_path) || !$value$plusargs("OUT=%s", output_path))
            $fatal(1, "missing plusargs");
        if (m_len > 99 || k_len > 64 || n_len > 256) $fatal(1, "shape too large");
        $readmemh(a_path, a_file);
        $readmemh(b_path, b_file);
        $readmemh(bias_path, bias_file);
        $readmemh(expected_path, expected_file);
        output_fd = $fopen(output_path, "w");

        repeat (4) @(negedge clk);
        rst_n = 1;
        for (j0 = 0; j0 < n_len; j0 += 32) begin
            for (k0 = 0; k0 < k_len; k0 += 32) begin
                load_b_tile(k0, j0);
                for (i0 = 0; i0 < m_len; i0 += 32) begin
                    load_a_tile(i0, k0);
                    load_c_tile(i0, j0, k0);
                    start_block();
                    save_c_tile(i0, j0, k0 + 32 >= k_len);
                end
            end
        end
        repeat_last_tile(((m_len - 1) / 32) * 32, ((n_len - 1) / 32) * 32,
                         ((k_len - 1) / 32) * 32);
        if (outputs != m_len * n_len) $fatal(1, "output count=%0d expected=%0d", outputs, m_len*n_len);
        $fclose(output_fd);
        $display("PASS arch=%0d shape=%0dx%0dx%0d outputs=%0d blocks=%0d cycles=%0d host_writes=%0d A=%0d B=%0d C=%0d gaps=%0d compute_cycles=%0d block_cycles=%0d",
                 ARCH, m_len, k_len, n_len, outputs, blocks,
                 cycle_count, a_writes+b_writes+c_writes, a_writes, b_writes, c_writes, gap_count, compute_cycles, EXPECT_BLOCK);
        $finish;
    end
endmodule
