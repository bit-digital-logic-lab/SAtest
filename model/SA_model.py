def mul ( a , b ):
    return a * b  #一个简单地乘法器

class adder: 
    # 求和加法器，两个加法器负责一列
    def __init__(self,old_sum):
        self.res_width = 38
        self.res = old_sum.copy()
        self.count = 0

    def add(self, par_res):
        max_value = (1 << (self.res_width - 1)) - 1
        min_value = -(1 << (self.res_width - 1))

        value = self.res[self.count] + par_res

        self.res[self.count] = max(min_value, min(value, max_value))

        self.count = (self.count + 1) % len(self.res)

        

    def clean(self):
        for i in range(len(self.res)) :
            self.res[i] = 0
            self.count = 0


class mat_colum:
    # 乘法矩阵的一列
    def __init__(self,oldsum):
        num_add = 2
        num_mul = 8
        self.adders = [
            adder(oldsum[i::num_add])
            for i in range(num_add)
        ]
        self.mul = mul
        self.temp_res = [0] * 8
        self.res = [0] * 8

    def run (self,a,b):
        for i in range(len(b)):
            self.temp_res[i] = self.mul(a,b[i]) #mul

        for i in range(len(self.temp_res)):
            self.adders[i%2].add(self.temp_res[i]) #add

        for i in range(len(self.res)):
            self.res [i]= self.adders[i%2].res[i//2] #report



class mat :
    # 完整的计算部分，脉冲矩阵
    def __init__(self,old_sum):
        num_col = 8
        num_row = 8

        self.mat_colum = [
            mat_colum(old_sum[i * num_row : (i + 1) * num_row])
            for i in range(num_col)
        ]

        self.new_sum = [0] * num_col * num_row

    def run (self,a,b):
        for i in range(len(a)):
            self.mat_colum[i].run(a[i],b) #compute

        for i in range(len(a)):
            for j in range(len(b)):
                self.new_sum[i*8 + j] = self.mat_colum[i].res[j]  


class SA:
    def __init__(self, A, B, old_sum):
        self.A = A
        self.B = B

        self.M = len(A)
        self.K = len(A[0])
        self.N = len(B[0])

        self.C = [row.copy() for row in old_sum]

        self.cache_A = [0] * 64
        self.cache_B = [0] * 64
        self.cache_C = [0] * 64

    def get_block(self, i, j, k):
        """
        i：输出行起点
        j：输出列起点
        k：归约维起点
        加载 A[i:i+8, k:k+8] 和 C[i:i+8, j:j+8]
        """
        for r in range(8):
            for c in range(8):
                index = r * 8 + c

                # 输入块，不足的位置补零
                if i + r < self.M and k + c < self.K:
                    self.cache_A[index] = self.A[i + r][k + c]
                else:
                    self.cache_A[index] = 0

                # 加载当前输出块的历史和
                if i + r < self.M and j + c < self.N:
                    self.cache_C[index] = self.C[i + r][j + c]
                else:
                    self.cache_C[index] = 0

    def get_weight(self, k, j):
        """加载 B[k:k+8, j:j+8]。"""
        for r in range(8):
            for c in range(8):
                index = r * 8 + c

                if k + r < self.K and j + c < self.N:
                    self.cache_B[index] = self.B[k + r][j + c]
                else:
                    self.cache_B[index] = 0

    def compute(self):
        # 创建对象，装入本块历史和
        self.core = mat(self.cache_C)

        for k in range(8):
            # A 块的一列
            a = [
                self.cache_A[r * 8 + k]
                for r in range(8)
            ]

            # B 块的一行
            b = [
                self.cache_B[k * 8 + c]
                for c in range(8)
            ]

            self.core.run(a, b)

        self.cache_C = self.core.new_sum.copy()

    def write_back(self, i, j):
        for r in range(8):
            for c in range(8):
                if i + r < self.M and j + c < self.N:
                    self.C[i + r][j + c] = self.cache_C[r * 8 + c]

    def run(self):
        for j in range(0, self.N, 8):
            for k in range(0, self.K, 8):
                # 权重块驻留，复用到下面所有输入行块
                self.get_weight(k, j)

                for i in range(0, self.M, 8):
                    self.get_block(i, j, k)
                    self.compute()
                    self.write_back(i, j)

        return [row.copy() for row in self.C]

        


            









    
