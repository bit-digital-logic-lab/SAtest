// 一列乘积逐对送往两个加法PE。
module kwt_column_pipe #(parameter int COL=0) (
    input logic clk,                         // 时钟
    input logic rst_n,                       // 低有效复位
    input logic load,                        // 部分和装载
    input logic [5:0] load_addr,              // 装载地址
    input logic [31:0] load_data,             // 装载数据
    kwt_product_if.sink products,             // 乘积和lane使能
    input logic [5:0] out_addr,               // 当前输出地址
    input logic out_step,                   // 固定下载节拍
    output logic [31:0] out_data               // 当前部分和
);
    logic [175:0] product_q;                 // 八个22位乘积移位寄存器
    logic [7:0] enable_q;                    // 八个lane有效位移位寄存器
    logic [1:0] step_index;                  // 当前乘积对序号
    logic active;                            // 正在消费向量
    logic compute_step;                      // PE步进
    logic load_even, load_odd;               // 偶行与奇行装载
    logic drain_even, drain_odd;             // 偶行与奇行选择
    logic [31:0] even_data, odd_data;         // 两个PE输出
    logic signed [21:0] even_product, odd_product; // 当前乘积对
    logic even_enable, odd_enable;           // 当前乘积有效位

    // 四个有效节拍固定消费一向量，末拍可同时装入下一向量。
    always_comb begin
        compute_step = active; // 只在持有向量时推进PE的轮转槽。
        load_even = load && (load_addr[2:0] == 3'(COL)) && !load_addr[3]; // 列地址匹配且行为偶数，装入偶行PE。
        load_odd = load && (load_addr[2:0] == 3'(COL)) && load_addr[3]; // 列地址匹配且行为奇数，装入奇行PE。
        drain_even = (out_addr[2:0] == 3'(COL)) && !out_addr[3]; // 当前输出列匹配且行为偶数，推进偶行PE读槽。
        drain_odd = (out_addr[2:0] == 3'(COL)) && out_addr[3]; // 当前输出列匹配且行为奇数，推进奇行PE读槽。
        even_product = $signed(product_q[21:0]); // 移位寄存器最低22位送给偶行PE。
        odd_product = $signed(product_q[43:22]); // 接下来的22位送给奇行PE。
        even_enable = enable_q[0]; // 当前偶行乘积的非零使能与数据同步移位。
        odd_enable = enable_q[1]; // 当前奇行乘积的非零使能与数据同步移位。
        out_data = out_addr[3] ? odd_data : even_data; // 根据行号奇偶选择两个PE之一的部分和。
    end

    // 乘积与有效位并行移位，末步无气泡衔接下一向量。
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin // 复位清空乘积缓存并取消消费状态。
            product_q <= '0; enable_q <= '0;
            step_index <= '0; active <= 1'b0;
        end else if (!active) begin // 列空闲时等待三拍乘法器给出新向量。
            if (products.valid) begin // 预定首向量到达，锁存八个乘积和零值使能。
                product_q <= products.data;
                enable_q <= products.enable;
                step_index <= '0;
                active <= 1'b1;
            end
        end else begin // 正在消费时，每拍移走两个乘积及对应使能位。
            product_q <= product_q >> 44;
            enable_q <= enable_q >> 2;
            if (step_index == 2'd3) begin // 第4对消费结束，本向量已处理完。
                if (products.valid) begin // 新向量恰好到达，直接换入并连续消费。
                    product_q <= products.data;
                    enable_q <= products.enable;
                    step_index <= '0;
                    active <= 1'b1;
                end else begin // 没有后继向量，退出消费状态等待下一次输入。
                    step_index <= '0;
                    active <= 1'b0;
                end
            end else begin // 尚未消费第4对，推进到下一对。
                step_index <= step_index + 1'b1;
            end
        end
    end

    // 偶数行与奇数行各自维护四个轮转和。
    kwt_pe_pipe u_even_pe (
        .clk(clk), .rst_n(rst_n), .load(load_even),
        .load_slot(load_addr[5:4]), .load_data(load_data),
        .compute_step(compute_step), .product_enable(even_enable),
        .product(even_product), .drain_select(drain_even),
        .drain_step(out_step), .drain_data(even_data)
    );
    kwt_pe_pipe u_odd_pe (
        .clk(clk), .rst_n(rst_n), .load(load_odd),
        .load_slot(load_addr[5:4]), .load_data(load_data),
        .compute_step(compute_step), .product_enable(odd_enable),
        .product(odd_product), .drain_select(drain_odd),
        .drain_step(out_step), .drain_data(odd_data)
    );
endmodule
