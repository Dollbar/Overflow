`timescale 1ns/1ps
`default_nettype none

// 640-byte DL CRC数学与提交屏障。
// 输入必须已经按Figure 2-4排成80个低字节在先的64-bit beat；本模块不决定CRC0..CRC3线上映射。
// i_received_crc_coeff在EOP握手拍有效，按x^i对应bit i给出；待A19关闭后由独立deframer
// 从该末拍的线上四个octet生成。SOP及中间拍上的该输入不会参与比较。
module dl_crc_math_commit_gate (
 input  wire        i_clk,
 input  wire        i_rstn,
 input  wire        i_valid,
 output wire        o_ready,
 input  wire [63:0] i_data,
 input  wire        i_sop,
 input  wire        i_eop,
 input  wire [31:0] i_received_crc_coeff,
 output wire        o_commit_valid,
 input  wire        i_commit_ready,
 output wire [63:0] o_commit_data,
 output wire        o_commit_sop,
 output wire        o_commit_eop,
 output wire        o_busy,
 output wire        o_quiescent,
 output wire        o_crc_error,
 output wire        o_protocol_error,
 output wire [15:0] o_crc_error_count,
 output wire [15:0] o_protocol_error_count,
 output wire [31:0] o_calculated_crc_coeff
);

reg [63:0] frame_memory [0:79];
reg receiving_q;
reg transmitting_q;
reg [6:0] receive_count_q;
reg [6:0] transmit_count_q;
reg [31:0] crc_q;
reg [31:0] calculated_crc_q;
reg crc_error_q;
reg protocol_error_q;
reg [15:0] crc_error_count_q;
reg [15:0] protocol_error_count_q;
reg [31:0] receive_crc_next;
reg receive_feedback_bit;
integer receive_bit_index;

// 每个octet的bit0先进入，64-bit beat的低octet先进入。
// 最后一个beat的高32位是CRC字段，数学计算强制按零处理。
always @* begin
 receive_crc_next=crc_q;
 receive_feedback_bit=1'b0;
 for(receive_bit_index=0;receive_bit_index<64;receive_bit_index=receive_bit_index+1)begin
  receive_feedback_bit=receive_crc_next[31]^((receive_count_q==7'd79 && receive_bit_index>=32)?1'b0:i_data[receive_bit_index]);
  receive_crc_next={receive_crc_next[30:0],1'b0};
  if(receive_feedback_bit)receive_crc_next=receive_crc_next^32'h04c11db7;
 end
end

assign o_ready=i_rstn&&!transmitting_q;
assign o_commit_valid=i_rstn&&transmitting_q;
assign o_commit_data=o_commit_valid?frame_memory[transmit_count_q]:64'd0;
assign o_commit_sop=o_commit_valid&&(transmit_count_q==7'd0);
assign o_commit_eop=o_commit_valid&&(transmit_count_q==7'd79);
assign o_busy=receiving_q||transmitting_q;
assign o_quiescent=i_rstn&&!receiving_q&&!transmitting_q;
assign o_crc_error=crc_error_q;
assign o_protocol_error=protocol_error_q;
assign o_crc_error_count=crc_error_count_q;
assign o_protocol_error_count=protocol_error_count_q;
assign o_calculated_crc_coeff=calculated_crc_q;

always @(posedge i_clk)begin
 if(!i_rstn)begin
  receiving_q<=1'b0;
  transmitting_q<=1'b0;
  receive_count_q<=7'd0;
  transmit_count_q<=7'd0;
  crc_q<=32'hffffffff;
  calculated_crc_q<=32'd0;
  crc_error_q<=1'b0;
  protocol_error_q<=1'b0;
  crc_error_count_q<=16'd0;
  protocol_error_count_q<=16'd0;
 end else begin
  if(o_commit_valid&&i_commit_ready)begin
   if(transmit_count_q==7'd79)begin
    transmitting_q<=1'b0;
    transmit_count_q<=7'd0;
   end else transmit_count_q<=transmit_count_q+7'd1;
  end

  if(i_valid&&o_ready)begin
   if(!receiving_q)begin
    if(!i_sop||i_eop)begin
     protocol_error_q<=1'b1;
     if(protocol_error_count_q!=16'hffff)protocol_error_count_q<=protocol_error_count_q+16'd1;
    end else begin
     frame_memory[0]<=i_data;
     receiving_q<=1'b1;
     receive_count_q<=7'd1;
     crc_q<=receive_crc_next;
    end
   end else if(i_sop||((receive_count_q==7'd79)!=i_eop))begin
    receiving_q<=1'b0;
    receive_count_q<=7'd0;
    crc_q<=32'hffffffff;
    protocol_error_q<=1'b1;
    if(protocol_error_count_q!=16'hffff)protocol_error_count_q<=protocol_error_count_q+16'd1;
   end else begin
    frame_memory[receive_count_q]<=i_data;
    crc_q<=receive_crc_next;
    if(receive_count_q==7'd79)begin
     receiving_q<=1'b0;
     receive_count_q<=7'd0;
     crc_q<=32'hffffffff;
     calculated_crc_q<=receive_crc_next^32'hffffffff;
     if((receive_crc_next^32'hffffffff)==i_received_crc_coeff)begin
      transmitting_q<=1'b1;
      transmit_count_q<=7'd0;
     end else begin
      crc_error_q<=1'b1;
      if(crc_error_count_q!=16'hffff)crc_error_count_q<=crc_error_count_q+16'd1;
     end
    end else receive_count_q<=receive_count_q+7'd1;
   end
  end
 end
end

endmodule
`default_nettype wire
