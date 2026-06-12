`timescale 1ns/1ps
`default_nettype none
// Indexed状态backend：从真实Fabric packed计数中只选择一个资源、账户或RAS项返回CSR。
module switch_fabric_status_query_backend #(
 parameter integer C_RESOURCES=4096,
 parameter integer C_ACCOUNTS=262144,
 parameter integer C_RAS_COUNTERS=32,
 parameter integer C_RESOURCE_INDEX_WIDTH=12,
 parameter integer C_ACCOUNT_INDEX_WIDTH=18,
 parameter integer C_RAS_INDEX_WIDTH=5,
 parameter integer C_CREDIT_COUNT_WIDTH=3,
 parameter integer C_QUEUE_COUNT_WIDTH=8,
 parameter integer C_RESPONSE_LATENCY=1
)(
 input wire i_clk,
 input wire i_rstn,
 input wire i_enable,
 input wire i_query_valid,
 output wire o_query_ready,
 input wire [2:0] i_query_kind,
 input wire [31:0] i_query_index,
 output wire [31:0] o_query_data,
 input wire [C_RESOURCES*C_CREDIT_COUNT_WIDTH-1:0] i_resource_free,
 input wire [C_RESOURCES*C_QUEUE_COUNT_WIDTH-1:0] i_queue_occupancy,
 input wire [C_ACCOUNTS*C_CREDIT_COUNT_WIDTH-1:0] i_account_issued,
 input wire [C_ACCOUNTS*C_CREDIT_COUNT_WIDTH-1:0] i_account_occupied,
 input wire [C_RAS_COUNTERS*32-1:0] i_ras_counters
);
 localparam [2:0] Q_RESOURCE_FREE=3'd0,Q_QUEUE_OCCUPANCY=3'd1,Q_ACCOUNT_ISSUED=3'd2,Q_ACCOUNT_OCCUPIED=3'd3,Q_RAS=3'd4;
 localparam [7:0] RESPONSE_DELAY=C_RESPONSE_LATENCY[7:0];
 localparam CONFIG_LEGAL=(C_RESOURCES>=1)&&(C_ACCOUNTS>=1)&&(C_RAS_COUNTERS>=1)&&
  (C_RESOURCES<=(1<<C_RESOURCE_INDEX_WIDTH))&&(C_ACCOUNTS<=(1<<C_ACCOUNT_INDEX_WIDTH))&&
  (C_RAS_COUNTERS<=(1<<C_RAS_INDEX_WIDTH))&&(C_RESPONSE_LATENCY>=0)&&(C_RESPONSE_LATENCY<=255);
 reg pending_q;
 reg [7:0] delay_q;
 reg [31:0] data_q;
 reg [31:0] selected_data;
 integer selected_index;
 assign o_query_ready=pending_q&&(delay_q==0)&&CONFIG_LEGAL;
 assign o_query_data=data_q;

 always @(*) begin
  selected_data=32'd0;
  selected_index=i_query_index;
  case(i_query_kind)
   Q_RESOURCE_FREE:if(selected_index<C_RESOURCES)
    selected_data[0+:C_CREDIT_COUNT_WIDTH]=i_resource_free[selected_index*C_CREDIT_COUNT_WIDTH+:C_CREDIT_COUNT_WIDTH];
   Q_QUEUE_OCCUPANCY:if(selected_index<C_RESOURCES)
    selected_data[0+:C_QUEUE_COUNT_WIDTH]=i_queue_occupancy[selected_index*C_QUEUE_COUNT_WIDTH+:C_QUEUE_COUNT_WIDTH];
   Q_ACCOUNT_ISSUED:if(selected_index<C_ACCOUNTS)
    selected_data[0+:C_CREDIT_COUNT_WIDTH]=i_account_issued[selected_index*C_CREDIT_COUNT_WIDTH+:C_CREDIT_COUNT_WIDTH];
   Q_ACCOUNT_OCCUPIED:if(selected_index<C_ACCOUNTS)
    selected_data[0+:C_CREDIT_COUNT_WIDTH]=i_account_occupied[selected_index*C_CREDIT_COUNT_WIDTH+:C_CREDIT_COUNT_WIDTH];
   Q_RAS:if(selected_index<C_RAS_COUNTERS)selected_data=i_ras_counters[selected_index*32+:32];
   default:selected_data=32'd0;
  endcase
 end

 always @(posedge i_clk) begin
  if(!i_rstn||!CONFIG_LEGAL)begin
   pending_q<=1'b0;
   delay_q<=8'd0;
   data_q<=32'd0;
  end else begin
   if(pending_q)begin
    if(delay_q!=0)delay_q<=delay_q-1'b1;
    else if(i_query_valid)pending_q<=1'b0;
   end else if(i_enable&&i_query_valid)begin
    pending_q<=1'b1;
    delay_q<=RESPONSE_DELAY;
    data_q<=selected_data;
   end
  end
 end
endmodule
`default_nettype wire
