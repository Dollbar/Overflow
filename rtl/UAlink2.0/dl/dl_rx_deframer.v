`timescale 1ns/1ps
`default_nettype none

// CRC提交后的640-byte DL Flit解帧器。输入固定为10个512-bit beat；每个beat低字节在先。
// 物理字节位置和SH字段来自UALink 200G DL/PL 2.0 2.3.3/2.3.4及Figure 2-4。
// 输出o_meta[1:0]为TL M[1:0]，其余位固定为0。DL alternative sector尚无独立输出，
// 因此含DLAltSector的frame明确fail-closed，避免静默丢失DL消息。本模块不做CRC、sequence或replay。
module dl_rx_deframer(
 input wire i_clk,input wire i_rstn,input wire i_enable,input wire i_valid,
 input wire [511:0] i_data,input wire [127:0] i_meta,
 input wire i_sop,input wire i_eop,
 input wire i_ready,
 output wire o_ready,output wire o_valid,output wire [511:0] o_data,
 output wire [127:0] o_meta,output wire o_implemented,output wire o_error,
 output wire o_error_event,output wire o_busy,output wire o_quiescent,output wire o_carry_active
);
localparam [2:0] S_CAPTURE=3'd0,S_VALIDATE=3'd1,S_SEGMENT=3'd2,S_SECTOR=3'd3,S_DRAIN=3'd4;
localparam [1:0] P_CARRY=2'd0,P_TL0=2'd1,P_TL1=2'd2;
reg [2:0] state_q;
reg [5119:0] frame_q;
reg [3:0] capture_count_q;
reg [2:0] segment_q;
reg [7:0] sector_q,segment_end_q;
reg [1:0] phase_q;
reg tl0_q,tl1_q;
reg [1:0] msg0_q,msg1_q;
reg build_active_q;
reg [4:0] build_count_q;
reg [479:0] build_data_q;
reg [1:0] build_msg_q;
reg [511:0] output_memory [0:9];
reg [1:0] output_msg_memory [0:9];
reg [3:0] output_count_q,output_index_q;
reg error_q;
reg error_event_q;
integer sim_seg;
reg [8:0] sim_pos,sim_end,sim_half;
reg [8:0] sim_remaining;
reg [7:0] sim_sh;
reg frame_legal;
wire [7:0] current_sh;
wire [7:0] current_byte0,current_byte1,current_byte2,current_byte3;
wire [9:0] current_p0,current_p1,current_p2,current_p3;
wire output_fire;

function automatic [9:0] payload_physical_byte;
 input [7:0] sector; input [1:0] byte_no;
 reg [9:0] s,b,p;
 begin
  s={2'b0,sector};b={8'b0,byte_no};p=10'd0;
  if(sector<=8'd15) p=s*10'd4+b;
  else if(sector<=8'd30) p=10'd68+(s-10'd16)*10'd4+b;
  else if(sector==8'd31) p=(byte_no<2'd3)?10'd64+b:10'd131;
  else if(sector<=8'd46) p=10'd132+(s-10'd32)*10'd4+b;
  else if(sector==8'd47) p=(byte_no<2'd3)?10'd128+b:10'd194;
  else if(sector<=8'd62) p=10'd196+(s-10'd48)*10'd4+b;
  else if(sector==8'd63) p=(byte_no<2'd2)?10'd192+b:10'd256+b;
  else if(sector<=8'd78) p=10'd260+(s-10'd64)*10'd4+b;
  else if(sector==8'd79) p=(byte_no<2'd2)?10'd256+b:10'd319+b;
  else if(sector<=8'd94) p=10'd324+(s-10'd80)*10'd4+b;
  else if(sector==8'd95) p=(byte_no==2'd0)?10'd320:10'd384+b;
  else if(sector<=8'd110) p=10'd388+(s-10'd96)*10'd4+b;
  else if(sector==8'd111) p=(byte_no==2'd0)?10'd384:10'd447+b;
  else if(sector<=8'd126) p=10'd452+(s-10'd112)*10'd4+b;
  else if(sector<=8'd142) p=10'd512+(s-10'd127)*10'd4+b;
  else if(sector<=8'd154) p=10'd580+(s-10'd143)*10'd4+b;
  else if(sector==8'd155) p=10'd628+b;
  else p=(byte_no<2'd3)?10'd576+b:10'd635;
  payload_physical_byte=p;
 end
endfunction
function automatic [7:0] frame_byte;
 input [9:0] byte_index;
 begin frame_byte=frame_q[byte_index*8+:8]; end
endfunction
function automatic [7:0] segment_header;
 input [2:0] seg;
 begin
  case(seg)
   3'd0:segment_header=frame_q[67*8+:8];
   3'd1:segment_header=frame_q[195*8+:8];
   3'd2:segment_header=frame_q[323*8+:8];
   3'd3:segment_header=frame_q[451*8+:8];
   default:segment_header=frame_q[579*8+:8];
  endcase
 end
endfunction
function automatic [7:0] segment_start;
 input [2:0] seg;
 begin case(seg)3'd0:segment_start=0;3'd1:segment_start=32;3'd2:segment_start=64;3'd3:segment_start=96;default:segment_start=127;endcase end
endfunction
function automatic [7:0] segment_end;
 input [2:0] seg;
 begin case(seg)3'd0:segment_end=31;3'd1:segment_end=63;3'd2:segment_end=95;3'd3:segment_end=126;default:segment_end=156;endcase end
endfunction
function automatic [7:0] segment_half;
 input [2:0] seg;
 begin case(seg)3'd0:segment_half=16;3'd1:segment_half=48;3'd2:segment_half=80;3'd3:segment_half=112;default:segment_half=143;endcase end
endfunction

assign current_sh=(segment_q==3'd0)?frame_q[67*8+:8]:
                  (segment_q==3'd1)?frame_q[195*8+:8]:
                  (segment_q==3'd2)?frame_q[323*8+:8]:
                  (segment_q==3'd3)?frame_q[451*8+:8]:frame_q[579*8+:8];
assign current_p0=payload_physical_byte(sector_q,2'd0);
assign current_p1=payload_physical_byte(sector_q,2'd1);
assign current_p2=payload_physical_byte(sector_q,2'd2);
assign current_p3=payload_physical_byte(sector_q,2'd3);
assign current_byte0=frame_q[current_p0*8+:8];
assign current_byte1=frame_q[current_p1*8+:8];
assign current_byte2=frame_q[current_p2*8+:8];
assign current_byte3=frame_q[current_p3*8+:8];
assign o_ready=i_rstn&&i_enable&&(state_q==S_CAPTURE);
assign o_valid=i_rstn&&(state_q==S_DRAIN)&&(output_index_q<output_count_q);
assign o_data=o_valid?output_memory[output_index_q]:512'd0;
assign o_meta=o_valid?{126'd0,output_msg_memory[output_index_q]}:128'd0;
assign output_fire=o_valid&&i_ready;
assign o_implemented=1'b1;
assign o_error=error_q;
assign o_error_event=error_event_q;
assign o_carry_active=build_active_q;
assign o_busy=i_rstn&&((state_q!=S_CAPTURE)||(capture_count_q!=0)||build_active_q);
assign o_quiescent=i_rstn&&(state_q==S_CAPTURE)&&(capture_count_q==0)&&!build_active_q;

// 在产生任何TL输出前检查整帧头部及packing可行性，非法frame不会部分提交。
always @(*)begin
 frame_legal=1'b1;
 sim_remaining=build_active_q?(9'd16-{4'd0,build_count_q}):9'd0;
 if(frame_q[632*8+20]!==1'b1)frame_legal=1'b0;
 if(!((frame_q[632*8+23-:3]===3'd0)||(frame_q[632*8+23-:3]===3'd1)||
      (frame_q[632*8+23-:3]===3'd2)||(frame_q[632*8+23-:3]===3'd3)))frame_legal=1'b0;
 if((frame_q[632*8+23-:3]<2)&&(|frame_q[632*8+19-:3]||(|frame_q[632*8+:8])))frame_legal=1'b0;
 if((frame_q[632*8+23-:3]>=2)&&(|frame_q[632*8+:8]))frame_legal=1'b0;
 for(sim_seg=0;sim_seg<5;sim_seg=sim_seg+1)begin
  sim_sh=segment_header(sim_seg[2:0]);
  sim_pos={1'b0,segment_start(sim_seg[2:0])};sim_end={1'b0,segment_end(sim_seg[2:0])};sim_half={1'b0,segment_half(sim_seg[2:0])};
  if(sim_sh[1]||sim_sh[0]||(!sim_sh[4]&&|sim_sh[3:2])||(!sim_sh[7]&&|sim_sh[6:5]))frame_legal=1'b0;
  if(sim_remaining>0)begin
   if(sim_remaining<=sim_end-sim_pos+1)begin sim_pos=sim_pos+sim_remaining;sim_remaining=0;end
   else begin sim_remaining=sim_remaining-(sim_end-sim_pos+1);sim_pos=sim_end+1;end
  end
  if(sim_sh[4])begin
   if(sim_pos>sim_end)frame_legal=1'b0;
   else if(16<=sim_end-sim_pos+1)begin sim_pos=sim_pos+16;sim_remaining=0;end
   else begin sim_remaining=16-(sim_end-sim_pos+1);sim_pos=sim_end+1;end
  end else if(sim_pos<sim_half)sim_pos=sim_half;
  if(sim_sh[7])begin
   if((sim_remaining!=0)||(sim_pos>sim_end))frame_legal=1'b0;
   else if(16<=sim_end-sim_pos+1)begin sim_pos=sim_pos+16;sim_remaining=0;end
   else begin sim_remaining=16-(sim_end-sim_pos+1);sim_pos=sim_end+1;end
  end
 end
end

always @(posedge i_clk)begin
 if(!i_rstn)begin
  state_q<=S_CAPTURE;frame_q<=5120'd0;capture_count_q<=0;segment_q<=0;sector_q<=0;segment_end_q<=0;phase_q<=0;
  tl0_q<=0;tl1_q<=0;msg0_q<=0;msg1_q<=0;build_active_q<=0;build_count_q<=0;build_data_q<=480'd0;build_msg_q<=0;
  output_count_q<=0;output_index_q<=0;error_q<=0;error_event_q<=0;
 end else begin
  error_event_q<=1'b0;
  case(state_q)
   S_CAPTURE:if(i_valid&&o_ready)begin
    if((capture_count_q==0&&(!i_sop||i_eop||(|i_meta)))||(capture_count_q!=0&&(i_sop||(|i_meta)||((capture_count_q==9)!=i_eop))))begin
     capture_count_q<=0;error_q<=1'b1;error_event_q<=1'b1;
    end else begin
     frame_q[capture_count_q*512+:512]<=i_data;
     if(capture_count_q==9)begin capture_count_q<=0;state_q<=S_VALIDATE;end
     else capture_count_q<=capture_count_q+1'b1;
    end
   end
   S_VALIDATE:begin
    output_count_q<=0;output_index_q<=0;segment_q<=0;
    if(!frame_legal)begin error_q<=1'b1;error_event_q<=1'b1;state_q<=S_CAPTURE;end
    else state_q<=S_SEGMENT;
   end
   S_SEGMENT:begin
    sector_q<=segment_start(segment_q);segment_end_q<=segment_end(segment_q);
    tl0_q<=current_sh[4];tl1_q<=current_sh[7];msg0_q<=current_sh[3:2];msg1_q<=current_sh[6:5];
    if(|current_sh[1:0])begin error_q<=1'b1;error_event_q<=1'b1;end
    if(build_active_q)begin phase_q<=P_CARRY;state_q<=S_SECTOR;end
    else if(current_sh[4])begin build_active_q<=1'b1;build_count_q<=0;build_data_q<=480'd0;build_msg_q<=current_sh[3:2];phase_q<=P_TL0;state_q<=S_SECTOR;end
    else if(current_sh[7])begin sector_q<=segment_half(segment_q);build_active_q<=1'b1;build_count_q<=0;build_data_q<=480'd0;build_msg_q<=current_sh[6:5];phase_q<=P_TL1;state_q<=S_SECTOR;end
    else if(segment_q==4)state_q<=(output_count_q!=0)?S_DRAIN:S_CAPTURE;
    else segment_q<=segment_q+1'b1;
   end
   S_SECTOR:begin
    build_data_q[build_count_q*32+:32]<={current_byte3,current_byte2,current_byte1,current_byte0};
    if(build_count_q==15)begin
     output_memory[output_count_q]<={current_byte3,current_byte2,current_byte1,current_byte0,build_data_q[479:0]};
     output_msg_memory[output_count_q]<=build_msg_q;output_count_q<=output_count_q+1'b1;
     build_active_q<=1'b0;build_count_q<=0;build_data_q<=480'd0;
     if((phase_q==P_CARRY)&&tl0_q&&(sector_q<segment_end_q))begin build_active_q<=1'b1;build_msg_q<=msg0_q;phase_q<=P_TL0;sector_q<=sector_q+1'b1;end
     else if((phase_q!=P_TL1)&&tl1_q&&(sector_q<segment_end_q))begin
      build_active_q<=1'b1;build_msg_q<=msg1_q;phase_q<=P_TL1;
      sector_q<=((phase_q==P_CARRY)&&!tl0_q&&((sector_q+1'b1)<segment_half(segment_q)))?segment_half(segment_q):(sector_q+1'b1);
     end
     else if(segment_q==4)state_q<=S_DRAIN;
     else begin segment_q<=segment_q+1'b1;state_q<=S_SEGMENT;end
    end else begin
     build_count_q<=build_count_q+1'b1;
     if(sector_q==segment_end_q)begin
      if(segment_q==4)state_q<=(output_count_q!=0)?S_DRAIN:S_CAPTURE;
      else begin segment_q<=segment_q+1'b1;state_q<=S_SEGMENT;end
     end
     else sector_q<=sector_q+1'b1;
    end
   end
   S_DRAIN:if(output_fire)begin
    if(output_index_q+1'b1>=output_count_q)begin output_index_q<=0;output_count_q<=0;state_q<=S_CAPTURE;end
    else output_index_q<=output_index_q+1'b1;
   end
   default:begin state_q<=S_CAPTURE;capture_count_q<=0;error_q<=1'b1;error_event_q<=1'b1;end
  endcase
 end
end
endmodule
`default_nettype wire
