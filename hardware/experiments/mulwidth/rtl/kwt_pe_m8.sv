// 8乘PE：每拍并行8个A12×W10三级乘法，经7个3:2压缩器组成固定树，再由单个kwt_acc28做28位CPA。
// 端口与m4同构，仅增加a4..a7/b4..b7；乘积按各自out_enable屏蔽，valid需8路对齐且至少一路非零。
module kwt_pe_m8 (
    input logic clk,rst_n, // 时钟、低有效复位
    input logic signed [11:0] a0,a1,a2,a3,a4,a5,a6,a7, // 8个K通道的激活
    input logic signed [9:0] b0,b1,b2,b3,b4,b5,b6,b7, // 8个K通道的权重
    input logic compute,init,shift, // 固定发射、旧和上传、结果整行移位
    kwt_psum_if.sink psum_in, // 上一行同列的部分和
    kwt_psum_if.source psum_out // 本PE驻留和，符号扩展为32位
);
    logic signed [11:0] av[0:7]; // 端口到数组的别名，便于展开8个乘法器
    logic signed [9:0] bv[0:7];
    logic [7:0] v,e; // 8路三级流水有效位与零值使能
    logic signed [21:0] product[0:7]; // 8个完整22位有符号乘积
    logic [27:0] p[0:7]; // 符号扩展并屏蔽后的28位乘积
    logic [27:0] acc; // 唯一驻留部分和
    logic [27:0] s0,c0,s1,c1,s2,c2,s3,c3,s4,c4,s5,c5,s6,c6; // 7级压缩树中间结果
    logic all_valid,any_enable; // 8路对齐有效、至少一路非零

    assign av[0]=a0; assign av[1]=a1; assign av[2]=a2; assign av[3]=a3; // 端口展开
    assign av[4]=a4; assign av[5]=a5; assign av[6]=a6; assign av[7]=a7;
    assign bv[0]=b0; assign bv[1]=b1; assign bv[2]=b2; assign bv[3]=b3;
    assign bv[4]=b4; assign bv[5]=b5; assign bv[6]=b6; assign bv[7]=b7;
    assign all_valid = v[0]&v[1]&v[2]&v[3]&v[4]&v[5]&v[6]&v[7]; // 8路输出有效必须同拍。
    assign any_enable = e[0]|e[1]|e[2]|e[3]|e[4]|e[5]|e[6]|e[7]; // 全零拍保持ACC28。
    assign psum_out.data = {{4{acc[27]}},acc}; // 28位补码和符号扩展回32位行总线。

    // 8个独立乘法器接收同一compute；零值仍占流水位置，仅屏蔽数据更新。
    genvar gi;
    generate
        for (gi=0;gi<8;gi++) begin : g_mul
            kwt_mul u_mul(.clk(clk),.rst_n(rst_n),.in_valid(compute),
                .a(av[gi]),.b(bv[gi]),.out_valid(v[gi]),.out_enable(e[gi]),
                .product(product[gi]));
            // 先符号扩展到28位，再按该通道enable清零。
            assign p[gi] = e[gi] ? {{6{product[gi][21]}},product[gi]} : 28'b0;
        end
    endgenerate

    // SPEC固定树：先把9个数（8乘积+旧和）压到6个，再逐级压到2个。
    kwt_csa3 u_csa0(.a(p[0]),.b(p[1]),.c(p[2]),.s(s0),.co(c0)); // 第1组3乘积。
    kwt_csa3 u_csa1(.a(p[3]),.b(p[4]),.c(p[5]),.s(s1),.co(c1)); // 第2组3乘积。
    kwt_csa3 u_csa2(.a(p[6]),.b(p[7]),.c(acc),.s(s2),.co(c2)); // 第3组2乘积加旧和。
    kwt_csa3 u_csa3(.a(s0),.b(c0),.c(s1),.s(s3),.co(c3)); // 合并前两组。
    kwt_csa3 u_csa4(.a(c1),.b(s2),.c(c2),.s(s4),.co(c4)); // 合并第2组进位与第3组。
    kwt_csa3 u_csa5(.a(s3),.b(c3),.c(s4),.s(s5),.co(c5)); // 继续压两数。
    kwt_csa3 u_csa6(.a(s5),.b(c5),.c(c4),.s(s6),.co(c6)); // 树顶输出两数。
    // 单拍28位CPA在kwt_acc28内完成；load优先于valid。
    kwt_acc28 u_acc(.clk(clk),.rst_n(rst_n),.load(init||shift),
        .load_data(psum_in.data),.valid(all_valid&&any_enable),
        .sum_bits(s6),.carry_bits(c6),.sum(acc));
endmodule
