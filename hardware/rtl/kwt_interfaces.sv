// 阵列控制、乘积和部分和的连接约定；供CSA阵列及32×32块控制器使用。
interface kwt_array_if;
    logic load;                 // 每拍写入一整行历史部分和
    logic [255:0] load_data;      // 历史部分和；首次可由上层填bias
    logic step;                 // 控制器规定的A/B输入节拍，无ready握手
    logic flush;                // 请求统一排出部分和
    logic [2:0] out_row;        // 当前输出行号0～7
    logic [255:0] out_data;     // 一整行8个INT32部分和，低位为第0列
    modport control(output load,load_data,step,flush,
                    input out_row,out_data);
    modport compute(input load,load_data,step,flush,
                    output out_row,out_data);
endinterface

// 驻留PE之间的部分和移位连接；移位使能由阵列统一广播。
interface kwt_psum_if;
    logic [31:0] data; // 上一级持有的部分和
    modport source(output data);
    modport sink(input data);
endinterface

// 4×4块之间的整行部分和通道；四列并行，移位复用各PE原sum寄存器。
interface kwt_psum_row_if;
    logic [127:0] data; // 一行四个INT32，低位为本块第0列
    modport source(output data);
    modport sink(input data);
endinterface
