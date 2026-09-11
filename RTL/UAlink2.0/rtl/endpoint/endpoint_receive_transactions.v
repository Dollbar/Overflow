`default_nettype none
// 已退休TL记录到单64B Read事务的有限容量适配；不产生新的信用归还。
module endpoint_receive_transactions(
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
 output wire o_response_data_error,output wire o_error
);
localparam EMPTY=3'd0,CHECK=3'd1,LOWER=3'd2,SCAN=3'd3,UPPER=3'd4;
reg [2:0] r_state;
reg [599:0] r_record; // payload/msg/classes/releases在同一次输入握手中保存。
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
endmodule
`default_nettype wire
