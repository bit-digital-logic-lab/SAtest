// 阵列控制、乘积和部分和的连接约定；供CSA阵列及32×32块控制器使用。
interface kwt_array_if;
    logic load;                 // 写入一个历史部分和
    logic [31:0] load_data;      // 历史部分和；首次可由上层填bias
    logic step;                 // 控制器规定的A/B输入节拍，无ready握手
    logic flush;                // 请求统一排出部分和
    logic [5:0] out_addr;       // 输出在8×8内的行优先地址
    logic [31:0] out_data;      // 输出的INT32部分和
    modport control(output load,load_data,step,flush,
                    input out_addr,out_data);
    modport compute(input load,load_data,step,flush,
                    output out_addr,out_data);
endinterface

// 驻留PE之间的部分和移位连接；移位使能由阵列统一广播。
interface kwt_psum_if;
    logic [31:0] data; // 上一级持有的部分和
    modport source(output data);
    modport sink(input data);
endinterface
