// 阵列外加法版：块控制器每四拍发射一次，三拍乘积送往两PE列，无内部反压。
module kwt_array_pipe (
    input logic clk, rst_n,          // 时钟、低有效复位
    input logic [95:0] a_rows,       // 独立A端口：八个12位行输入
    input logic [79:0] b_cols,       // 独立B端口：八个10位列输入
    kwt_array_if.compute bus        // 固定输入节拍、上传和下载控制
);
    logic draining;                 // 固定64拍下载阶段
    logic [5:0] drain_addr;         // 行优先输出位置
    logic [31:0] col_out[0:7];      // 八列原部分和寄存器输出
    assign bus.out_addr=drain_addr; // 行优先下载，不需要输出地址重排。
    assign bus.out_data=col_out[drain_addr[2:0]]; // 地址低3位选择当前列。

    for (genvar c=0;c<8;c++) begin : columns // 每列乘法独立，八行A共享广播。
        kwt_product_if #(8) products(); // 三拍乘积和零值使能，仅向前传递。
        kwt_mul_column #(.ROWS(8)) u_mul(.clk(clk),.rst_n(rst_n),.a_rows(a_rows),
            .weight($signed(b_cols[c*10+:10])),.valid(bus.step),.products(products));
        kwt_column_pipe #(.COL(c)) u_col(.clk(clk),.rst_n(rst_n),
            .load(bus.load),.load_addr(bus.load_addr),.load_data(bus.load_data),
            .products(products),.out_addr(drain_addr),.out_step(draining),.out_data(col_out[c]));
    end

    // 上层固定等待最后一次加法提交，然后发flush；下载不插空拍。
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin draining<=0; drain_addr<=0; end // 复位后等待新任务。
        else if (bus.flush) begin draining<=1; drain_addr<=0; end // 下一拍起逐项输出。
        else if (draining) begin // 每拍输出一项，外部按相同节拍写回。
            if (drain_addr==63) begin draining<=0; drain_addr<=0; end // 第64项后结束。
            else drain_addr<=drain_addr+1'b1; // 继续下载下一行优先位置。
        end
    end
endmodule
