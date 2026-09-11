`default_nettype none
// 单端口顺序响应组装：八个真实header槽，Data按header顺序组成一个64B结果。
module endpoint_response_assembler(
 input wire i_clk,i_rstn,
 input wire i_header_valid,output wire o_header_ready,
 input wire [1:0] i_header_port,input wire [10:0] i_header_tag,
 input wire [9:0] i_header_dst,input wire [3:0] i_header_status,
 input wire [1:0] i_header_offset,input wire i_header_last,input wire [1:0] i_header_num_beats,
 input wire i_data_valid,output wire o_data_ready,
 input wire [1:0] i_data_port,input wire [255:0] i_data,
 output wire o_response_valid,input wire i_response_ready,
 output wire [1:0] o_response_port,output wire [10:0] o_response_tag,
 output wire [9:0] o_response_dst,output wire [3:0] o_response_status,
 output wire [1:0] o_response_offset,output wire o_response_last,
 output wire [1:0] o_response_num_beats,output reg [511:0] o_response_data,
 output wire o_response_data_error,output reg o_error
);
reg [31:0] headers[0:7]; // 描述符从入队到第二半Data接纳一直保持所有权。
reg [2:0] r_head,r_tail;
reg [3:0] r_count;
reg r_half,r_output_valid;
reg [255:0] r_first;
reg [31:0] r_output_header;
wire [31:0] head_header=headers[r_head];
wire enqueue=i_header_valid&&o_header_ready;
wire consume=i_data_valid&&o_data_ready;
wire dequeue=consume&&r_half;
wire data_wrong=i_data_valid&&((r_count==0)||(head_header[31:30]!=i_data_port));
assign o_header_ready=i_rstn&&!o_error&&(r_count<4'd8);
assign o_data_ready=i_rstn&&!o_error&&(r_count!=0)&&
 (head_header[31:30]==i_data_port)&&(!r_half||!r_output_valid||i_response_ready);
assign o_response_valid=i_rstn&&!o_error&&r_output_valid;
assign {o_response_port,o_response_tag,o_response_dst,o_response_status,
 o_response_offset,o_response_last,o_response_num_beats}=r_output_header;
assign o_response_data_error=1'b0; // Poison由调用者在发布结果前明确阻断。
always @(posedge i_clk)begin
 if(!i_rstn)begin
  r_head<=0;r_tail<=0;r_count<=0;r_half<=0;r_first<=0;
  r_output_header<=0;o_response_data<=0;r_output_valid<=0;o_error<=0;
 end else if(!o_error)begin
  if(data_wrong)begin o_error<=1'b1;r_output_valid<=1'b0;end
  else begin
   if(o_response_valid&&i_response_ready)r_output_valid<=1'b0;
   if(enqueue)begin
    headers[r_tail]<={i_header_port,i_header_tag,i_header_dst,i_header_status,
                     i_header_offset,i_header_last,i_header_num_beats};
    r_tail<=r_tail+3'd1;
   end
   if(consume)begin
    if(!r_half)begin r_first<=i_data;r_half<=1'b1;end
    else begin
     o_response_data<={i_data, r_first};r_output_header<=head_header;
     r_output_valid<=1'b1;r_half<=1'b0;r_head<=r_head+3'd1;
    end
   end
   case({enqueue,dequeue})
    2'b10:r_count<=r_count+4'd1;
    2'b01:r_count<=r_count-4'd1;
    default:begin end
   endcase
  end
 end
end
endmodule
`default_nettype wire
