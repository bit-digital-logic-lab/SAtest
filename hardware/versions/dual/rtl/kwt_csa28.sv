// 双乘PE的组合三压二：驻留旧和与相邻两个K的乘积压成两数，交给kwt_acc28完成CPA。
module kwt_csa28 (
    input logic [27:0] old_sum,p0,p1, // 同一输出的旧和、两个符号扩展乘积
    output logic [27:0] sum_bits,carry_bits // 压缩两数，carry已左移一位
);
    assign sum_bits=old_sum ^ p0 ^ p1; // 每位奇偶和，不跨位传播进位。
    assign carry_bits=((old_sum&p0)|(old_sum&p1)|(p0&p1))<<1; // 多数进位移到高一位，丢弃第28位外溢。
endmodule
