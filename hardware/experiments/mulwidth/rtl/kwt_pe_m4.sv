// 4乘PE：每拍并行4个A12×W10三级乘法，经三级3:2压缩树合成两数，由单个kwt_acc28做28位CPA。
// 乘积按各自out_enable屏蔽为0，零通道不影响同拍其他通道；驻留和与行移位复用kwt_acc28寄存器。
module kwt_pe_m4 (
    input logic clk,rst_n, // 时钟、低有效复位
    input logic signed [11:0] a0,a1,a2,a3, // 4个K通道的激活
    input logic signed [9:0] b0,b1,b2,b3, // 4个K通道的权重
    input logic compute,init,shift, // 固定发射、旧和上传、结果整行移位
    kwt_psum_if.sink psum_in, // 上一行同列的部分和
    kwt_psum_if.source psum_out // 本PE驻留和，符号扩展为32位
);
    logic signed [11:0] av[0:3]; // 端口到数组的别名，便于展开4个乘法器
    logic signed [9:0] bv[0:3];
    logic [3:0] v,e; // 4路三级流水有效位与零值使能
    logic signed [21:0] product[0:3]; // 4个完整22位有符号乘积
    logic [27:0] p[0:3]; // 符号扩展并屏蔽后的28位乘积
    logic [27:0] acc; // 唯一驻留部分和
    logic [27:0] s0,c0,s1,c1,s2,c2; // 压缩树中间和位/进位位
    logic all_valid,any_enable; // 4路对齐有效、至少一路非零

    assign av[0]=a0; assign av[1]=a1; assign av[2]=a2; assign av[3]=a3; // 端口展开
    assign bv[0]=b0; assign bv[1]=b1; assign bv[2]=b2; assign bv[3]=b3;
    assign all_valid = v[0]&v[1]&v[2]&v[3]; // 4个乘法器输出有效位必须同拍对齐。
    assign any_enable = e[0]|e[1]|e[2]|e[3]; // 全零拍不更新ACC28，但其他通道非零时必须累加。
    assign psum_out.data = {{4{acc[27]}},acc}; // 28位补码和符号扩展回32位行总线。

    // 4个独立乘法器同时接收同一compute，各自三级流水，绝不复用。
    genvar gi;
    generate
        for (gi=0;gi<4;gi++) begin : g_mul
            kwt_mul u_mul(.clk(clk),.rst_n(rst_n),.in_valid(compute),
                .a(av[gi]),.b(bv[gi]),.out_valid(v[gi]),.out_enable(e[gi]),
                .product(product[gi]));
            // 先符号扩展到28位，再按该通道enable清零；不能丢掉同拍非零通道。
            assign p[gi] = e[gi] ? {{6{product[gi][21]}},product[gi]} : 28'b0;
        end
    endgenerate

    // SPEC固定树：p0..p2、p3与首级和/进位、最后并入驻留和。
    kwt_csa3 u_csa0(.a(p[0]),.b(p[1]),.c(p[2]),.s(s0),.co(c0)); // 三个乘积压成两数。
    kwt_csa3 u_csa1(.a(p[3]),.b(s0),.c(c0),.s(s1),.co(c1)); // 第4个乘积并入上一级两数。
    kwt_csa3 u_csa2(.a(acc),.b(s1),.c(c1),.s(s2),.co(c2)); // 驻留旧和作为第4级输入。
    // 单拍28位CPA在kwt_acc28内完成；load优先于valid，移位复用同一寄存器。
    kwt_acc28 u_acc(.clk(clk),.rst_n(rst_n),.load(init||shift),
        .load_data(psum_in.data),.valid(all_valid&&any_enable),
        .sum_bits(s2),.carry_bits(c2),.sum(acc));
endmodule
