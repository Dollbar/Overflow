`timescale 1ns/1ps
`default_nettype none
// Two independent one-entry bundled-data mailboxes carry the managed Endpoint
// CSR request and response. Only toggle bits cross through synchronizers. Each
// wide payload is launched from a source register, held until acknowledgement,
// and captured into a destination register after the request toggle settles.
// Physical implementation must constrain each bundled bus relative to the
// corresponding two-stage toggle synchronizer.
//
// Either active-low reset starts a common cancellation epoch. Assertion clears
// both mailboxes asynchronously. Each domain then releases through its own
// two-stage synchronizer, so no pre-reset record or raw reset deassertion can
// reach functional state.
module endpoint_management_cdc_bridge(
 input wire i_mgmt_clk,input wire i_mgmt_rstn,
 input wire i_mgmt_req_valid,output wire o_mgmt_req_ready,
 input wire i_mgmt_req_write,input wire[15:0] i_mgmt_req_addr,input wire[31:0] i_mgmt_req_wdata,
 output wire o_mgmt_rsp_valid,input wire i_mgmt_rsp_ready,
 output wire[31:0] o_mgmt_rsp_rdata,output wire o_mgmt_rsp_error,output wire o_mgmt_rsp_unsupported,
 input wire i_fabric_clk,input wire i_fabric_rstn,
 output wire o_fabric_req_valid,input wire i_fabric_req_ready,
 output wire o_fabric_req_write,output wire[15:0] o_fabric_req_addr,output wire[31:0] o_fabric_req_wdata,
 input wire i_fabric_rsp_valid,output wire o_fabric_rsp_ready,
 input wire[31:0] i_fabric_rsp_rdata,input wire i_fabric_rsp_error,input wire i_fabric_rsp_unsupported
);
 wire mailbox_async_rstn=i_mgmt_rstn&&i_fabric_rstn;
 (* ASYNC_REG = "TRUE" *) reg mgmt_reset_sync1_q,mgmt_reset_sync2_q;
 (* ASYNC_REG = "TRUE" *) reg fabric_reset_sync1_q,fabric_reset_sync2_q;
 wire mgmt_domain_rstn=mgmt_reset_sync2_q;
 wire fabric_domain_rstn=fabric_reset_sync2_q;
 reg request_toggle_q,request_acknowledge_q;
 reg[48:0] request_source_payload_q,request_destination_payload_q;
 reg request_destination_valid_q;
 (* ASYNC_REG = "TRUE" *) reg request_sync1_q,request_sync2_q;
 (* ASYNC_REG = "TRUE" *) reg request_ack_sync1_q,request_ack_sync2_q;
 reg response_toggle_q,response_acknowledge_q;
 reg[33:0] response_source_payload_q,response_destination_payload_q;
 reg response_destination_valid_q;
 (* ASYNC_REG = "TRUE" *) reg response_sync1_q,response_sync2_q;
 (* ASYNC_REG = "TRUE" *) reg response_ack_sync1_q,response_ack_sync2_q;
 wire request_source_idle=request_ack_sync2_q==request_toggle_q;
 wire request_destination_pending=request_sync2_q!=request_acknowledge_q;
 wire response_source_idle=response_ack_sync2_q==response_toggle_q;
 wire response_destination_pending=response_sync2_q!=response_acknowledge_q;
 wire request_source_fire=mgmt_domain_rstn&&i_mgmt_req_valid&&request_source_idle;
 wire request_destination_fire=fabric_domain_rstn&&request_destination_valid_q&&i_fabric_req_ready;
 wire response_source_fire=fabric_domain_rstn&&i_fabric_rsp_valid&&response_source_idle;
 wire response_destination_fire=mgmt_domain_rstn&&response_destination_valid_q&&i_mgmt_rsp_ready;

 assign o_mgmt_req_ready=mgmt_domain_rstn&&request_source_idle;
 assign o_fabric_req_valid=fabric_domain_rstn&&request_destination_valid_q;
 assign o_fabric_req_write=o_fabric_req_valid?request_destination_payload_q[48]:1'b0;
 assign o_fabric_req_addr=o_fabric_req_valid?request_destination_payload_q[47:32]:16'd0;
 assign o_fabric_req_wdata=o_fabric_req_valid?request_destination_payload_q[31:0]:32'd0;
 assign o_fabric_rsp_ready=fabric_domain_rstn&&response_source_idle;
 assign o_mgmt_rsp_valid=mgmt_domain_rstn&&response_destination_valid_q;
 assign o_mgmt_rsp_unsupported=o_mgmt_rsp_valid?response_destination_payload_q[33]:1'b0;
 assign o_mgmt_rsp_error=o_mgmt_rsp_valid?response_destination_payload_q[32]:1'b0;
 assign o_mgmt_rsp_rdata=o_mgmt_rsp_valid?response_destination_payload_q[31:0]:32'd0;

 always @(posedge i_mgmt_clk or negedge mailbox_async_rstn)begin
  if(!mailbox_async_rstn)begin mgmt_reset_sync1_q<=1'b0;mgmt_reset_sync2_q<=1'b0;end
  else begin mgmt_reset_sync1_q<=1'b1;mgmt_reset_sync2_q<=mgmt_reset_sync1_q;end
 end
 always @(posedge i_fabric_clk or negedge mailbox_async_rstn)begin
  if(!mailbox_async_rstn)begin fabric_reset_sync1_q<=1'b0;fabric_reset_sync2_q<=1'b0;end
  else begin fabric_reset_sync1_q<=1'b1;fabric_reset_sync2_q<=fabric_reset_sync1_q;end
 end

 always @(posedge i_mgmt_clk or negedge mailbox_async_rstn)begin
  if(!mailbox_async_rstn)begin
   request_toggle_q<=1'b0;request_source_payload_q<=49'd0;
   request_ack_sync1_q<=1'b0;request_ack_sync2_q<=1'b0;
   response_sync1_q<=1'b0;response_sync2_q<=1'b0;
   response_acknowledge_q<=1'b0;response_destination_valid_q<=1'b0;
   response_destination_payload_q<=34'd0;
  end else if(!mgmt_domain_rstn)begin
   request_toggle_q<=1'b0;request_source_payload_q<=49'd0;
   request_ack_sync1_q<=1'b0;request_ack_sync2_q<=1'b0;
   response_sync1_q<=1'b0;response_sync2_q<=1'b0;
   response_acknowledge_q<=1'b0;response_destination_valid_q<=1'b0;
   response_destination_payload_q<=34'd0;
  end else begin
   request_ack_sync1_q<=request_acknowledge_q;
   request_ack_sync2_q<=request_ack_sync1_q;
   response_sync1_q<=response_toggle_q;
   response_sync2_q<=response_sync1_q;
   if(request_source_fire)begin
    request_source_payload_q<={i_mgmt_req_write,i_mgmt_req_addr,i_mgmt_req_wdata};
    request_toggle_q<=~request_toggle_q;
   end
   if(!response_destination_valid_q&&response_destination_pending)begin
    response_destination_valid_q<=1'b1;
    response_destination_payload_q<=response_source_payload_q;
   end
   if(response_destination_fire)begin
    response_destination_valid_q<=1'b0;
    response_acknowledge_q<=response_sync2_q;
   end
  end
 end

 always @(posedge i_fabric_clk or negedge mailbox_async_rstn)begin
  if(!mailbox_async_rstn)begin
   request_sync1_q<=1'b0;request_sync2_q<=1'b0;
   request_acknowledge_q<=1'b0;request_destination_valid_q<=1'b0;
   request_destination_payload_q<=49'd0;
   response_toggle_q<=1'b0;response_source_payload_q<=34'd0;
   response_ack_sync1_q<=1'b0;response_ack_sync2_q<=1'b0;
  end else if(!fabric_domain_rstn)begin
   request_sync1_q<=1'b0;request_sync2_q<=1'b0;
   request_acknowledge_q<=1'b0;request_destination_valid_q<=1'b0;
   request_destination_payload_q<=49'd0;
   response_toggle_q<=1'b0;response_source_payload_q<=34'd0;
   response_ack_sync1_q<=1'b0;response_ack_sync2_q<=1'b0;
  end else begin
   request_sync1_q<=request_toggle_q;
   request_sync2_q<=request_sync1_q;
   response_ack_sync1_q<=response_acknowledge_q;
   response_ack_sync2_q<=response_ack_sync1_q;
   if(!request_destination_valid_q&&request_destination_pending)begin
    request_destination_valid_q<=1'b1;
    request_destination_payload_q<=request_source_payload_q;
   end
   if(request_destination_fire)begin
    request_destination_valid_q<=1'b0;
    request_acknowledge_q<=request_sync2_q;
   end
   if(response_source_fire)begin
    response_source_payload_q<={i_fabric_rsp_unsupported,i_fabric_rsp_error,i_fabric_rsp_rdata};
    response_toggle_q<=~response_toggle_q;
   end
  end
 end
endmodule
`default_nettype wire
