`timescale 1ns/1ps // 定义已组装Write执行器的数字仿真时间单位。
`default_nettype none // 禁止隐式网络掩盖完整事务字段接线错误。
module endpoint_write_completer #( // Write Completer模块保存完整事务，等待真实后端完成后返回无Data响应。
 parameter integer CAPACITY=4, // 本轮支持一至四个完整请求和完成预约槽。
 parameter integer SLOT_WIDTH=(CAPACITY<=2)?1:2 // 单槽也保留至少一位；允许上层显式固定两位ABI。
)( // 以下接口只接收已完整验证Data归属的组装后事务。
 input wire i_clk,i_rstn, // 单时钟、同步低有效复位；不代表撤销已发生的内存副作用。
 input wire [9:0] i_local_id, // 本地ID在运行期间保持稳定。
 input wire i_request_valid,output wire o_request_ready, // 一次握手预留整个请求和完成资源。
 input wire [10:0] i_request_tag,input wire [9:0] i_request_src,i_request_dst, // 保留完整Tag及源目的ID。
 input wire i_request_full,input wire [56:0] i_request_address,input wire [5:0] i_request_length, // Full种类、完整地址和DWORD长度减一。
 input wire [7:0] i_request_attr,input wire [1:0] i_request_vc,input wire i_request_pool, // 写属性不复用Read的字节使能含义。
 input wire [1:0] i_request_asi,input wire [7:0] i_request_metadata, // 后端定义的访问空间和元数据原样传递。
 input wire [2047:0] i_request_data,input wire [255:0] i_request_be, // 相对Beat零在最低512位，BE按整个256字节区域定位。
 output wire o_mem_valid,input wire i_mem_ready,output wire [SLOT_WIDTH-1:0] o_mem_slot, // 完整事务执行命令与本地完成关联槽。
 output wire [56:0] o_mem_address,output wire [5:0] o_mem_length,output wire [7:0] o_mem_attr, // 保留完整访问地址和属性。
 output wire [1:0] o_mem_asi,output wire [7:0] o_mem_metadata, // 保留所有后端定义元数据。
 output wire [2047:0] o_mem_data,output wire [255:0] o_mem_be, // Full重建区域BE，普通Write保留稀疏或全零BE。
 input wire i_mem_result_valid,output wire o_mem_result_ready,input wire [SLOT_WIDTH-1:0] i_mem_result_slot, // 命令接纳与实际完成是不同事件。
 input wire [3:0] i_mem_result_status, // 普通远端Write允许0、2、3、6、8五种完成状态。
 output wire o_source_valid,output wire [255:0] o_source_control,input wire i_source_captured, // Header低64位为WriteResponse，其余NOP，无Data输出。
 output wire o_error,output wire [7:0] o_count // 非法事件组合诊断与未完整退休槽占用。
); // 结束完整组装后Write执行接口。
 localparam integer SLOTS=(CAPACITY>=1&&CAPACITY<=4)?CAPACITY:1; // 非法容量也安全展开非空数组。
 localparam CONFIG_LEGAL=(CAPACITY>=1)&&(CAPACITY<=4)&&(SLOT_WIDTH>=1)&&(SLOT_WIDTH<=2)&&((1<<SLOT_WIDTH)>=CAPACITY); // 不允许静默截断槽号。
 localparam integer LAST_SLOT_VALUE=SLOTS-1; // 先计算有界真实回绕点。
 localparam [SLOT_WIDTH-1:0] LAST_SLOT=LAST_SLOT_VALUE[SLOT_WIDTH-1:0]; // 明确选择可表示真实槽号的位宽。
 localparam [7:0] COUNT_LIMIT=SLOTS[7:0]; // 与公开八位占用比较保持明确宽度。
 wire active,request_legal,request_fire,memory_fire,result_fire,status_legal,retire; // 分离各实际所有权推进事件。
 wire [8:0] request_bytes,request_end; // 九位计算覆盖完整256字节长度与跨界末端。
 reg [255:0] range_be; // 当前请求的区域定位有效范围。
 reg [SLOT_WIDTH-1:0] allocate_q,issue_q,head_q; // 独立请求接纳、内存命令和响应退休指针。
 reg [7:0] count_q; // 容量不在内存接纳时释放。
 reg [SLOTS-1:0] busy_q,issued_q,complete_q; // 每槽完整执行生命周期。
 reg [10:0] tag_q[0:SLOTS-1];reg [9:0] src_q[0:SLOTS-1],dst_q[0:SLOTS-1]; // 保存完整响应身份。
 reg [56:0] address_q[0:SLOTS-1];reg [5:0] length_q[0:SLOTS-1]; // 保存完整访问几何。
 reg [7:0] attr_q[0:SLOTS-1],metadata_q[0:SLOTS-1];reg [1:0] asi_q[0:SLOTS-1]; // 保存后端定义属性。
 reg [2047:0] data_q[0:SLOTS-1];reg [255:0] be_q[0:SLOTS-1]; // 每槽真实保存全部四Beat和区域BE。
 reg [3:0] status_q[0:SLOTS-1]; // 完成状态仅由一次合法后端返回更新。
 reg [56:0] issue_address;reg [5:0] issue_length;reg [7:0] issue_attr,issue_metadata;reg [1:0] issue_asi; // 内存命令组合字段。
 reg [2047:0] issue_data;reg [255:0] issue_be; // 内存反压期间从同一槽读取完整数据。
 reg issue_busy,issue_issued,head_busy,head_complete,result_legal; // 有界选择只访问真实槽。
 reg [10:0] head_tag;reg [9:0] head_src,head_dst;reg [3:0] head_status; // 有界选择的响应字段。
 integer byte_index,read_slot; // 编译期有界循环使用独立控制变量。
 assign active=i_rstn&&CONFIG_LEGAL; // 非法参数封锁接纳并同步保持所有槽为空。
 assign request_bytes={1'b0,i_request_length,2'b00}+9'd4; // LEN63正确得到256，而不是八位回零。
 assign request_end={1'b0,i_request_address[7:0]}+request_bytes; // 末端最大511，可明确拒绝跨256字节区域。
 always @(*) begin // 为普通Write验证范围，为Full重建范围BE。
  range_be=256'd0; // 未覆盖的区域字节全部禁止写入。
  for(byte_index=0;byte_index<256;byte_index=byte_index+1) begin // 覆盖完整区域所有自然字节编号。
   if(byte_index[8:0]>={1'b0,i_request_address[7:0]}&&byte_index[8:0]<request_end)range_be[byte_index]=1'b1; // 相对Beat数据不改变区域BE位置。
  end // 结束固定256字节范围推导。
 end // 组合默认赋值覆盖全部BE位。
 assign request_legal=(i_request_dst==i_local_id)&&(i_request_vc==2'd0)&&!i_request_pool&&(i_request_address[1:0]==2'd0)&&(request_end<=9'd256)&&(!i_request_full||((i_request_address[5:0]==6'd0)&&(i_request_length[3:0]==4'd15)))&&(i_request_full||((i_request_be&~range_be)==256'd0)); // 属性不受无依据的Read限制；Full忽略输入BE。
 assign o_request_ready=active&&request_legal&&(count_q<COUNT_LIMIT); // 满槽仅背压，不把接纳当作执行完成。
 assign request_fire=i_request_valid&&o_request_ready; // 原子预留完整请求和后端完成空间。
 assign status_legal=(i_mem_result_status==4'd0)||(i_mem_result_status==4'd2)||(i_mem_result_status==4'd3)||(i_mem_result_status==4'd6)||(i_mem_result_status==4'd8); // 不接收保留状态或本地ISOLATE作为远端普通响应。
 always @(*) begin // 固定索引读取避免非二次幂memory_map生成不存在的补齐行。
  issue_address=57'd0;issue_length=6'd0;issue_attr=8'd0;issue_metadata=8'd0;issue_asi=2'd0;issue_data=2048'd0;issue_be=256'd0; // 默认无命令字段。
  issue_busy=1'b0;issue_issued=1'b0;head_busy=1'b0;head_complete=1'b0;result_legal=1'b0; // 未用slot既不有效也不别名。
  head_tag=11'd0;head_src=10'd0;head_dst=10'd0;head_status=4'd0; // 默认无响应身份。
  for(read_slot=0;read_slot<SLOTS;read_slot=read_slot+1) begin // 展开成每个真实槽的显式选择。
   if(issue_q==read_slot[SLOT_WIDTH-1:0]) begin // 命令顺序与请求接纳顺序一致。
    issue_busy=busy_q[read_slot];issue_issued=issued_q[read_slot];issue_address=address_q[read_slot];issue_length=length_q[read_slot]; // 选择有效状态和完整地址长度。
    issue_attr=attr_q[read_slot];issue_metadata=metadata_q[read_slot];issue_asi=asi_q[read_slot];issue_data=data_q[read_slot];issue_be=be_q[read_slot]; // 选择完整数据和后端属性。
   end // 结束内存命令选择。
   if(head_q==read_slot[SLOT_WIDTH-1:0]) begin // 响应保守按请求顺序提交。
    head_busy=busy_q[read_slot];head_complete=complete_q[read_slot];head_tag=tag_q[read_slot];head_src=src_q[read_slot];head_dst=dst_q[read_slot];head_status=status_q[read_slot]; // 仅真实完成才能公开此身份。
   end // 结束队首响应选择。
   if(i_mem_result_slot==read_slot[SLOT_WIDTH-1:0])result_legal=busy_q[read_slot]&&issued_q[read_slot]&&!complete_q[read_slot]&&status_legal; // 空闲、未issued、重复或保留状态返回不能更新任何槽。
  end // 结束全部真实槽的有限组合译码。
 end // 组合默认值完整，无锁存器或补齐读行。
 assign o_mem_valid=active&&issue_busy&&!issue_issued; // 完整事务已拥有存储后才发出后端命令。
 assign o_mem_slot=issue_q; // slot随完整命令稳定到实际接纳。
 assign o_mem_address=issue_address; // 完整57位地址不截断或限定本地测试映射。
 assign o_mem_length=issue_length;assign o_mem_attr=issue_attr;assign o_mem_asi=issue_asi;assign o_mem_metadata=issue_metadata; // 后端属性逐字段透传。
 assign o_mem_data=issue_data; // 四个相对Beat原样保存和转交。
 assign o_mem_be=issue_be; // 固定256位区域掩码，不随Beat数缩短。
 assign memory_fire=o_mem_valid&&i_mem_ready; // 接纳命令不触发Response。
 assign o_mem_result_ready=active; // 合法请求已预约结果空间，非法返回也消费诊断。
 assign result_fire=i_mem_result_valid&&o_mem_result_ready&&result_legal; // 只有真实合法完成改变有效槽。
 assign o_source_valid=active&&head_busy&&head_complete; // 不把命令接纳或issued冒充完成。
 assign o_source_control=o_source_valid?{192'd0,4'd2,2'd0,head_tag,1'b0,2'd0,2'd0,head_status,1'b0,1'b0,head_dst,head_src,2'd0,14'd0}:256'd0; // 普通未压缩WriteResponse低64位，RD_WR/LAST/LEN/OFFSET均零，无Data。
 assign retire=o_source_valid&&i_source_captured; // 无Data响应在Header所有权转移后释放槽。
 assign o_count=active?count_q:8'd0; // 非法配置和复位不公开旧占用。
 assign o_error=i_rstn&&(!CONFIG_LEGAL||(i_request_valid&&!request_legal)||(i_mem_result_valid&&!result_legal)||(i_source_captured&&!o_source_valid)); // 满槽等待不报错，非法事件不偷偷改变其他事务。
 always @(posedge i_clk) begin // 指针和容量仅由真实握手推进。
  if(!active)begin allocate_q<=0;issue_q<=0;head_q<=0;count_q<=8'd0;end // 同步复位清空本地生命周期，不回滚外部内存。
  else begin // 独立槽可并行接纳、返回和退休。
   if(request_fire)begin if(allocate_q==LAST_SLOT)allocate_q<=0;else allocate_q<=allocate_q+1'b1;end // 仅在实际接纳后转向下个真实槽。
   if(memory_fire)begin if(issue_q==LAST_SLOT)issue_q<=0;else issue_q<=issue_q+1'b1;end // 后端命令保持有序。
   if(retire)begin if(head_q==LAST_SLOT)head_q<=0;else head_q<=head_q+1'b1;end // 响应只推进已真实捕获的队首。
   case({request_fire,retire}) // 同沿独立一进一出保持准确占用。
    2'b10:count_q<=count_q+8'd1; // 新接纳只增加一次。
    2'b01:count_q<=count_q-8'd1; // 完整响应只释放一次。
    default:count_q<=count_q; // 空闲或同时进出保持计数。
   endcase // 结束容量更新。
  end // 结束非复位状态推进。
 end // 结束共享指针过程。
 genvar slot; // 每个槽使用静态固定索引寄存器写入。
 generate for(slot=0;slot<SLOTS;slot=slot+1)begin:slots // 非二次幂也只实例化实际容量。
  localparam [SLOT_WIDTH-1:0] INDEX=slot; // 与外部slot匹配保持精确宽度。
  always @(posedge i_clk)begin // 每槽独立保存完整请求及实际完成。
   if(!active)begin busy_q[slot]<=1'b0;issued_q[slot]<=1'b0;complete_q[slot]<=1'b0;end // 清除有效状态即可阻止旧描述符重新执行。
   else begin // 大数据寄存器不需要复位填零。
    if(request_fire&&allocate_q==INDEX)begin // 接纳即预留全部描述符、数据、BE和结果状态。
     busy_q[slot]<=1'b1;issued_q[slot]<=1'b0;complete_q[slot]<=1'b0;tag_q[slot]<=i_request_tag;src_q[slot]<=i_request_src;dst_q[slot]<=i_request_dst; // 完整身份只在新接纳时写入。
     address_q[slot]<=i_request_address;length_q[slot]<=i_request_length;attr_q[slot]<=i_request_attr;asi_q[slot]<=i_request_asi;metadata_q[slot]<=i_request_metadata; // 保留完整后端访问语义。
     data_q[slot]<=i_request_data;be_q[slot]<=i_request_full?range_be:i_request_be; // 普通零BE不丢弃事务，Full重建有效范围。
    end // 结束完整请求保存。
    if(memory_fire&&issue_q==INDEX)issued_q[slot]<=1'b1; // 从下一周期起才允许对应后端结果。
    if(result_fire&&i_mem_result_slot==INDEX)begin complete_q[slot]<=1'b1;status_q[slot]<=i_mem_result_status;end // 一次真实完成原子保存响应状态。
    if(retire&&head_q==INDEX)begin busy_q[slot]<=1'b0;issued_q[slot]<=1'b0;complete_q[slot]<=1'b0;end // Header捕获后才允许此槽复用。
   end // 结束槽正常执行分支。
  end // 结束槽寄存器过程。
 end endgenerate // 结束真实容量的静态槽阵列。
endmodule // 结束组装后普通Write/WriteFull执行器。
`default_nettype wire // 恢复外围编译单元默认网络规则。
