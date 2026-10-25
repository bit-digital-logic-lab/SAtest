// 一列三拍乘法器；A按行直达，B向列内广播，乘积经interface送入加法PE列。
module kwt_mul_column #(parameter int ROWS=8) (
    input logic clk, rst_n,               // 时钟、低有效复位
    input logic [ROWS*12-1:0] a_rows,      // 各行12位激活值
    input logic signed [9:0] weight,      // 本列10位权重
    input logic valid,                   // 本拍接受一个向量
    kwt_product_if.source products       // 三拍后乘积、有效位和逐行零值使能
);
    logic [ROWS-1:0] lane_valid;          // 各行有效时序相同，接口取第0行
    assign products.valid = lane_valid[0]; // 所有行接收相同valid，取第0行作为整列有效位。
    for (genvar r=0;r<ROWS;r++) begin : rows // 每行实例化一个乘法器，行索引在展开时固定。
        kwt_mul u_mul(.clk(clk),.rst_n(rst_n),.in_valid(valid),
            .a($signed(a_rows[r*12+:12])),.b(weight),
            .out_valid(lane_valid[r]),.out_enable(products.enable[r]),
            .product(products.data[r*22+:22]));
    end
endmodule
