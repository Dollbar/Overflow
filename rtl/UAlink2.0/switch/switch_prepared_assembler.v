`timescale 1ns/1ps // 单时钟完整事务组装候选。
`default_nettype none // 禁止隐式连线。
module switch_prepared_assembler #(parameter integer PORTS=4,DISCARD_ENABLE=0)( // switch_prepared_assembler模块：每端口完整ordinary字段组装。
 input wire i_clk,i_rstn, // 同步共同复位。
 input wire [PORTS-1:0] i_auth,i_valid, // Auth在整个reset epoch中保持。
 input wire [PORTS*512-1:0] i_flit, // 只输入TL，不输入旧DL头。
 input wire [PORTS*2-1:0] i_msg,i_source_captured, // 消息标记和真实prepared捕获。
 input wire [PORTS*4-1:0] i_data_accepted, // 每类真实Data半字接纳数量。
 output wire [PORTS*1-1:0] o_ready, // 独立完整源组或实际接纳观察。
 output wire [PORTS*2-1:0] o_source_valid, // 独立完整源组或实际接纳观察。
 output wire [PORTS*512-1:0] o_source_control, // 独立完整源组或实际接纳观察。
 output wire [PORTS*2-1:0] o_source_tags_valid, // 独立完整源组或实际接纳观察。
 output wire [PORTS*1024-1:0] o_source_tags, // 独立完整源组或实际接纳观察。
 output wire [PORTS*4-1:0] o_data_valid, // 独立完整源组或实际接纳观察。
 output wire [PORTS*512-1:0] o_data0, // 独立完整源组或实际接纳观察。
 output wire [PORTS*512-1:0] o_data1, // 独立完整源组或实际接纳观察。
 output wire [PORTS*1-1:0] o_busy, // 独立完整源组或实际接纳观察。
 output wire [PORTS*1-1:0] o_error, // 独立完整源组或实际接纳观察。
 output wire [PORTS*1-1:0] o_error_sticky, // 独立完整源组或实际接纳观察。
 output wire [PORTS*1-1:0] o_captured, // 独立完整源组或实际接纳观察。
 output wire [PORTS*1-1:0] o_done // 独立完整源组或实际接纳观察。
,output wire [PORTS*2-1:0] o_data_poison0,o_data_poison1 // 与每类有序Data半字同时保持。
,input wire [PORTS-1:0] i_discard // 独立已接纳管理记录才丢弃完整未发送字段，不伪造prepared握手。
); // 结束明确ownership接口。
 localparam [31:0] C_PORTS=PORTS; // 常量生成端口。
 genvar p; // 各端口独立组装。
 generate // 只接受有限端口配置。
 if(PORTS!=1&&PORTS!=2&&PORTS!=4)begin:gen_bad_ports // 配置错误明确展开失败。
  switch_prepared_assembler_invalid_ports Invalid_Inst(); // 不截断端口。
 end // 结束参数保护。
 for(p=0;p<C_PORTS;p=p+1)begin:gen_port // 单资源组装所有者。
  reg [1:0] r_state; // 空闲、完整组收集、逐字段交付。
  reg r_error,r_auth,r_header,r_deferred; // 唯一输入责任及旧尾携带的下一组责任。
  reg [2:0] r_fields,r_next_fields;reg [1:0] r_index; // 当前组最多四个ordinary字段。
  reg [5:0] r_total,r_received,r_next_total;reg [3:0] r_sent; // 完整组最大32半字；单字段最大9半字。
  reg [1023:0] r_controls,r_next_controls; // 四个自然位置不变的独立字段。
  reg [15:0] r_needs,r_next_needs;reg [23:0] r_offsets,r_next_offsets; // 每字段独立Data起点和长度。
  reg [3:0] r_roles,r_next_roles;reg [255:0] r_tags; // Auth序号跳过FC，按低sector命令顺序。
  reg [255:0] r_next_control; // 保存旧尾同字的完整原Control用于责任观察。
  reg [31:0] r_poison; // Poison与原Data索引共用所有权。
  reg [255:0] r_payload [0:31];integer reset_word; // 顺序Data/BE总量的有界保存，不增加信用所有者。
  wire [255:0] lower,upper; // 原始TL半字。
  assign lower=i_flit[p*512+:256];assign upper=i_flit[p*512+256+:256]; // 不接收任何DL头。
  wire ctx_allowed,unused_ctx_taken,unused_ctx_rejected,unused_ctx_store; // 实际分类准入。
  wire [2:0] cl,cu;wire [6:0] unused_pending;wire [72:0] unused_be; // 保留真实序列所有者。
  wire [583:0] unused_metadata;wire [79:0] unused_demands,unused_releases; // 不将提议接到任何credit bank。
  tl_receive_context u_context( // 仅捕获时推进实际TL状态。
   .i_clk(i_clk),.i_rstn(i_rstn),.i_commit(o_captured[p]),.i_auth(i_auth[p]), // 与完整存储使用相同事件。
   .i_lower(lower),.i_msg(i_msg[p*2+:2]),.i_type0(lower[7:0]),.i_type1(upper[7:0]), // 完整字段输入。
   .o_allowed(ctx_allowed),.o_taken(unused_ctx_taken),.o_rejected(unused_ctx_rejected), // 唯一分类状态。
   .o_lower(cl),.o_upper(cu),.o_demands(unused_demands),.o_releases(unused_releases), // 不归还信用。
   .o_store(unused_ctx_store),.o_pending(unused_pending),.o_be(unused_be),.o_metadata(unused_metadata)); // 只消费准入与类别。
  wire decoded;wire [2:0] requests;wire [3:0] responses;wire [7:0] field_starts,req_starts,rsp_starts; // 真实自然字段边界。
  tl_control_decode u_decode(lower,decoded,requests,responses,field_starts,req_starts,rsp_starts); // 不能通过猜固定槽恢复字段。
  reg profile;reg [2:0] fields;reg [5:0] total;
  reg [1023:0] controls;reg [15:0] needs;reg [23:0] offsets;reg [3:0] roles;
  reg [255:0] field_value,field_mask;reg [3:0] field_need;integer s;
  wire [255:0] unused_field_payload=field_value; // 未解释位全部随原字段保存。
  wire [6:0] unused_decoded_counts={requests,responses}; // 数量由逐字段有限扫描交叉约束。
  wire [7:0] unused_field_starts=field_starts; // FC资格由共享事件解码器独立解释。
  wire fc_valid;wire [159:0] unused_grants;wire [1:0] unused_nop,unused_init,unused_shared,unused_poison;
  tl_credit_events u_events(lower,upper,2'd0,1'b1,fc_valid,unused_grants,unused_nop,unused_init,unused_shared,unused_poison); // 只作合法性检查，不扣除/归还信用。
  always @*begin // 全Control预检；任一后续非法字段拒绝整个输入字。
   profile=decoded&&fc_valid;fields=3'd0;total=6'd0;controls=1024'd0;needs=16'd0;offsets=24'd0;roles=4'd0;
   field_value=256'd0;field_mask=256'd0;field_need=4'd0;
   for(s=0;s<8;s=s+1)begin
    if(req_starts[s]||rsp_starts[s])begin
     field_value=lower>>(s*32);field_need=4'd0;
     if(req_starts[s])begin
      field_mask=256'hffffffffffffffffffffffffffffffff<<(s*32);
      if(field_value[127:124]!=4'd1||
       !((field_value[123:118]==6'd3)||(field_value[123:118]==6'd40)||(field_value[123:118]==6'd41)||(field_value[123:118]==6'd42))||
       ((field_value[123:118]==6'd3)&&(field_value[1:0]!=2'd0)))profile=1'b0;
      field_need=(field_value[123:118]==6'd3)?4'd0:({1'b0,field_value[1:0],1'b0}+4'd2+(((field_value[123:118]==6'd40)||(field_value[123:118]==6'd42))?4'd1:4'd0));
     end else begin
      field_mask=256'hffffffffffffffff<<(s*32);
      if(field_value[63:60]!=4'd2||field_value[15:14]!=2'd0)profile=1'b0;
      field_need=field_value[37]?({1'b0,field_value[45:44],1'b0}+4'd2):4'd0;
     end
     if(fields<3'd4)begin
      controls[fields*32'd256+:256]=lower&field_mask;
      needs[fields*32'd4+:4]=field_need;offsets[fields*32'd6+:6]=total;
      roles[fields[1:0]]=rsp_starts[s];
     end else profile=1'b0;
     fields=fields+3'd1;total=total+{2'd0,field_need};
    end
   end
   if(total>6'd32)profile=1'b0;
  end
  wire dl=(cl==3'd1)||(cl==3'd2)||(cl==3'd5),du=(cu==3'd1)||(cu==3'd2)||(cu==3'd5);
  wire [1:0] incoming_count={1'b0,dl}+{1'b0,du};
  wire [255:0] r_control=r_controls[r_index*32'd256+:256]; // 当前独立字段，供真实目的/VC/role解析。
  wire r_role=r_roles[r_index];wire [3:0] r_need=r_needs[r_index*32'd4+:4];
  wire [63:0] r_tag=r_tags[r_index*32'd64+:64];
  wire [5:0] offset=r_offsets[r_index*32'd6+:6];
  wire [3:0] remaining=r_need-r_sent;
  wire [1:0] offered=(i_rstn&&!r_error&&r_state==2'd2&&r_header)?((remaining>4'd1)?2'd2:remaining[1:0]):2'd0;
  wire [3:0] offer=r_role?{offered,2'd0}:{2'd0,offered};
  wire [1:0] source_valid=(i_rstn&&!r_error&&r_state==2'd2&&!r_header)?(r_role?2'b10:2'b01):2'b00;
  wire [1:0] ack=r_role?i_data_accepted[p*4+2+:2]:i_data_accepted[p*4+:2];
  wire discard_taken=(DISCARD_ENABLE!=0)&&i_discard[p]&&(|source_valid);
  wire bad_ack=((DISCARD_ENABLE!=0)&&i_discard[p]&&(!(|source_valid)||(|i_source_captured[p*2+:2])))||(|(i_source_captured[p*2+:2]&~source_valid))||(i_data_accepted[p*4+:2]>offer[1:0])||(i_data_accepted[p*4+2+:2]>offer[3:2]);
  wire local_fc=profile&&(fields==3'd0);
  wire swapped_header=(r_state==2'd1)&&!i_auth[p]&&!r_deferred&&profile&&(fields!=3'd0)&&(cl==3'd0)&&du&&(r_received+6'd1==r_total);
  wire unused_tags_zero=(upper>>(fields*32'd64))==256'd0;
  wire content_allowed,unused_content_taken,unused_content_rejected,unused_content_fatal,unused_pair_open,unused_pair_poison; // 复用真实内容配对，不增加信用。
  tl_content u_content(i_clk,i_rstn,o_captured[p],lower,upper,cl,cu,{1'b0,fields},content_allowed,unused_content_taken,unused_content_rejected,unused_content_fatal,unused_pair_open,unused_pair_poison); // 两半必须属于同一Poison状态的Beat。
  wire legal=ctx_allowed&&content_allowed&&(!i_msg[p*2]||(cl==3'd5))&&(!i_msg[p*2+1]||(cu==3'd5))&&
   ((r_state==2'd0)?(local_fc?(upper==256'd0):(profile&&(fields!=3'd0)&&
    (i_auth[p]?(cu==3'd6&&unused_tags_zero):((total==6'd0)?(cu==3'd3&&upper==256'd0):du)))):
   ((cl==3'd0||dl)&&(du||cu==3'd3)&&((cl!=3'd0)||local_fc||swapped_header)&&((cu!=3'd3)||(upper==256'd0))&&
    (({1'b0,r_received}+{5'd0,incoming_count})<={1'b0,r_total})));
  assign o_error[p]=i_rstn&&!r_error&&(bad_ack||(i_valid[p]&&r_state!=2'd2&&!legal));
  assign o_error_sticky[p]=i_rstn&&r_error;
  assign o_ready[p]=i_rstn&&!r_error&&!bad_ack&&r_state!=2'd2&&(!i_valid[p]||legal);
  assign o_captured[p]=i_valid[p]&&o_ready[p];
  assign o_busy[p]=i_rstn&&(r_state!=2'd0);
  assign o_done[p]=i_rstn&&!r_error&&!bad_ack&&(r_state==2'd2)&&
   (discard_taken||(!r_header&&(|i_source_captured[p*2+:2])&&(r_need==4'd0))||(r_header&&({1'b0,r_sent}+{3'd0,ack}=={1'b0,r_need})));
  assign o_source_valid[p*2+:2]=source_valid;
  assign o_source_control[p*512+:512]=source_valid[0]?{256'd0,r_control}:source_valid[1]?{r_control,256'd0}:512'd0;
  assign o_source_tags_valid[p*2+:2]=source_valid&{2{r_auth}};
  assign o_source_tags[p*1024+:1024]=(source_valid[0]&&r_auth)?{960'd0,r_tag}:(source_valid[1]&&r_auth)?{448'd0,r_tag,512'd0}:1024'd0;
  assign o_data_valid[p*4+:4]=offer;
  wire [255:0] unused_next_control=r_next_control; // 调试观察不参与功能。
  wire [6:0] data_position={1'b0,offset}+{3'd0,r_sent};
  wire [1:0] unused_position_high=data_position[6:5];
  wire [4:0] second_position=data_position[4:0]+5'd1;
  assign o_data_poison0[p*2+:2]=(offered!=0)?(r_role?{r_poison[data_position[4:0]],1'b0}:{1'b0,r_poison[data_position[4:0]]}):2'd0; // 标记与第一项完全同序。
  assign o_data_poison1[p*2+:2]=(offered==2)?(r_role?{r_poison[second_position],1'b0}:{1'b0,r_poison[second_position]}):2'd0; // 标记与第二项完全同序。
  wire [511:0] shifted={r_payload[second_position],r_payload[data_position[4:0]]};
  assign o_data0[p*512+:512]=(offered!=2'd0)?(r_role?{shifted[255:0],256'd0}:{256'd0,shifted[255:0]}):512'd0;
  assign o_data1[p*512+:512]=(offered==2'd2)?(r_role?{shifted[511:256],256'd0}:{256'd0,shifted[511:256]}):512'd0;
  always @(posedge i_clk)begin
   if(!i_rstn)begin
    r_state<=0;r_error<=0;r_auth<=0;r_header<=0;r_deferred<=0;
    r_fields<=0;r_next_fields<=0;r_index<=0;r_total<=0;r_received<=0;r_next_total<=0;r_sent<=0;
    r_controls<=0;r_next_controls<=0;r_needs<=0;r_next_needs<=0;r_offsets<=0;r_next_offsets<=0;
    r_poison<=0;r_roles<=0;r_next_roles<=0;r_tags<=0;r_next_control<=0;for(reset_word=0;reset_word<32;reset_word=reset_word+1)r_payload[reset_word]<=0;
   end else if(o_error[p])r_error<=1'b1;
   else if(!r_error)begin
    if(o_done[p])begin // 每字段实际全部转交才释放本次route/arbiter owner。
     r_header<=0;r_sent<=0;
     if({1'b0,r_index}+3'd1<r_fields)r_index<=r_index+2'd1;
     else begin
      r_index<=0;r_deferred<=0;
      if(r_deferred)begin
       r_state<=(r_next_total==0)?2'd2:2'd1;r_controls<=r_next_controls;r_fields<=r_next_fields;
       r_roles<=r_next_roles;r_needs<=r_next_needs;r_offsets<=r_next_offsets;r_total<=r_next_total;
       r_received<=0;r_auth<=0;r_tags<=0;
      end else r_state<=0;
     end
    end else if(r_state==2'd2)begin
     if(|i_source_captured[p*2+:2])r_header<=1'b1;
     r_sent<=r_sent+{2'd0,ack};
    end else if(o_captured[p])begin
     if(r_state==2'd0&&fields!=0)begin
      r_controls<=controls;r_fields<=fields;r_roles<=roles;r_needs<=needs;r_offsets<=offsets;r_total<=total;
      r_index<=0;r_auth<=i_auth[p];r_tags<=i_auth[p]?upper:256'd0;r_header<=0;r_sent<=0;
      r_received<={4'd0,incoming_count};if(du)begin r_payload[0]<=upper;r_poison[0]<=(cu==3'd5);end
      r_state<=({4'd0,incoming_count}==total)?2'd2:2'd1;
     end else if(r_state==2'd1)begin
      if(swapped_header)begin
       r_deferred<=1'b1;r_next_control<=lower;r_next_controls<=controls;r_next_fields<=fields;
       r_next_roles<=roles;r_next_needs<=needs;r_next_offsets<=offsets;r_next_total<=total;
      end
      if(dl)begin r_payload[r_received[4:0]]<=lower;r_poison[r_received[4:0]]<=(cl==3'd5);end
      if(du)begin r_payload[r_received[4:0]+{4'd0,dl}]<=upper;r_poison[r_received[4:0]+{4'd0,dl}]<=(cu==3'd5);end
      r_received<=r_received+{4'd0,incoming_count};
      if(r_received+{4'd0,incoming_count}==r_total)r_state<=2'd2;
     end
    end
   end
  end
 end
 endgenerate
endmodule
`default_nettype wire
