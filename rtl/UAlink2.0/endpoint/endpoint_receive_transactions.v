`default_nettype none
// 已退休TL记录到单64B Read事务的有限容量适配；不产生新的信用归还。
module endpoint_receive_transactions #(parameter WRITE_ENABLE=0)(
 input wire i_clk,i_rstn,input wire [1:0] i_port,
 input wire i_read_valid,output wire o_read_ready,
 input wire [511:0] i_read_flit,input wire [1:0] i_read_msg,
 input wire [5:0] i_read_classes,input wire [79:0] i_read_releases,
 output wire o_request_valid,input wire i_request_ready,
 output wire [10:0] o_request_tag,output wire [9:0] o_request_src,o_request_dst,
 output wire [56:0] o_request_address,output wire [5:0] o_request_length,
 output wire [7:0] o_request_attr,output wire [1:0] o_request_vc,
 output wire o_request_pool,output wire [1:0] o_request_asi,
 output wire [7:0] o_request_metadata,
 output wire o_response_valid,input wire i_response_ready,
 output wire [1:0] o_response_port,output wire [10:0] o_response_tag,
 output wire [9:0] o_response_dst,output wire [3:0] o_response_status,
 output wire [1:0] o_response_offset,output wire o_response_last,
 output wire [1:0] o_response_num_beats,output wire [511:0] o_response_data,
 output wire o_response_data_error,output wire o_error,
 output wire o_request_is_write,o_request_full,output wire [2047:0] o_request_data,output wire [255:0] o_request_be,output wire o_response_is_write
);
reg [599:0] r_record; // 保持原退休记录观察点，两个展开模式均整字接纳
 generate if(WRITE_ENABLE==0)begin:read_only
 assign o_request_is_write=1'b0;assign o_request_full=1'b0;assign o_request_data=2048'd0;assign o_request_be=256'd0;assign o_response_is_write=1'b0;
localparam EMPTY=3'd0,CHECK=3'd1,LOWER=3'd2,SCAN=3'd3,UPPER=3'd4;
reg [2:0] r_state;
reg [1:0] r_port;
reg [3:0] r_sector;
reg r_error;
wire [2:0] lower_class=r_record[516:514],upper_class=r_record[519:517];
wire decoded;
wire [2:0] unused_request_count;
wire [3:0] unused_response_count;
wire [7:0] unused_starts,request_starts,response_starts;
tl_control_decode u_decode(.i_half(r_record[255:0]),.o_valid(decoded),
 .o_requests(unused_request_count),.o_responses(unused_response_count),.o_field_starts(unused_starts),
 .o_request_starts(request_starts),.o_response_starts(response_starts));
wire [255:0] shifted=r_record[255:0]>>(r_sector*32);
wire [127:0] field128=shifted[127:0];
wire [63:0] field64=shifted[63:0];
// 已预检字段的类型/保留位无需再次出现在typed输出中。
wire unused_output_fields=^{shifted[255:128],field128[127:118],field128[4:0],
 field64[63:58],field64[46],field64[37],field64[35:26],field64[15:0]};
wire scanning=(r_state==SCAN)&&(r_sector<4'd8);
wire request_here=scanning&&request_starts[r_sector[2:0]];
wire response_here=scanning&&response_starts[r_sector[2:0]];
wire assembler_error,header_ready,data_ready,response_valid;
wire header_valid=i_rstn&&!o_error&&response_here;
wire data_valid=i_rstn&&!o_error&&(((r_state==LOWER)&&(lower_class==3'd1))||
 ((r_state==UPPER)&&(upper_class==3'd1)));
wire [255:0] data_half=(r_state==LOWER)?r_record[255:0]:r_record[511:256];
assign o_error=r_error||assembler_error;
assign o_read_ready=i_rstn&&!o_error&&(r_state==EMPTY);
assign o_request_valid=i_rstn&&!o_error&&request_here;
assign o_request_tag=field128[113:103];
assign o_request_src=field128[24:15];assign o_request_dst=field128[14:5];
assign o_request_address={field128[79:25],2'b00};
assign o_request_length=field128[93:88];assign o_request_attr=field128[101:94];
assign o_request_vc=field128[117:116];assign o_request_pool=field128[102];
assign o_request_asi=field128[115:114];assign o_request_metadata=field128[87:80];
assign o_response_valid=response_valid&&!r_error;
endpoint_response_assembler u_assembler(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_header_valid(header_valid),.o_header_ready(header_ready),
 .i_header_port(r_port),.i_header_tag(field64[57:47]),.i_header_dst(field64[25:16]),
 .i_header_status(field64[41:38]),.i_header_offset(field64[43:42]),
 .i_header_last(field64[36]),.i_header_num_beats(field64[45:44]),
 .i_data_valid(data_valid),.o_data_ready(data_ready),.i_data_port(r_port),.i_data(data_half),
 .o_response_valid(response_valid),.i_response_ready(i_response_ready&&!r_error),
 .o_response_port(o_response_port),.o_response_tag(o_response_tag),
 .o_response_dst(o_response_dst),.o_response_status(o_response_status),
 .o_response_offset(o_response_offset),.o_response_last(o_response_last),
 .o_response_num_beats(o_response_num_beats),.o_response_data(o_response_data),
 .o_response_data_error(o_response_data_error),.o_error(assembler_error));
function read_profile;
 input [127:0] f;
 reg unused_payload;
 begin
  unused_payload=^{f[113:103],f[79:29],f[24:5],f[3:2]};
  read_profile=(f[127:124]==4'd1)&&(f[123:118]==6'd3)&&
   (f[117:114]==4'd0)&&!f[102]&&(f[101:94]==8'hff)&&
   (f[93:88]==6'd15)&&(f[87:80]==8'd0)&&(f[28:25]==4'd0)&&
   !f[4]&&(f[1:0]==2'd0); // CLOAD0时CWAY忽略；NUMBEATS0是本地窄profile。
 end
endfunction
function response_profile;
 input [63:0] f;
 reg unused_payload;
 begin
  unused_payload=^{f[57:47],f[35:16],f[13:0]};
  response_profile=(f[63:60]==4'd2)&&(f[59:58]==2'd0)&&!f[46]&&
   (f[45:42]==4'd0)&&((f[41:38]==4'd0)||(f[41:38]==4'd3))&&
   f[37]&&f[36]&&(f[15:14]==2'd0); // SRC仅保留于线上，SPARE不成为接收拒绝条件。
 end
endfunction
reg bad;
reg [2:0] kind;
reg message;
reg [255:0] word,probe;
wire unused_probe_high=^probe[255:128];
integer h,s;
always @*begin
 bad=1'b0;kind=3'd7;message=1'b0;word=0;probe=0;
 for(h=0;h<2;h=h+1)begin
  kind=(h==0)?lower_class:upper_class;
  message=r_record[512+h];word=(h==0)?r_record[255:0]:r_record[511:256];
  if(message&&(kind!=3'd4)&&(kind!=3'd5))bad=1'b1;
  if(!message&&((kind==3'd4)||(kind==3'd5)))bad=1'b1;
  case(kind)
   3'd0:if(h!=0||!decoded)bad=1'b1;
   3'd1:begin end
   3'd3:if(word!=256'd0)bad=1'b1;
   3'd4:if((word[7:0]!=8'd0)&&(word[7:0]!=8'd1))bad=1'b1;
   3'd2,3'd5,3'd6,3'd7: bad=1'b1;
   default:bad=1'b1;
  endcase
 end
 if(lower_class==3'd0)begin
  for(s=0;s<8;s=s+1)begin
   probe=r_record[255:0]>>(s*32);
   if(request_starts[s])begin
    if((s!=0&&s!=4)||!read_profile(probe[127:0]))bad=1'b1;
   end
   if(response_starts[s])begin
    if((s%2!=0)||!response_profile(probe[63:0]))bad=1'b1;
   end
  end
 end
end
always @(posedge i_clk)begin
 if(!i_rstn)begin r_state<=EMPTY;r_record<=0;r_port<=0;r_sector<=0;r_error<=0;end
 else if(!o_error)begin
  case(r_state)
   EMPTY:if(i_read_valid&&o_read_ready)begin
    r_record<={i_read_releases,i_read_classes,i_read_msg,i_read_flit};r_port<=i_port;r_state<=CHECK;
   end
   CHECK:if(bad)r_error<=1'b1;else r_state<=LOWER;
   LOWER:begin
    if(lower_class==3'd0)begin r_sector<=0;r_state<=SCAN;end
    else if(lower_class!=3'd1||data_ready)r_state<=UPPER;
   end
   SCAN:begin
    if(r_sector==4'd8)r_state<=UPPER;
    else if((!request_here||i_request_ready)&&(!response_here||header_ready))r_sector<=r_sector+4'd1;
   end
   UPPER:if(upper_class!=3'd1||data_ready)r_state<=EMPTY;
   default:r_error<=1'b1;
  endcase
 end
end
end else begin:mixed
localparam EMPTY=3'd0,CHECK=3'd1,LOWER=3'd2,SCAN=3'd3,UPPER=3'd4,EARLY=3'd5; // 整字预检后按共享Data归属推进
reg [2:0] state; reg [1:0] port; reg [3:0] sector; reg error_q,upper_done; // 当前退休字的独立持有状态
reg [127:0] requests[0:7]; reg [2047:0] request_data[0:7]; reg [255:0] request_be[0:7]; // 请求与全部数据空间同时预约
reg [1:0] request_port[0:7],response_port[0:7]; // Payload延续必须属于同一端口
reg [63:0] responses[0:7];reg [511:0] response_data[0:7]; // Read和无Data写响应使用独立出口队列
reg [7:0] request_complete,response_complete; // 完整内容才可交付后端或Tag表
reg [2:0] request_head,request_tail,response_head,response_tail; // 八槽自然回绕，不增补虚构槽
reg [3:0] request_count,response_count; // Header预约包含尚未收齐的数据
reg [15:0] owner_write;reg [2:0] owner_slot[0:15]; // 两类Data共用严格顺序所有者队列
reg [3:0] owner_head,owner_tail,half_count;reg [4:0] owner_count; // 最多八请求加八响应，半字从零计数
wire [2:0] lower_class=r_record[516:514],upper_class=r_record[519:517]; // 元数据与payload同次保存
wire decoded;wire [7:0] request_starts,response_starts; // 复用真实自然字段起点解码
wire [2:0] unused_request_count;wire [3:0] unused_response_count;wire [7:0] unused_field_starts; // 明确连接结构解码的非消费输出
wire [255:0] shifted=r_record[255:0]>>(sector*32); // 当前自然字段在低端对齐
wire [127:0] f128=shifted[127:0];wire [63:0] f64=shifted[63:0]; // 只提取当前字段，不重新排序Control
wire scanning=state==SCAN&&sector<8; // 一次最多交付一个自然字段
wire req_here=scanning&&request_starts[sector[2:0]];wire rsp_here=scanning&&response_starts[sector[2:0]]; // 请求和响应分类
wire field_write=f128[123:118]==6'h28||f128[123:118]==6'h29;wire field_read_response=f64[37]; // 无Data字段不进入所有者队列
wire req_space=request_count<8&&(!field_write||owner_count<16); // 每个Header原子预约所需真实空间
wire rsp_space=response_count<8&&(!field_read_response||owner_count<16); // 写响应仍独立保存，不等待Data
wire req_push=i_rstn&&!error_q&&req_here&&req_space;wire rsp_push=i_rstn&&!error_q&&rsp_here&&rsp_space; // 实际字段入队事件
wire owner_push=(req_push&&field_write)||(rsp_push&&field_read_response); // 保持所有带Data字段的Control顺序
wire req_pop=o_request_valid&&i_request_ready,rsp_pop=o_response_valid&&i_response_ready; // 输出背压只影响对应队列
wire [127:0] req_out=o_request_valid?requests[request_head]:128'd0; // 未完成槽不暴露请求字段
wire [63:0] rsp_out=o_response_valid?responses[response_head]:64'd0; // 响应按同类出口顺序交付
wire payload_state=(state==LOWER&&lower_class!=0)||state==UPPER||state==EARLY; // Control扫描与Payload消费分离
wire [2:0] payload_class=state==LOWER?lower_class:upper_class; // 提前上半只消费此前所有者，仍先整字预检
wire [255:0] payload=state==LOWER?r_record[255:0]:r_record[511:256]; // 原始半字不进行大小端交换
wire payload_event=i_rstn&&!error_q&&payload_state&&(payload_class==1||payload_class==2); // 普通Message/NOP不消费Data
wire [2:0] data_slot=owner_slot[owner_head]; // 只在owner_count非零时使用
wire data_is_write=owner_write[owner_head];wire [127:0] data_request=requests[data_slot]; // 数据所属请求不依赖输出队首
wire [3:0] write_halves=({2'd0,data_request[1:0]}+4'd1)<<1; // 一至四Beat对应二至八半字
wire data_full=data_request[123:118]==6'h29; // WriteFull不消费后续BE字段
wire expect_be=data_is_write&&!data_full&&half_count==write_halves; // 普通Write仅在全部Data后需要BE
wire payload_port_ok=port==(data_is_write?request_port[data_slot]:response_port[data_slot]); // 防止跨端口误归属
reg [255:0] allowed_be;integer byte_index; // 区域BE按完整地址低八位和扩宽长度构造
wire [8:0] byte_start={1'b0,data_request[30:25],2'b00}; // 256-byte区域内起点
wire [8:0] byte_size=({3'd0,data_request[93:88]}+9'd1)<<2; // 256字节长度不会溢出为零
wire unused_mixed_fields=^{shifted[255:128],req_out[127:124],req_out[4:0],rsp_out[63:58],rsp_out[46],rsp_out[35:26],rsp_out[15:0],data_request[127:124],data_request[117:94],data_request[87:31],data_request[24:2]}; // 身份与保留位不参加Data计数
always @* begin // 有界字节mask组合，不从传入BE推导合法范围
 allowed_be=256'd0; // 未被请求的所有位必须为零
 for(byte_index=0;byte_index<256;byte_index=byte_index+1) // 固定区域的全部字节
  if(byte_index[8:0]>=byte_start&&byte_index[8:0]<byte_start+byte_size)allowed_be[byte_index]=1'b1; // 自然区域位图，宽度明确保持九位
end // 完整赋值无锁存
wire payload_ok=owner_count!=0&&payload_port_ok&&((expect_be&&payload_class==2&&((payload&~allowed_be)==0))||(!expect_be&&payload_class==1)); // 非法BE或无归属Data不推进
wire owner_pop=payload_event&&payload_ok&&(expect_be||(data_is_write?data_full&&half_count+1==write_halves:half_count==1)); // 完整事务最后半字才完成
assign o_error=error_q;assign o_read_ready=i_rstn&&!error_q&&state==EMPTY; // 原600位所有权仅接纳一次
assign o_request_valid=i_rstn&&!error_q&&request_count!=0&&request_complete[request_head]; // 后端永不看到部分Write
assign o_request_is_write=req_out[123:118]==6'h28||req_out[123:118]==6'h29;assign o_request_full=req_out[123:118]==6'h29; // 明确typed请求种类
assign o_request_tag=req_out[113:103];assign o_request_src=req_out[24:15];assign o_request_dst=req_out[14:5]; // 完整身份保持
assign o_request_address={req_out[79:25],2'b00};assign o_request_length=req_out[93:88];assign o_request_attr=req_out[101:94]; // 地址不截高位
assign o_request_vc=req_out[117:116];assign o_request_pool=req_out[102];assign o_request_asi=req_out[115:114];assign o_request_metadata=req_out[87:80]; // 写属性交付后端
assign o_request_data=o_request_valid?request_data[request_head]:2048'd0;assign o_request_be=o_request_valid?request_be[request_head]:256'd0; // 保持全部Beat及区域BE
assign o_response_valid=i_rstn&&!error_q&&response_count!=0&&response_complete[response_head]; // 写响应无需虚构Data
assign o_response_is_write=o_response_valid&&!rsp_out[37];assign o_response_port=o_response_valid?response_port[response_head]:2'd0; // kind参与共享Tag匹配
assign o_response_tag=rsp_out[57:47];assign o_response_dst=rsp_out[25:16];assign o_response_status=rsp_out[41:38]; // SRC不参与功能身份
assign o_response_offset=rsp_out[43:42];assign o_response_last=rsp_out[36];assign o_response_num_beats=rsp_out[45:44]; // 无效写字段原样交付而不额外拒绝
assign o_response_data=o_response_valid&&rsp_out[37]?response_data[response_head]:512'd0;assign o_response_data_error=1'b0; // poison仍为显式未实现错误路径
 tl_control_decode u_decode(.i_half(r_record[255:0]),.o_valid(decoded),.o_requests(unused_request_count),.o_responses(unused_response_count),.o_field_starts(unused_field_starts),.o_request_starts(request_starts),.o_response_starts(response_starts)); // 结构解码不能代替语义检查
function request_legal; // 未压缩Read子集及完整普通Write几何校验
 input [127:0] f;reg [8:0] size,offset,beats;reg write_cmd,unused_fields; // 中间运算扩宽至可表示256字节
 begin
 size=({3'd0,f[93:88]}+9'd1)<<2;offset={1'b0,f[30:25],2'b00};beats=({3'd0,f[28:25],2'b00}+size+9'd63)>>6;
 unused_fields=^{f[113:103],f[79:31],f[24:5],f[3:2]}; // 语义检查不以身份值作为合法性依据
 write_cmd=f[123:118]==6'h28||f[123:118]==6'h29;
 request_legal=f[127:124]==1&&f[117:116]==0&&!f[102]&&!f[4]&&
 (write_cmd?(offset+size<=256&&beats>=1&&beats<=4&&{7'd0,f[1:0]}==beats-9'd1&&
 (f[123:118]!=6'h29||(f[28:25]==0&&f[91:88]==4'hf))):
 (f[123:118]==3&&f[115:114]==0&&f[101:94]==8'hff&&f[93:88]==15&&f[87:80]==0&&f[28:25]==0&&f[1:0]==0));
 end
endfunction
function response_legal; // 写响应忽略OFFSET/LAST的无效取值，不强制建议值
 input [63:0] f;reg status_ok,unused_fields;
 begin
 status_ok=f[41:38]==0||f[41:38]==3||(!f[37]&&(f[41:38]==2||f[41:38]==6||f[41:38]==8));
 unused_fields=^{f[57:47],f[35:16],f[13:0]}; // 响应SRC与SPARE不成为身份/合法性条件
 response_legal=f[63:60]==2&&f[59:58]==0&&!f[46]&&f[45:44]==0&&status_ok&&f[15:14]==0&&(!f[37]||(f[43:42]==0&&f[36]));
 end
endfunction
reg bad,control_has_data;reg [2:0] check_kind;reg [255:0] check_word,probe;integer h,s; // 整个记录在公开其中字段之前检查
wire unused_probe_high=^probe[255:128]; // 检查窗口只消费最低自然字段
always @* begin
 bad=0;control_has_data=0;check_kind=0;check_word=0;probe=0;
 for(h=0;h<2;h=h+1)begin
  check_kind=h==0?lower_class:upper_class;check_word=h==0?r_record[255:0]:r_record[511:256];
  if(r_record[512+h]!=(check_kind==4||check_kind==5))bad=1;
  case(check_kind)
   0:if(h!=0||!decoded)bad=1;
   1,2:begin end
   3:if(check_word!=0)bad=1;
   4:if(check_word[7:0]!=0&&check_word[7:0]!=1)bad=1;
   default:bad=1;
  endcase
 end
 if(lower_class==0)begin
  for(s=0;s<8;s=s+1)begin
   probe=r_record[255:0]>>(s*32);
   if(request_starts[s])begin
    if((s!=0&&s!=4)||!request_legal(probe[127:0]))bad=1;
    if(probe[123:118]==6'h28||probe[123:118]==6'h29)control_has_data=1;
   end
   if(response_starts[s])begin
    if(s%2!=0||!response_legal(probe[63:0]))bad=1;
    if(probe[37])control_has_data=1;
   end
  end
  if(owner_count==0&&(upper_class==2||(upper_class==1&&!control_has_data)))bad=1; // 新所有者的第一个半字必须是Data
 end
end
always @(posedge i_clk)begin
 if(!i_rstn)begin
  state<=EMPTY;r_record<=0;port<=0;sector<=0;error_q<=0;upper_done<=0;
  request_head<=0;request_tail<=0;request_count<=0;request_complete<=0;
  response_head<=0;response_tail<=0;response_count<=0;response_complete<=0;
  owner_head<=0;owner_tail<=0;owner_count<=0;owner_write<=0;half_count<=0;
 end else if(!error_q)begin
  case({req_push,req_pop})2'b10:request_count<=request_count+1'b1;2'b01:request_count<=request_count-1'b1;default:begin end endcase
  case({rsp_push,rsp_pop})2'b10:response_count<=response_count+1'b1;2'b01:response_count<=response_count-1'b1;default:begin end endcase
  case({owner_push,owner_pop})2'b10:owner_count<=owner_count+1'b1;2'b01:owner_count<=owner_count-1'b1;default:begin end endcase
  if(req_push)begin
   requests[request_tail]<=f128;request_port[request_tail]<=port;request_data[request_tail]<=0;request_be[request_tail]<=0;
   request_complete[request_tail]<=!field_write;request_tail<=request_tail+1'b1;
  end
  if(rsp_push)begin
   responses[response_tail]<=f64;response_port[response_tail]<=port;response_data[response_tail]<=0;
   response_complete[response_tail]<=!field_read_response;response_tail<=response_tail+1'b1;
  end
  if(owner_push)begin owner_write[owner_tail]<=req_push;owner_slot[owner_tail]<=req_push?request_tail:response_tail;owner_tail<=owner_tail+1'b1;end
  if(req_pop)begin request_complete[request_head]<=0;request_head<=request_head+1'b1;end
  if(rsp_pop)begin response_complete[response_head]<=0;response_head<=response_head+1'b1;end
  if(payload_event)begin
   if(!payload_ok)error_q<=1;
   else begin
    if(data_is_write)begin
     if(expect_be)request_be[data_slot]<=payload;
     else request_data[data_slot][half_count*256+:256]<=payload;
     if(owner_pop)begin request_complete[data_slot]<=1;if(data_full)request_be[data_slot]<=allowed_be;end
    end else begin
     response_data[data_slot][half_count*256+:256]<=payload;
     if(owner_pop)response_complete[data_slot]<=1;
    end
    if(owner_pop)begin owner_head<=owner_head+1'b1;half_count<=0;end else half_count<=half_count+1'b1;
   end
  end
  case(state)
   EMPTY:if(i_read_valid&&o_read_ready)begin r_record<={i_read_releases,i_read_classes,i_read_msg,i_read_flit};port<=i_port;state<=CHECK;upper_done<=0;end
   CHECK:if(bad)error_q<=1;else state<=LOWER;
   LOWER:if(lower_class==0)begin sector<=0;if(owner_count!=0&&(upper_class==1||upper_class==2))state<=EARLY;else state<=SCAN;end else state<=UPPER;
   EARLY:begin upper_done<=1;state<=SCAN;end // 旧尾先消耗可释放空间，后续Control字段仍按sector顺序入队
   SCAN:if(sector==8)state<=upper_done?EMPTY:UPPER;else if((!req_here||req_space)&&(!rsp_here||rsp_space))sector<=sector+1'b1;
   UPPER:state<=EMPTY;
   default:error_q<=1;
  endcase
 end
end

end endgenerate
endmodule
`default_nettype wire
