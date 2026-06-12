`timescale 1ns/1ps
`default_nettype none
// CMD42 destination service. This owns completer holding, never an originator Tag table.
module endpoint_message_handler #(parameter PORTS=1,parameter TOKEN_WIDTH=16,parameter LINK_RESET_ENABLE=0)(
 input wire i_clk,i_rstn,input wire i_link_reset,input wire [9:0] i_local_id,
 input wire i_request_valid,output wire o_request_ready,input wire [127:0] i_request_header,
 input wire [1:0] i_request_port,input wire [2047:0] i_request_data,input wire [255:0] i_request_be,
 output wire o_backend_valid,input wire i_backend_ready,output wire [TOKEN_WIDTH-1:0] o_backend_token,
 output wire [127:0] o_backend_header,output wire [1:0] o_backend_port,output wire [2047:0] o_backend_data,output wire [255:0] o_backend_be,
 input wire i_result_valid,output wire o_result_ready,input wire [TOKEN_WIDTH-1:0] i_result_token,
 input wire i_result_is_read,input wire [1:0] i_result_num_beats,input wire [3:0] i_result_status,
 input wire [2047:0] i_result_data,input wire [3:0] i_result_poison,input wire i_response_pool,
 output wire o_source_valid,output wire [255:0] o_source_control,input wire i_source_captured,
 output wire [1:0] o_source_port,
 output wire [1:0] o_data_valid,output wire [511:0] o_data,output wire [1:0] o_data_poison,input wire [1:0] i_data_accepted,
 output wire o_busy,output wire o_error,output wire [7:0] o_reason
);
 localparam IDLE=2'd0,ISSUE=2'd1,WAIT_RESULT=2'd2,RESPONSE=2'd3;
 reg [1:0] state_q,beat_q,num_q;reg read_q,pool_q,header_q,fault_q,exhausted_q;
 reg [1:0] data_q;reg [7:0] reason_q;reg [3:0] status_q,poison_q;
 reg [127:0] header_hold;reg [1:0] port_hold;reg [2047:0] data_hold,result_hold;reg [255:0] be_hold;
 reg [TOKEN_WIDTH-1:0] token_q,next_token_q;
 wire link_reset=(LINK_RESET_ENABLE!=0)&&i_link_reset;
 wire active=i_rstn&&!fault_q&&!link_reset;wire vendor=i_request_header[87:84]==4'hf;
 wire nop=i_request_header[87:80]==8'd0;
 wire shape=i_request_header[127:124]==4'd1&&i_request_header[123:118]==6'h2a&&!i_request_header[4]&&
            i_request_header[14:5]==i_local_id&&{30'd0,i_request_port}<PORTS;
 wire nop_ok=i_request_header[1:0]==0&&i_request_data==0;
 wire request_fire=i_request_valid&&o_request_ready;
 wire result_legal=state_q==WAIT_RESULT&&i_result_token==token_q&&
                   (i_result_is_read||(i_result_num_beats==0&&i_result_status!=4'hf));
 wire bad_result=active&&i_result_valid&&!result_legal;
 wire bad_capture=active&&i_source_captured&&!o_source_valid;
 wire bad_data=active&&((i_data_accepted&~o_data_valid)!=0);
 wire header_done=header_q||(o_source_valid&&i_source_captured);
 wire [1:0] data_done=data_q|(i_data_accepted&o_data_valid);
 wire response_done=active&&state_q==RESPONSE&&header_done&&(!read_q||data_done==2'b11);
 wire [63:0] response_field={4'd2,header_hold[117:116],header_hold[113:103],pool_q,2'd0,
        read_q?beat_q:2'd0,status_q,read_q,read_q&&(beat_q==num_q),header_hold[14:5],header_hold[24:15],2'd0,14'd0};
 assign o_request_ready=active&&state_q==IDLE;
 assign o_backend_valid=active&&state_q==ISSUE;
 assign o_backend_token=o_backend_valid?token_q:{TOKEN_WIDTH{1'b0}};
 assign o_backend_header=o_backend_valid?header_hold:128'd0;
 assign o_backend_port=o_backend_valid?port_hold:2'd0;
 assign o_backend_data=o_backend_valid?data_hold:2048'd0;
 assign o_backend_be=o_backend_valid?be_hold:256'd0;
 // Invalid results are diagnostic-only consumption; no completion or slot release.
 assign o_result_ready=active;
 assign o_source_valid=active&&state_q==RESPONSE&&!header_q;
 assign o_source_control=o_source_valid?{192'd0,response_field}:256'd0;
 assign o_source_port=(active&&state_q==RESPONSE)?port_hold:2'd0;
 assign o_data_valid=(active&&state_q==RESPONSE&&read_q)?~data_q:2'd0;
 assign o_data=(active&&state_q==RESPONSE&&read_q)?result_hold[beat_q*512+:512]:512'd0;
 assign o_data_poison=(active&&state_q==RESPONSE&&read_q)?{2{poison_q[beat_q]}}:2'd0;
 assign o_busy=i_rstn&&state_q!=IDLE;
 assign o_error=i_rstn&&(fault_q||bad_result||bad_capture||bad_data);
 assign o_reason=fault_q?reason_q:bad_result?8'd5:bad_capture?8'd6:bad_data?8'd7:8'd0;
 always @(posedge i_clk)begin
  if(!i_rstn)begin
   state_q<=IDLE;beat_q<=0;num_q<=0;read_q<=0;pool_q<=0;header_q<=0;data_q<=0;
   fault_q<=0;reason_q<=0;status_q<=0;poison_q<=0;header_hold<=0;port_hold<=0;
   data_hold<=0;result_hold<=0;be_hold<=0;token_q<=0;next_token_q<=0;exhausted_q<=0;
  end else if(link_reset)begin
   // Link-local取消不复用旧token；其他Port由外层独立handler保持运行。
   state_q<=IDLE;beat_q<=0;num_q<=0;read_q<=0;pool_q<=0;header_q<=0;data_q<=0;
   fault_q<=0;reason_q<=0;status_q<=0;poison_q<=0;header_hold<=0;port_hold<=0;
   data_hold<=0;result_hold<=0;be_hold<=0;token_q<=0;
   if(&next_token_q)exhausted_q<=1;else next_token_q<=next_token_q+1'b1;
  end else if(!fault_q)begin
   if(bad_result)begin fault_q<=1'b1;reason_q<=8'd5;end
   if(request_fire)begin
    if(!shape||(!vendor&&!nop)|| (nop&&!nop_ok)||(vendor&&exhausted_q))begin
     fault_q<=1;reason_q<=!shape?8'd1:(!vendor&&!nop)?8'd2:(nop&&!nop_ok)?8'd3:8'd4;
    end else begin
     header_hold<=i_request_header;port_hold<=i_request_port;data_hold<=i_request_data;be_hold<=i_request_be;
     pool_q<=i_response_pool;beat_q<=0;header_q<=0;data_q<=0;num_q<=0;status_q<=0;read_q<=0;poison_q<=0;
     if(vendor)begin
      state_q<=ISSUE;token_q<=next_token_q;
      // Never wrap a service identity within the current reset epoch.
      if(&next_token_q)exhausted_q<=1;else next_token_q<=next_token_q+1'b1;
     end else state_q<=RESPONSE;
    end
   end
   if(o_backend_valid&&i_backend_ready)state_q<=WAIT_RESULT;
   if(i_result_valid&&o_result_ready&&result_legal)begin
    state_q<=RESPONSE;read_q<=i_result_is_read;num_q<=i_result_num_beats;status_q<=i_result_status;
    result_hold<=i_result_data;poison_q<=i_result_poison;
   end
   if(o_source_valid&&i_source_captured)header_q<=1;
   if(|(i_data_accepted&o_data_valid))data_q<=data_done;
   if(response_done)begin
    header_q<=0;data_q<=0;
    if(!read_q||beat_q==num_q)state_q<=IDLE;else beat_q<=beat_q+1'b1;
   end
  end
 end
 generate if((PORTS!=1&&PORTS!=2&&PORTS!=4)||TOKEN_WIDTH<1||TOKEN_WIDTH>32||((LINK_RESET_ENABLE!=0)&&(LINK_RESET_ENABLE!=1)))begin:invalid_parameters
  endpoint_message_invalid_parameters Invalid_Config();
 end endgenerate
endmodule
`default_nettype wire
