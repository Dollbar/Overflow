module tl_tx_data_fifo #( // tl_tx_data_fifo模块：双bank有序半Flit发送SRAM缓存
 parameter integer BANK_DEPTH=5, // 每bank精确逻辑容量，总容量为两倍且不借用消费当拍空间
 parameter integer COUNT_WIDTH=(BANK_DEPTH<2)?1:(BANK_DEPTH<4)?2:(BANK_DEPTH<8)?3:(BANK_DEPTH<16)?4:(BANK_DEPTH<32)?5:(BANK_DEPTH<64)?6:(BANK_DEPTH<128)?7:(BANK_DEPTH<256)?8:(BANK_DEPTH<512)?9:(BANK_DEPTH<1024)?10:(BANK_DEPTH<2048)?11:(BANK_DEPTH<4096)?12:(BANK_DEPTH<8192)?13:(BANK_DEPTH<16384)?14:(BANK_DEPTH<32768)?15:16 // 由底层FIFO验证深度及计数宽度
)( // 端口为本地半Flit队列，实际线上消费来自同一发送器
 input wire i_clk,i_rstn,i_write_valid,input wire [1:0] i_write_count, // 同域同步复位及一或二半Flit有序写提议
 input wire [255:0] i_data0,i_data1,output wire o_write_ready,output wire [1:0] o_write_taken, // 输入按先后顺序排列，按实际接纳数量保留未入队项
 input wire [1:0] i_take,output wire [1:0] o_valid_count, // 实际发送确认零至两个当前可见半Flit
 output wire [255:0] o_data0,o_data1,output wire [COUNT_WIDTH:0] o_count, // 队首两项与包含在途读的总占用
 output wire o_error // 非法输入数量或透支可见数据的本地诊断
); // 结束有序发送缓存端口
reg r_write_bank,r_read_bank; // 下一写入和下一消费各自独立的交替bank所有权
wire [1:0] write_ready,read_valid,write_enable,read_enable; // 两个真实FIFO的独立事务资格
wire [255:0] read_data0,read_data1;wire [COUNT_WIDTH-1:0] count0,count1; // 实际bank数据及全生命周期容量
wire write_legal,write_fire,read_legal; // 原子请求数量合法性及真实写接纳
assign write_legal=(i_write_count==2'd1)||(i_write_count==2'd2); // 零或三项不能伪装成有效写请求
assign o_write_ready=i_rstn&&write_legal&&write_ready[r_write_bank]; // 存在队首空位即可接纳第一项，第二项独立受剩余容量限制
assign write_fire=i_write_valid&&o_write_ready; // 至少接纳一项才推进写条带
assign o_write_taken=!write_fire?2'd0:((i_write_count==2'd2)&&write_ready[!r_write_bank])?2'd2:2'd1; // 明确反馈部分接纳，避免最小容量等待整对的死锁
assign o_valid_count=(!i_rstn||!read_valid[r_read_bank])?2'd0:(read_valid[!r_read_bank]?2'd2:2'd1); // 第二bank先返回也不能越过真实队首
assign read_legal=i_rstn&&(i_take<=o_valid_count); // 非法双消费不退化成单消费
assign o_error=i_rstn&&((i_write_valid&&!write_legal)||(i_take>o_valid_count)); // 诊断不改变另一路合法操作
assign o_data0=(o_valid_count!=2'd0)?(r_read_bank?read_data1:read_data0):256'd0; // 队首只由正确bank已完成读缓存提供
assign o_data1=(o_valid_count==2'd2)?(r_read_bank?read_data0:read_data1):256'd0; // 第二项按逻辑顺序选择另一个bank
assign o_count={1'b0,count0}+{1'b0,count1}; // 额外一位保存两个满bank之和
assign write_enable[0]=write_fire&&(!r_write_bank||(o_write_taken==2'd2)); // 第一bank属于单项目标或实际双项写
assign write_enable[1]=write_fire&&(r_write_bank||(o_write_taken==2'd2)); // 第二bank属于单项目标或实际双项写
assign read_enable[0]=read_legal&&(i_take!=2'd0)&&(!r_read_bank||(i_take==2'd2)); // 实际确认后才释放第一bank逻辑容量
assign read_enable[1]=read_legal&&(i_take!=2'd0)&&(r_read_bank||(i_take==2'd2)); // 第二bank容量与线上确认同沿释放
upli_receive_storage #(.C_DEPTH(BANK_DEPTH),.C_DATA_WIDTH(256),.C_COUNT_WIDTH(COUNT_WIDTH)) Bank0_Inst( // 复用已验证注册读FIFO控制及获授权SRAM映射
 .i_clk(i_clk),.i_rstn(i_rstn),.i_write_valid(write_enable[0]),.i_write_data(r_write_bank?i_data1:i_data0),.o_write_ready(write_ready[0]), // 第一bank写入对应条带的真实半Flit
 .i_read_ready(read_enable[0]),.o_read_valid(read_valid[0]),.o_read_data(read_data0),.o_count(count0) // 缓存与在途读仍计入原始容量
); // 结束第一bank实例
upli_receive_storage #(.C_DEPTH(BANK_DEPTH),.C_DATA_WIDTH(256),.C_COUNT_WIDTH(COUNT_WIDTH)) Bank1_Inst( // 第二bank与第一bank使用同一个输入时钟
 .i_clk(i_clk),.i_rstn(i_rstn),.i_write_valid(write_enable[1]),.i_write_data(r_write_bank?i_data0:i_data1),.o_write_ready(write_ready[1]), // 第二bank保持奇偶交替的数据顺序
 .i_read_ready(read_enable[1]),.o_read_valid(read_valid[1]),.o_read_data(read_data1),.o_count(count1) // 独立SRAM预取不会越序释放
); // 结束第二bank实例
always @(posedge i_clk)begin // 写入一项改变下一项所在bank，两项保持原bank
 if(!i_rstn)r_write_bank<=1'b0; // 同步复位从第一bank开始新的逻辑序列
 else if(write_fire&&(o_write_taken==2'd1))r_write_bank<=!r_write_bank; // 实际双写或被拒绝写保持条带相位
end // 结束写条带相位寄存器
always @(posedge i_clk)begin // 消费相位只跟随实际接纳的有序项数
 if(!i_rstn)r_read_bank<=1'b0; // 复位不允许旧SRAM字形成有效队首
 else if(read_legal&&(i_take==2'd1))r_read_bank<=!r_read_bank; // 单消费切换到另一bank，双消费保持
end // 结束读条带相位寄存器
endmodule // 结束tl_tx_data_fifo模块
