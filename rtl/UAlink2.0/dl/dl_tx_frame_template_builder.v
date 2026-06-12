`timescale 1ns/1ps
`default_nettype none

// 已确认Figure 2-4布局的TL->640-byte DL frame模板构造器。
// 每个输入是一个完整512-bit TL word；显式SOP打开packet，EOP关闭并允许flush，M由i_tl_msg携带。
// 最多缓存10个TL Flit，按每segment最多TL0/TL1两个起点贪心放置，允许最后一个Flit
// 跨DL frame carry。FH只写Original/Payload模板，sequence由hop-local TX context后写；
// CRC0..CRC3始终为零，本模块不选择A19 wire byte order，也不产生physical-valid。
module dl_tx_frame_template_builder(
 input wire i_clk,input wire i_rstn,input wire i_enable,
 input wire i_tl_valid,output wire o_tl_ready,input wire[511:0] i_tl_data,input wire[1:0] i_tl_msg,
 input wire i_tl_sop,input wire i_tl_eop,input wire i_flush,
 output wire o_frame_valid,input wire i_frame_ready,output wire[511:0] o_frame_data,
 output wire o_frame_sop,output wire o_frame_eop,output wire o_carry_active,
 output wire o_protocol_error,output wire[15:0] o_protocol_error_count,
 output wire o_busy,output wire o_quiescent
);
localparam[1:0] S_CAPTURE=2'd0,S_INIT=2'd1,S_PACK=2'd2,S_OUTPUT=2'd3;
reg[1:0] state_q;reg[511:0] fifo_data[0:9];reg[1:0] fifo_msg[0:9];reg[3:0] head_q,tail_q,count_q;
reg[5119:0] frame_q;reg[7:0] sector_q;reg[2:0] segment_q;reg[1:0] starts_q;reg[4:0] flit_sector_q;reg[3:0] output_beat_q;
reg protocol_error_q,packet_open_q,fatal_q;reg[15:0] protocol_count_q;
wire input_fire,output_fire,input_boundary_ok,flush_boundary_ok,boundary_error_event;
integer data_byte_index;
function automatic[9:0] payload_physical_byte;input[7:0]sector;input[1:0]byte_no;reg[9:0]s,b,p;begin s={2'b0,sector};b={8'b0,byte_no};p=0;
 if(sector<=15)p=s*4+b;else if(sector<=30)p=68+(s-16)*4+b;else if(sector==31)p=(byte_no<3)?64+b:131;
 else if(sector<=46)p=132+(s-32)*4+b;else if(sector==47)p=(byte_no<3)?128+b:194;
 else if(sector<=62)p=196+(s-48)*4+b;else if(sector==63)p=(byte_no<2)?192+b:256+b;
 else if(sector<=78)p=260+(s-64)*4+b;else if(sector==79)p=(byte_no<2)?256+b:319+b;
 else if(sector<=94)p=324+(s-80)*4+b;else if(sector==95)p=(byte_no==0)?320:384+b;
 else if(sector<=110)p=388+(s-96)*4+b;else if(sector==111)p=(byte_no==0)?384:447+b;
 else if(sector<=126)p=452+(s-112)*4+b;else if(sector<=142)p=512+(s-127)*4+b;
 else if(sector<=154)p=580+(s-143)*4+b;else if(sector==155)p=628+b;else p=(byte_no<3)?576+b:635;payload_physical_byte=p;end endfunction
function automatic[9:0] sh_byte;input[2:0]seg;begin case(seg)0:sh_byte=67;1:sh_byte=195;2:sh_byte=323;3:sh_byte=451;default:sh_byte=579;endcase end endfunction
function automatic[7:0] seg_start;input[2:0]seg;begin case(seg)0:seg_start=0;1:seg_start=32;2:seg_start=64;3:seg_start=96;default:seg_start=127;endcase end endfunction
function automatic[7:0] seg_end;input[2:0]seg;begin case(seg)0:seg_end=31;1:seg_end=63;2:seg_end=95;3:seg_end=126;default:seg_end=156;endcase end endfunction
function automatic[7:0] seg_half;input[2:0]seg;begin case(seg)0:seg_half=16;1:seg_half=48;2:seg_half=80;3:seg_half=112;default:seg_half=143;endcase end endfunction
function automatic[3:0] ptr_next;input[3:0]ptr;begin ptr_next=(ptr==9)?0:ptr+1'b1;end endfunction
assign input_boundary_ok=(packet_open_q?!i_tl_sop:i_tl_sop)&&((count_q!=9)||i_tl_eop);
assign flush_boundary_ok=input_fire?(input_boundary_ok&&i_tl_eop):!packet_open_q;
assign o_tl_ready=i_rstn&&i_enable&&!fatal_q&&(state_q==S_CAPTURE)&&(count_q<10);
assign input_fire=i_tl_valid&&o_tl_ready;
assign boundary_error_event=(input_fire&&!input_boundary_ok)||(i_flush&&!flush_boundary_ok);
assign o_frame_valid=i_rstn&&!fatal_q&&(state_q==S_OUTPUT);assign o_frame_data=o_frame_valid?frame_q[output_beat_q*512+:512]:512'd0;
assign o_frame_sop=o_frame_valid&&(output_beat_q==0);assign o_frame_eop=o_frame_valid&&(output_beat_q==9);assign output_fire=o_frame_valid&&i_frame_ready;
assign o_carry_active=(count_q!=0)&&(flit_sector_q!=0);assign o_protocol_error=protocol_error_q;assign o_protocol_error_count=protocol_count_q;
assign o_busy=i_rstn&&(fatal_q||(state_q!=S_CAPTURE)||(count_q!=0));assign o_quiescent=i_rstn&&!fatal_q&&(state_q==S_CAPTURE)&&(count_q==0);

always @(posedge i_clk)begin
 if(!i_rstn)begin state_q<=S_CAPTURE;head_q<=0;tail_q<=0;count_q<=0;frame_q<=0;sector_q<=0;segment_q<=0;starts_q<=0;flit_sector_q<=0;output_beat_q<=0;protocol_error_q<=0;protocol_count_q<=0;packet_open_q<=0;fatal_q<=0;end
 else begin
  case(state_q)
   S_CAPTURE:begin
    if(boundary_error_event)begin protocol_error_q<=1'b1;fatal_q<=1'b1;if(protocol_count_q!=16'hffff)protocol_count_q<=protocol_count_q+1'b1;end
    else if(input_fire)begin
     fifo_data[tail_q]<=i_tl_data;fifo_msg[tail_q]<=i_tl_msg;tail_q<=ptr_next(tail_q);count_q<=count_q+1'b1;packet_open_q<=!i_tl_eop;if(count_q==9)state_q<=S_INIT;
    end
    if(!boundary_error_event&&i_flush&&flush_boundary_ok&&((count_q!=0)||(input_fire&&input_boundary_ok)))state_q<=S_INIT;
   end
   S_INIT:begin
    frame_q<=5120'd0;frame_q[632*8+20]<=1'b1;sector_q<=0;segment_q<=0;starts_q<=0;output_beat_q<=0;
    if(count_q==0)state_q<=S_CAPTURE;
    else begin
     if(flit_sector_q==0)begin frame_q[67*8+4]<=1'b1;frame_q[67*8+2+:2]<=fifo_msg[head_q];starts_q<=1;end
     state_q<=S_PACK;
    end
   end
   S_PACK:begin
    for(data_byte_index=0;data_byte_index<4;data_byte_index=data_byte_index+1)
     frame_q[payload_physical_byte(sector_q,data_byte_index[1:0])*8+:8]<=fifo_data[head_q][flit_sector_q*32+data_byte_index*8+:8];
    if(flit_sector_q==15)begin
     flit_sector_q<=0;head_q<=ptr_next(head_q);count_q<=count_q-1'b1;
     if((count_q==1)||(sector_q==156))begin state_q<=S_OUTPUT;output_beat_q<=0;end
     else if(starts_q==0)begin
      if(sector_q<seg_end(segment_q))begin sector_q<=sector_q+1'b1;frame_q[sh_byte(segment_q)*8+4]<=1'b1;frame_q[sh_byte(segment_q)*8+2+:2]<=fifo_msg[ptr_next(head_q)];starts_q<=1;end
      else if(segment_q<4)begin segment_q<=segment_q+1'b1;sector_q<=seg_start(segment_q+1'b1);frame_q[sh_byte(segment_q+1'b1)*8+4]<=1'b1;frame_q[sh_byte(segment_q+1'b1)*8+2+:2]<=fifo_msg[ptr_next(head_q)];starts_q<=1;end
      else begin state_q<=S_OUTPUT;output_beat_q<=0;end
     end else if(starts_q==1)begin
      if((((sector_q+1'b1)<seg_half(segment_q))?seg_half(segment_q):(sector_q+1'b1))<=seg_end(segment_q))begin
       sector_q<=((sector_q+1'b1)<seg_half(segment_q))?seg_half(segment_q):(sector_q+1'b1);frame_q[sh_byte(segment_q)*8+7]<=1'b1;frame_q[sh_byte(segment_q)*8+5+:2]<=fifo_msg[ptr_next(head_q)];starts_q<=2;
      end else if(segment_q<4)begin segment_q<=segment_q+1'b1;sector_q<=seg_start(segment_q+1'b1);frame_q[sh_byte(segment_q+1'b1)*8+4]<=1'b1;frame_q[sh_byte(segment_q+1'b1)*8+2+:2]<=fifo_msg[ptr_next(head_q)];starts_q<=1;end
      else begin state_q<=S_OUTPUT;output_beat_q<=0;end
     end else if(segment_q<4)begin segment_q<=segment_q+1'b1;sector_q<=seg_start(segment_q+1'b1);frame_q[sh_byte(segment_q+1'b1)*8+4]<=1'b1;frame_q[sh_byte(segment_q+1'b1)*8+2+:2]<=fifo_msg[ptr_next(head_q)];starts_q<=1;end
     else begin state_q<=S_OUTPUT;output_beat_q<=0;end
    end else begin
     flit_sector_q<=flit_sector_q+1'b1;
     if(sector_q==156)begin state_q<=S_OUTPUT;output_beat_q<=0;end
     else if(sector_q==seg_end(segment_q))begin segment_q<=segment_q+1'b1;sector_q<=seg_start(segment_q+1'b1);starts_q<=0;end
     else sector_q<=sector_q+1'b1;
    end
   end
   S_OUTPUT:if(output_fire)begin
    if(output_beat_q==9)begin output_beat_q<=0;if(count_q!=0)state_q<=S_INIT;else state_q<=S_CAPTURE;end else output_beat_q<=output_beat_q+1'b1;
   end
   default:begin state_q<=S_CAPTURE;head_q<=0;tail_q<=0;count_q<=0;flit_sector_q<=0;packet_open_q<=0;protocol_error_q<=1'b1;fatal_q<=1'b1;if(protocol_count_q!=16'hffff)protocol_count_q<=protocol_count_q+1'b1;end
  endcase
 end
end
endmodule
`default_nettype wire
