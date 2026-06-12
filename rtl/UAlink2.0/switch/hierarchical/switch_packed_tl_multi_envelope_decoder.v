`timescale 1ns/1ps
`default_nettype none
// 已验证Station TL到有序fabric envelope的普通明文事务解码器。
// 每个物理TL入口复用一份真实switch_prepared_assembler；assembler先把Control拆成单字段记录，本模块再逐记录串行输出。
// 每个envelope的header载荷仅保留其自己的128-bit Request或64-bit Response，不能携带同Control中的其它目的字段。
// 当前仅支持普通Read/Write/WriteFull Request与普通unicast Response；Message、Poison、Auth、压缩及其它命令失败关闭。
module switch_packed_tl_multi_envelope_decoder #(
 parameter integer C_PORTS=4,parameter integer C_COUNT_WIDTH=4
)(
 input wire i_clk,input wire i_rstn,input wire [C_PORTS-1:0] i_valid,output wire [C_PORTS-1:0] o_ready,
 input wire [C_PORTS*512-1:0] i_tl_data,input wire [C_PORTS*2-1:0] i_tl_msg,input wire [C_PORTS*10-1:0] i_source_port,
 output wire [C_PORTS-1:0] o_valid,input wire [C_PORTS-1:0] i_ready,output wire [C_PORTS*512-1:0] o_data,
 output wire [C_PORTS*2-1:0] o_tl_msg,output wire [C_PORTS*10-1:0] o_dst_id,output wire [C_PORTS*2-1:0] o_class,
 output wire [C_PORTS*2-1:0] o_original_vc,output wire [C_PORTS-1:0] o_original_pool,output wire [C_PORTS*10-1:0] o_source_port,
 output wire [C_PORTS-1:0] o_sop,output wire [C_PORTS-1:0] o_eop,output wire [C_PORTS*C_COUNT_WIDTH-1:0] o_packet_flits,
 output wire [C_PORTS-1:0] o_busy,output wire [C_PORTS-1:0] o_error,output wire o_config_error
);
 localparam CONFIG_LEGAL=(C_PORTS>=1)&&(C_PORTS<=1024)&&(C_COUNT_WIDTH>=3)&&(C_COUNT_WIDTH<=16);
 wire [C_PORTS-1:0] candidate_valid,candidate_ready,candidate_legal,candidate_sop,candidate_eop,adapter_error;
 wire [C_PORTS*512-1:0] candidate_data;wire [C_PORTS*10-1:0] candidate_dst,candidate_src;
 wire [C_PORTS*2-1:0] candidate_class,candidate_vc;wire [C_PORTS-1:0] candidate_pool;
 wire [C_PORTS*C_COUNT_WIDTH-1:0] candidate_flits;
 wire boundary_config_error;wire [C_PORTS*2-1:0] normalized_msg;wire [C_PORTS-1:0] single_envelope;
 assign normalized_msg=0;assign single_envelope={C_PORTS{1'b1}};assign o_config_error=!CONFIG_LEGAL||boundary_config_error;
 genvar p;
 generate for(p=0;p<C_PORTS;p=p+1)begin:g_decode
  wire asm_ready,asm_busy,asm_error,asm_sticky,asm_captured,asm_done;wire [1:0] source_valid,tags_valid,poison0,poison1;
  wire [511:0] source_control,data0,data1;wire [1023:0] tags;wire [3:0] data_valid;wire [1:0] source_captured;wire [3:0] data_accepted;
  switch_prepared_assembler #(.PORTS(1))u_assembler(
   .i_clk(i_clk),.i_rstn(i_rstn),.i_auth(1'b0),.i_valid(i_valid[p]),.i_flit(i_tl_data[p*512+:512]),.i_msg(i_tl_msg[p*2+:2]),
   .i_source_captured(source_captured),.i_data_accepted(data_accepted),.o_ready(asm_ready),.o_source_valid(source_valid),.o_source_control(source_control),
   .o_source_tags_valid(tags_valid),.o_source_tags(tags),.o_data_valid(data_valid),.o_data0(data0),.o_data1(data1),.o_busy(asm_busy),
   .o_error(asm_error),.o_error_sticky(asm_sticky),.o_captured(asm_captured),.o_done(asm_done),.o_data_poison0(poison0),.o_data_poison1(poison1),.i_discard(1'b0));
  wire role=source_valid[1];wire header_valid=|source_valid;wire [255:0] control=role?source_control[511:256]:source_control[255:0];
  wire decoded;wire [2:0] request_count;wire [3:0] response_count;wire [7:0] field_starts,request_starts,response_starts;
  tl_control_decode u_header_decode(control,decoded,request_count,response_count,field_starts,request_starts,response_starts);
  reg header_found,header_profile;reg [255:0] shifted_field;reg [9:0] parsed_dst;reg [1:0] parsed_vc;reg parsed_pool;reg [3:0] parsed_halves;
  integer sector;
  always @*begin
   header_found=1'b0;header_profile=1'b0;shifted_field=256'd0;parsed_dst=10'd0;parsed_vc=2'd0;parsed_pool=1'b0;parsed_halves=4'd0;
   for(sector=0;sector<8;sector=sector+1)begin
    if(!role&&decoded&&request_count==3'd1&&response_count==4'd0&&request_starts[sector])begin
     shifted_field=control>>(sector*32);header_found=1'b1;parsed_vc=shifted_field[117:116];parsed_pool=shifted_field[102];parsed_dst=shifted_field[14:5];
     if((shifted_field[127:124]==4'd1)&&((shifted_field[123:118]==6'd3)||(shifted_field[123:118]==6'd40)||(shifted_field[123:118]==6'd41)))begin
      header_profile=1'b1;if(shifted_field[123:118]!=6'd3)parsed_halves={1'b0,shifted_field[1:0],1'b0}+4'd2+((shifted_field[123:118]==6'd40)?4'd1:4'd0);
     end
    end
    if(role&&decoded&&request_count==3'd0&&response_count==4'd1&&response_starts[sector])begin
     shifted_field=control>>(sector*32);header_found=1'b1;parsed_vc=shifted_field[59:58];parsed_pool=shifted_field[46];parsed_dst=shifted_field[25:16];
     if((shifted_field[63:60]==4'd2)&&(shifted_field[15:14]==2'd0))begin header_profile=1'b1;if(shifted_field[37])parsed_halves={1'b0,shifted_field[45:44],1'b0}+4'd2;end
    end
   end
  end
  // Data阶段live source_valid已在header握手后撤销，必须使用已锁定packet role选择对应Data lane。
  wire [3:0] live_packet_flits=4'd1+((parsed_halves+4'd1)>>1);wire [1:0] offered=packet_role_q?data_valid[3:2]:data_valid[1:0];wire [3:0] offered_ext={2'b00,offered};
  wire [511:0] normalized_header=role?{448'd0,shifted_field[63:0]}:{384'd0,shifted_field[127:0]};
  reg packet_q,packet_role_q,packet_pool_q;reg [9:0] packet_dst_q,packet_src_q;reg [1:0] packet_vc_q;reg [3:0] packet_halves_q,packet_flits_q;
  wire data_phase=packet_q&&(offered!=2'd0);wire header_phase=header_valid&&!packet_q;
  assign candidate_valid[p]=header_phase||data_phase;
  assign candidate_legal[p]=header_phase?(header_found&&header_profile):(data_phase&&(offered_ext<=packet_halves_q));
  assign candidate_data[p*512+:512]=header_phase?normalized_header:(packet_role_q?{data1[511:256],data0[511:256]}:{data1[255:0],data0[255:0]});
  assign candidate_dst[p*10+:10]=header_phase?parsed_dst:packet_dst_q;assign candidate_src[p*10+:10]=header_phase?i_source_port[p*10+:10]:packet_src_q;
  assign candidate_class[p*2+:2]=header_phase?{1'b0,role}:{1'b0,packet_role_q};assign candidate_vc[p*2+:2]=header_phase?parsed_vc:packet_vc_q;
  assign candidate_pool[p]=header_phase?parsed_pool:packet_pool_q;assign candidate_sop[p]=header_phase;
  assign candidate_eop[p]=header_phase?(parsed_halves==4'd0):(offered_ext==packet_halves_q);
  assign candidate_flits[p*C_COUNT_WIDTH+:C_COUNT_WIDTH]=header_phase?{{(C_COUNT_WIDTH-4){1'b0}},live_packet_flits}:{{(C_COUNT_WIDTH-4){1'b0}},packet_flits_q};
  assign source_captured=(header_phase&&candidate_ready[p]&&candidate_legal[p])?(role?2'b10:2'b01):2'b00;
  assign data_accepted=(data_phase&&candidate_ready[p]&&candidate_legal[p])?(packet_role_q?{offered,2'b00}:{2'b00,offered}):4'd0;
  assign o_ready[p]=CONFIG_LEGAL&&asm_ready;assign o_busy[p]=CONFIG_LEGAL&&(asm_busy||packet_q||o_valid[p]);
  assign o_error[p]=!CONFIG_LEGAL||asm_error||asm_sticky||adapter_error[p];
  wire unused=^{tags_valid,tags,poison0,poison1,asm_captured,asm_done,field_starts,shifted_field};
  always @(posedge i_clk)begin
   if(!i_rstn)begin packet_q<=0;packet_role_q<=0;packet_pool_q<=0;packet_dst_q<=0;packet_src_q<=0;packet_vc_q<=0;packet_halves_q<=0;packet_flits_q<=0;end
   else if(CONFIG_LEGAL)begin
    if(header_phase&&candidate_ready[p]&&candidate_legal[p]&&(parsed_halves!=0))begin packet_q<=1;packet_role_q<=role;packet_pool_q<=parsed_pool;packet_dst_q<=parsed_dst;packet_src_q<=i_source_port[p*10+:10];packet_vc_q<=parsed_vc;packet_halves_q<=parsed_halves;packet_flits_q<=live_packet_flits;end
    else if(data_phase&&candidate_ready[p]&&candidate_legal[p])begin if(offered_ext==packet_halves_q)begin packet_q<=0;packet_halves_q<=0;end else packet_halves_q<=packet_halves_q-offered_ext;end
   end
  end
 end endgenerate
 switch_station_tl_ingress_adapter #(.C_PORTS(C_PORTS),.C_COUNT_WIDTH(C_COUNT_WIDTH),.C_NUM_CLASSES(2))u_boundary(
  .i_clk(i_clk),.i_rstn(i_rstn),.i_valid(candidate_valid),.o_ready(candidate_ready),.i_tl_data(candidate_data),.i_tl_msg(normalized_msg),
  .i_decode_valid(candidate_legal),.i_single_envelope(single_envelope),.i_dst_id(candidate_dst),.i_class(candidate_class),.i_original_vc(candidate_vc),
  .i_original_pool(candidate_pool),.i_source_port(candidate_src),.i_sop(candidate_sop),.i_eop(candidate_eop),.i_packet_flits(candidate_flits),
  .o_valid(o_valid),.i_ready(i_ready),.o_data(o_data),.o_tl_msg(o_tl_msg),.o_dst_id(o_dst_id),.o_class(o_class),.o_original_vc(o_original_vc),
  .o_original_pool(o_original_pool),.o_source_port(o_source_port),.o_sop(o_sop),.o_eop(o_eop),.o_packet_flits(o_packet_flits),.o_error(adapter_error),.o_config_error(boundary_config_error));
endmodule
`default_nettype wire
