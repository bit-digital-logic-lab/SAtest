// 阵列控制、乘积和部分和的连接约定；供三种计算版本及32×32块控制器使用。
interface kwt_array_if;
    logic load;                 // 写入一个历史部分和
    logic [5:0] load_addr;       // 8×8内的行优先地址
    logic [31:0] load_data;      // 历史部分和；首次可由上层填bias
    logic step;                 // 控制器规定的A/B输入节拍，无ready握手
    logic flush;                // 请求统一排出部分和
    logic [5:0] out_addr;       // 输出在8×8内的行优先地址
    logic [31:0] out_data;      // 输出的INT32部分和
    modport control(output load,load_addr,load_data,step,flush,
                    input out_addr,out_data);
    modport compute(input load,load_addr,load_data,step,flush,
                    output out_addr,out_data);
endinterface

// 一列乘法器到加法PE列的乘积向量，不携带外部矩阵地址。
interface kwt_product_if #(parameter int ROWS=8);
    logic [ROWS*22-1:0] data; // 每行一个有符号22位乘积
    logic valid;             // 本拍乘积有效
    logic [ROWS-1:0] enable; // 各行非零乘积使能；零值不停止流水位置
    modport source(output data,valid,enable);
    modport sink(input data,valid,enable);
endinterface

// 驻留PE之间的部分和移位连接；移位使能由阵列统一广播。
interface kwt_psum_if;
    logic [31:0] data; // 上一级持有的部分和
    modport source(output data);
    modport sink(input data);
endinterface
