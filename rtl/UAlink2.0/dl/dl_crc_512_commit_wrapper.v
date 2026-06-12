`timescale 1ns/1ps
`default_nettype none

// 10x512-bit DL frame CRC提交适配层。
// 每个512-bit beat按低64-bit在先拆成8个beat，复用dl_crc_math_commit_gate；
// CRC通过后再按原顺序聚合输出。i_received_crc_coeff仅在外部EOP握手拍采样。
// 本模块仍位于CRC polynomial-coefficient边界，不解释CRC0..CRC3的线序映射(A19)。
module dl_crc_512_commit_wrapper (
 input  wire         i_clk,
 input  wire         i_rstn,
 input  wire         i_valid,
 output wire         o_ready,
 input  wire [511:0] i_data,
 input  wire         i_sop,
 input  wire         i_eop,
 input  wire [31:0]  i_received_crc_coeff,
 output wire         o_commit_valid,
 input  wire         i_commit_ready,
 output wire [511:0] o_commit_data,
 output wire         o_commit_sop,
 output wire         o_commit_eop,
 output wire         o_busy,
 output wire         o_quiescent,
 output wire         o_crc_error,
 output wire         o_protocol_error,
 output wire [15:0]  o_crc_error_count,
 output wire [15:0]  o_protocol_error_count,
 output wire [31:0]  o_calculated_crc_coeff
);

localparam [2:0] S_CAPTURE = 3'd0;
localparam [2:0] S_FEED    = 3'd1;
localparam [2:0] S_VERIFY  = 3'd2;
localparam [2:0] S_DRAIN   = 3'd3;

reg [2:0] state_q;
reg [511:0] frame_memory [0:9];
reg [3:0] input_count_q;
reg [6:0] feed_count_q;
reg [31:0] received_crc_coeff_q;
reg [2:0] output_subword_q;
reg [447:0] output_assemble_q;
reg output_assemble_sop_q;
reg output_valid_q;
reg [511:0] output_data_q;
reg output_sop_q;
reg output_eop_q;
reg protocol_error_q;
reg [15:0] protocol_error_count_q;

wire leaf_input_valid;
wire leaf_input_ready;
wire [63:0] leaf_input_data;
wire leaf_input_sop;
wire leaf_input_eop;
wire [31:0] leaf_received_crc_coeff;
wire leaf_commit_valid;
wire leaf_commit_ready;
wire [63:0] leaf_commit_data;
wire leaf_commit_sop;
wire leaf_commit_eop;
wire leaf_busy;
wire leaf_quiescent;
wire leaf_crc_error;
wire leaf_protocol_error;
wire [15:0] leaf_crc_error_count;
wire [15:0] leaf_protocol_error_count;
wire [31:0] leaf_calculated_crc_coeff;
wire [16:0] protocol_count_sum;

assign leaf_input_valid=i_rstn&&(state_q==S_FEED);
assign leaf_input_data=frame_memory[feed_count_q[6:3]][feed_count_q[2:0]*64+:64];
assign leaf_input_sop=(feed_count_q==7'd0);
assign leaf_input_eop=(feed_count_q==7'd79);
assign leaf_received_crc_coeff=leaf_input_eop?received_crc_coeff_q:32'd0;
assign leaf_commit_ready=i_rstn&&(state_q==S_DRAIN)&&!output_valid_q;

assign o_ready=i_rstn&&(state_q==S_CAPTURE);
assign o_commit_valid=i_rstn&&output_valid_q;
assign o_commit_data=o_commit_valid?output_data_q:512'd0;
assign o_commit_sop=o_commit_valid&&output_sop_q;
assign o_commit_eop=o_commit_valid&&output_eop_q;
assign o_busy=(state_q!=S_CAPTURE)||(input_count_q!=4'd0)||output_valid_q||leaf_busy;
assign o_quiescent=i_rstn&&(state_q==S_CAPTURE)&&(input_count_q==4'd0)&&!output_valid_q&&leaf_quiescent;
assign o_crc_error=leaf_crc_error;
assign o_protocol_error=protocol_error_q||leaf_protocol_error;
assign o_crc_error_count=leaf_crc_error_count;
assign protocol_count_sum={1'b0,protocol_error_count_q}+{1'b0,leaf_protocol_error_count};
assign o_protocol_error_count=protocol_count_sum[16]?16'hffff:protocol_count_sum[15:0];
assign o_calculated_crc_coeff=leaf_calculated_crc_coeff;

dl_crc_math_commit_gate u_crc_gate (
 .i_clk(i_clk),.i_rstn(i_rstn),.i_valid(leaf_input_valid),.o_ready(leaf_input_ready),
 .i_data(leaf_input_data),.i_sop(leaf_input_sop),.i_eop(leaf_input_eop),
 .i_received_crc_coeff(leaf_received_crc_coeff),.o_commit_valid(leaf_commit_valid),
 .i_commit_ready(leaf_commit_ready),.o_commit_data(leaf_commit_data),
 .o_commit_sop(leaf_commit_sop),.o_commit_eop(leaf_commit_eop),.o_busy(leaf_busy),
 .o_quiescent(leaf_quiescent),.o_crc_error(leaf_crc_error),
 .o_protocol_error(leaf_protocol_error),.o_crc_error_count(leaf_crc_error_count),
 .o_protocol_error_count(leaf_protocol_error_count),
 .o_calculated_crc_coeff(leaf_calculated_crc_coeff));

always @(posedge i_clk)begin
 if(!i_rstn)begin
  state_q<=S_CAPTURE;
  input_count_q<=4'd0;
  feed_count_q<=7'd0;
  received_crc_coeff_q<=32'd0;
  output_subword_q<=3'd0;
  output_assemble_q<=448'd0;
  output_assemble_sop_q<=1'b0;
  output_valid_q<=1'b0;
  output_data_q<=512'd0;
  output_sop_q<=1'b0;
  output_eop_q<=1'b0;
  protocol_error_q<=1'b0;
  protocol_error_count_q<=16'd0;
 end else begin
  if(o_commit_valid&&i_commit_ready)begin
   output_valid_q<=1'b0;
   if(output_eop_q&&leaf_quiescent)begin
    state_q<=S_CAPTURE;
    input_count_q<=4'd0;
   end
  end

  case(state_q)
   S_CAPTURE:begin
    if(i_valid&&o_ready)begin
     if((input_count_q==4'd0&&(!i_sop||i_eop))||
        (input_count_q!=4'd0&&(i_sop||((input_count_q==4'd9)!=i_eop))))begin
      input_count_q<=4'd0;
      protocol_error_q<=1'b1;
      if(protocol_error_count_q!=16'hffff)
       protocol_error_count_q<=protocol_error_count_q+16'd1;
     end else begin
      frame_memory[input_count_q]<=i_data;
      if(input_count_q==4'd9)begin
       input_count_q<=4'd0;
       feed_count_q<=7'd0;
       received_crc_coeff_q<=i_received_crc_coeff;
       state_q<=S_FEED;
      end else input_count_q<=input_count_q+4'd1;
     end
    end
   end
   S_FEED:begin
    if(leaf_input_valid&&leaf_input_ready)begin
     if(feed_count_q==7'd79)begin
      feed_count_q<=7'd0;
      state_q<=S_VERIFY;
     end else feed_count_q<=feed_count_q+7'd1;
    end
   end
   S_VERIFY:begin
    if(leaf_commit_valid)begin
     output_subword_q<=3'd0;
     output_assemble_q<=448'd0;
     output_assemble_sop_q<=1'b0;
     state_q<=S_DRAIN;
    end else if(leaf_quiescent)begin
     state_q<=S_CAPTURE;
     input_count_q<=4'd0;
    end
   end
   S_DRAIN:begin
    if(leaf_commit_valid&&leaf_commit_ready)begin
     if(output_subword_q==3'd0)output_assemble_sop_q<=leaf_commit_sop;
     if(output_subword_q==3'd7)begin
      output_data_q<={leaf_commit_data,output_assemble_q[447:0]};
      output_sop_q<=output_assemble_sop_q;
      output_eop_q<=leaf_commit_eop;
      output_valid_q<=1'b1;
      output_subword_q<=3'd0;
     end else begin
      output_assemble_q[output_subword_q*64+:64]<=leaf_commit_data;
      output_subword_q<=output_subword_q+3'd1;
     end
    end
   end
   default:begin
    state_q<=S_CAPTURE;
    input_count_q<=4'd0;
    output_valid_q<=1'b0;
    protocol_error_q<=1'b1;
    if(protocol_error_count_q!=16'hffff)
     protocol_error_count_q<=protocol_error_count_q+16'd1;
   end
  endcase
 end
end

endmodule
`default_nettype wire
