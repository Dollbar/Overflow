`timescale 1ns/1ps
module tb;
parameter PORTS=1;
parameter TL=0;
localparam [1:0] ORIGINATOR_SCOPE=TL?3:1,COMPLETER_SCOPE=TL?3:2;
parameter CW=4;
parameter CAP=4;
localparam C_NUM_PORTS=PORTS, C_CREDIT_WIDTH=CW;
reg clk=0; always #5 clk=~clk;
reg rstn=0,peer_ready=0,consumer_enable=0;
wire originator_drop,completer_drop; reg [1:0] fault_ack=0; reg [3:0] credit_fault=0; reg allow_fault=0; reg data_parity_flip=0; reg credit_override=0; reg fault_mode=0;reg check_req_block=0; integer source_handshakes=0;always @(posedge clk)if(rstn&&o_req_candidate_accepted)source_handshakes<=source_handshakes+1;
integer control_seen=0,data_seen=0; reg [PORTS*5*CW-1:0] saved_bank;
wire oq,oa,cq,ca,otx,orx,ctx,crx,ob,cb;


wire  i_clk;
wire  i_rstn;
wire  i_originator_credit_connected;
wire  i_originator_beats_connected;
reg  i_req_candidate_valid=0;
reg [1:0] i_req_candidate_port=0;
reg [1:0] i_req_candidate_vc=0;
reg  i_req_candidate_pool=0;
reg  i_req_candidate_has_data=0;
reg [1:0] i_req_candidate_num_beats=0;
reg [3:0] i_req_candidate_data_pools=0;
reg [183:0] i_req_candidate_request=0;
reg [2047:0] i_req_candidate_data=0;
reg [255:0] i_req_candidate_byte_enable=0;
reg [3:0] i_req_candidate_error=0;
wire [3:0] i_req_credit_valid;
wire [3:0] i_req_credit_pool;
wire [7:0] i_req_credit_vc;
wire [7:0] i_req_credit_num;
wire [3:0] i_req_credit_init_done;
wire [3:0] i_data_credit_valid;
wire [3:0] i_data_credit_pool;
wire [7:0] i_data_credit_vc;
wire [7:0] i_data_credit_num;
wire [3:0] i_data_credit_init_done;
wire  o_req_candidate_accepted;
wire  o_req_valid;
wire [1:0] o_req_port;
wire [1:0] o_req_vc;
wire  o_req_pool;
wire [183:0] o_req_payload;
wire  o_data_valid;
wire [1:0] o_data_port;
wire [1:0] o_data_vc;
wire  o_data_pool;
wire [1:0] o_data_offset;
wire  o_data_last;
wire [511:0] o_data_payload;
wire [63:0] o_data_byte_enable;
wire  o_data_error;
wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_req_balances;
wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_data_balances;
wire [3:0] o_req_init;
wire [3:0] o_data_init;
wire  o_req_credit_error;
wire  o_data_credit_error;
wire  o_req_data_credit_error_sticky;
wire [3:0] o_req_busy;
wire  o_req_tdm_known;
wire [1:0] o_req_tdm_port;
wire [1:0] o_req_asi;
wire [63:0] o_req_auth_tag;
wire [9:0] o_req_src;
wire [9:0] o_req_dst;
wire [10:0] o_req_tag;
wire [1:0] o_req_num_beats;
wire [56:0] o_req_address;
wire [5:0] o_req_command;
wire [5:0] o_req_length;
wire [7:0] o_req_attr;
wire [7:0] o_req_metadata;
wire  o_req_valid_parity;
wire  o_req_auth_tag_parity;
wire  o_req_address_parity;
wire  o_req_control_parity;
wire  o_data_valid_parity;
wire  o_data_byte_enable_parity;
wire  o_data_fields_parity;
wire [7:0] o_data_parity;
wire  i_completer_credit_connected;
wire  i_completer_beats_connected;
reg  i_rd_candidate_valid=0;
reg [1:0] i_rd_candidate_port=0;
reg [1:0] i_rd_candidate_vc=0;
reg [3:0] i_rd_candidate_pools=0;
reg [2475:0] i_rd_candidate_payload=0;
wire [3:0] i_rd_credit_valid;
wire [3:0] i_rd_credit_pool;
wire [7:0] i_rd_credit_vc;
wire [7:0] i_rd_credit_num;
wire [3:0] i_rd_credit_init_done;
wire  o_rd_candidate_accepted;
wire  o_rd_candidate_error;
wire  o_rd_valid;
wire [1:0] o_rd_port;
wire [63:0] o_rd_auth_tag;
wire [9:0] o_rd_src;
wire [9:0] o_rd_dst;
wire [10:0] o_rd_tag;
wire [1:0] o_rd_num_beats;
wire [511:0] o_rd_data;
wire [3:0] o_rd_status;
wire [1:0] o_rd_offset;
wire  o_rd_last;
wire  o_rd_data_error;
wire [1:0] o_rd_type_info;
wire [1:0] o_rd_vc;
wire  o_rd_pool;
wire  o_rd_valid_parity;
wire  o_rd_auth_tag_parity;
wire [7:0] o_rd_data_parity;
wire  o_rd_control_parity;
wire [618:0] o_rd_payload;
wire [3:0] o_rd_busy;
wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_rd_balances;
wire [3:0] o_rd_init_confirmed;
wire  o_rd_credit_error;
wire  o_rd_credit_error_sticky;
wire  o_rd_tdm_known;
wire [1:0] o_rd_tdm_port;
reg  i_wr_candidate_valid=0;
reg [1:0] i_wr_candidate_port=0;
reg [1:0] i_wr_candidate_vc=0;
reg  i_wr_candidate_pool=0;
reg [100:0] i_wr_candidate_payload=0;
wire [3:0] i_wr_credit_valid;
wire [3:0] i_wr_credit_pool;
wire [7:0] i_wr_credit_vc;
wire [7:0] i_wr_credit_num;
wire [3:0] i_wr_credit_init_done;
wire  o_wr_candidate_accepted;
wire  o_wr_valid;
wire [1:0] o_wr_type_info;
wire [10:0] o_wr_tag;
wire [3:0] o_wr_status;
wire [9:0] o_wr_src;
wire [9:0] o_wr_dst;
wire [1:0] o_wr_port;
wire [1:0] o_wr_vc;
wire  o_wr_pool;
wire [63:0] o_wr_auth_tag;
wire  o_wr_valid_parity;
wire  o_wr_auth_tag_parity;
wire  o_wr_control_parity;
wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_wr_balances;
wire [3:0] o_wr_init_confirmed;
wire  o_wr_credit_error;
wire  o_wr_credit_error_sticky;
wire  o_wr_tdm_known;
wire [1:0] o_wr_tdm_port;
wire  i_req_credit_valid_parity;
wire  i_req_credit_parity;
wire  i_data_credit_valid_parity;
wire  i_data_credit_parity;
wire  i_rd_credit_valid_parity;
wire  i_rd_credit_parity;
wire  i_wr_credit_valid_parity;
wire  i_wr_credit_parity;
wire [3:0] o_credit_valid_parity_error;
wire [3:0] o_credit_control_parity_error;
wire [3:0] o_credit_parity_error;
wire [3:0] o_credit_integrity_ok;
assign i_clk=clk;assign i_rstn=rstn;
assign i_originator_credit_connected=orx;assign i_originator_beats_connected=ob;
assign i_completer_credit_connected=crx;assign i_completer_beats_connected=cb;

wire [1:0] path_req_consumer_port;
wire  path_req_head_taken;
wire [183:0] path_req_head_payload;
wire [12:0] path_req_head_parity;
wire [1:0] path_req_head_vc;
wire  path_req_head_pool;
wire [2:0] path_req_head_account;
wire  path_req_head_valid;
wire  path_req_consume_valid;
wire [3:0] path_req_credit_valid;
wire [3:0] path_req_credit_pool;
wire [7:0] path_req_credit_vc;
wire [7:0] path_req_credit_num;
wire [3:0] path_req_credit_init_done;
wire  path_req_credit_valid_parity;
wire  path_req_credit_parity;
wire [1:0] path_data_consumer_port;
wire  path_data_head_taken;
wire [579:0] path_data_head_payload;
wire [12:0] path_data_head_parity;
wire [1:0] path_data_head_vc;
wire  path_data_head_pool;
wire [2:0] path_data_head_account;
wire  path_data_head_valid;
wire  path_data_consume_valid;
wire [3:0] path_data_credit_valid;
wire [3:0] path_data_credit_pool;
wire [7:0] path_data_credit_vc;
wire [7:0] path_data_credit_num;
wire [3:0] path_data_credit_init_done;
wire  path_data_credit_valid_parity;
wire  path_data_credit_parity;
wire [618:0] path_rd_head_payload;
wire [12:0] path_rd_head_parity;
wire [1:0] path_rd_head_vc;
wire  path_rd_head_pool;
wire [2:0] path_rd_head_account;
wire  path_rd_head_valid;
wire  path_rd_consume_valid;
wire [3:0] path_rd_credit_valid;
wire [3:0] path_rd_credit_pool;
wire [7:0] path_rd_credit_vc;
wire [7:0] path_rd_credit_num;
wire [3:0] path_rd_credit_init_done;
wire  path_rd_credit_valid_parity;
wire  path_rd_credit_parity;
wire [100:0] path_wr_head_payload;
wire [12:0] path_wr_head_parity;
wire [1:0] path_wr_head_vc;
wire  path_wr_head_pool;
wire [2:0] path_wr_head_account;
wire  path_wr_head_valid;
wire  path_wr_consume_valid;
wire [3:0] path_wr_credit_valid;
wire [3:0] path_wr_credit_pool;
wire [7:0] path_wr_credit_vc;
wire [7:0] path_wr_credit_num;
wire [3:0] path_wr_credit_init_done;
wire  path_wr_credit_valid_parity;
wire  path_wr_credit_parity;
wire [3:0] path_receive_accepted;
wire [51:0] path_ingress_errors;
wire [51:0] path_head_errors;
wire [3:0] path_control_error;
wire [3:0] path_data_error;
wire [3:0] path_auth_error;
wire [3:0] path_auth_profile_error;
wire [3:0] path_metadata_error;
wire [3:0] path_fault_stop_request;
wire [11:0] path_storage_diagnostic;
wire [4*C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] path_counts;
wire [16*3-1:0] path_pending_count;
wire [4*C_NUM_PORTS*(CW+3)-1:0] path_order_counts;
wire [4*C_NUM_PORTS-1:0] path_order_error;
wire [4*C_NUM_PORTS-1:0] path_order_error_sticky;
wire [3:0] path_tdm_error;
wire [3:0] path_tdm_error_sticky;
wire [2:0] path_tdm_phase_known;
wire [5:0] path_tdm_expected_port;
wire  path_request_valid;
wire [1:0] path_request_port;
wire [1:0] path_request_vc;
wire  path_request_pool;
wire [183:0] path_request_payload;
wire [2047:0] path_request_data;
wire [255:0] path_request_be;
wire [3:0] path_request_poison;
wire [3:0] path_request_data_pools;
wire  path_bridge_busy;
wire  path_bridge_error;
reg [1:0] select_port=0;
reg [3:0] native_flip=0;
wire [3:0] sent={o_wr_valid,o_rd_valid,o_data_valid,o_req_valid};
wire [1:0] sent_port[0:3],sent_vc[0:3],head_port[0:3];
wire sent_pool[0:3];
wire [618:0] sent_payload[0:3],head_payload[0:3];
wire [12:0] sent_parity[0:3];
wire [3:0] head_taken;
wire request_ready=consumer_enable && (cycles%47>=31);
wire response_ready=consumer_enable && (cycles%7!=0);
assign sent_port[0]=o_req_port; assign sent_vc[0]=o_req_vc; assign sent_pool[0]=o_req_pool;
assign sent_payload[0]={435'd0,{o_req_asi,o_req_auth_tag,o_req_src,o_req_dst,o_req_tag,o_req_num_beats,o_req_address,o_req_command,o_req_length,o_req_attr,o_req_metadata}};
assign sent_parity[0]={9'd0,o_req_auth_tag_parity,o_req_address_parity,o_req_control_parity,o_req_valid_parity} ^ {11'd0,native_flip[0],1'b0};
assign head_taken[0]=path_req_head_taken; assign head_port[0]=path_req_consumer_port;
assign head_payload[0]={435'd0,path_req_head_payload};
assign i_req_credit_valid=path_req_credit_valid;
assign i_req_credit_pool=path_req_credit_pool;
assign i_req_credit_vc=path_req_credit_vc;
assign i_req_credit_num=path_req_credit_num;
assign i_req_credit_init_done=path_req_credit_init_done;
assign i_req_credit_valid_parity=path_req_credit_valid_parity;
assign i_req_credit_parity=path_req_credit_parity;
assign sent_port[1]=o_data_port; assign sent_vc[1]=o_data_vc; assign sent_pool[1]=o_data_pool;
assign sent_payload[1]={39'd0,{o_data_payload,o_data_byte_enable,o_data_offset,o_data_last,o_data_error}};
assign sent_parity[1]={o_data_byte_enable_parity,o_data_parity,2'd0,o_data_fields_parity,o_data_valid_parity} ^ {11'd0,native_flip[1],1'b0} ^ {8'd0,data_parity_flip,4'd0};
assign head_taken[1]=path_data_head_taken; assign head_port[1]=path_data_consumer_port;
assign head_payload[1]={39'd0,path_data_head_payload};
assign i_data_credit_valid=path_data_credit_valid;
assign i_data_credit_pool=path_data_credit_pool;
assign i_data_credit_vc=path_data_credit_vc;
assign i_data_credit_num=path_data_credit_num;
assign i_data_credit_init_done=path_data_credit_init_done;
assign i_data_credit_valid_parity=path_data_credit_valid_parity;
assign i_data_credit_parity=path_data_credit_parity;
assign sent_port[2]=o_rd_port; assign sent_vc[2]=o_rd_vc; assign sent_pool[2]=o_rd_pool;
assign sent_payload[2]={o_rd_auth_tag,o_rd_src,o_rd_dst,o_rd_tag,o_rd_num_beats,o_rd_data,o_rd_status,o_rd_offset,o_rd_last,o_rd_data_error,o_rd_type_info};
assign sent_parity[2]={1'b0,o_rd_data_parity,o_rd_auth_tag_parity,1'b0,o_rd_control_parity,o_rd_valid_parity} ^ {11'd0,native_flip[2],1'b0};
assign head_taken[2]=top_response_retired[0]; assign head_port[2]=top_response_port[0 +: 2];
assign head_payload[2]=path_rd_head_payload;
assign i_rd_credit_valid=path_rd_credit_valid;
assign i_rd_credit_pool=path_rd_credit_pool;
assign i_rd_credit_vc=path_rd_credit_vc;
assign i_rd_credit_num=path_rd_credit_num;
assign i_rd_credit_init_done=path_rd_credit_init_done;
assign i_rd_credit_valid_parity=path_rd_credit_valid_parity;
assign i_rd_credit_parity=path_rd_credit_parity;
assign sent_port[3]=o_wr_port; assign sent_vc[3]=o_wr_vc; assign sent_pool[3]=o_wr_pool;
assign sent_payload[3]={518'd0,{o_wr_auth_tag,o_wr_type_info,o_wr_tag,o_wr_status,o_wr_src,o_wr_dst}};
assign sent_parity[3]={9'd0,o_wr_auth_tag_parity,1'b0,o_wr_control_parity,o_wr_valid_parity} ^ {11'd0,native_flip[3],1'b0};
assign head_taken[3]=top_response_retired[1]; assign head_port[3]=top_response_port[2 +: 2];
assign head_payload[3]={518'd0,path_wr_head_payload};
assign i_wr_credit_valid=path_wr_credit_valid;
assign i_wr_credit_pool=path_wr_credit_pool;
assign i_wr_credit_vc=path_wr_credit_vc;
assign i_wr_credit_num=path_wr_credit_num;
assign i_wr_credit_init_done=path_wr_credit_init_done;
assign i_wr_credit_valid_parity=path_wr_credit_valid_parity;
assign i_wr_credit_parity=path_wr_credit_parity;

wire [1:0] top_drop_roles;
wire [2*C_NUM_PORTS-1:0] top_drop_ports;
wire [1:0] top_notify_roles;
wire [1:0] top_ack_accepted;
wire [1:0] top_reset_required;
wire [31:0] top_reason_sticky;
wire [1:0] top_init_incomplete;
wire [3:0] top_data_error_observed;
wire [3:0] top_raw_credit_valid_error;
wire [3:0] top_raw_credit_control_error;
wire [3:0] top_raw_credit_error;
wire  top_backend_implemented;
assign originator_drop=top_drop_roles[0]; assign completer_drop=top_drop_roles[1];
// Test-only synchronous cable cuts the external loopback feedback; it is not part of the IP.
reg [3:0] link_valid=0;
reg [1:0] link_port[0:3],link_vc[0:3];reg link_pool[0:3];
reg [618:0] link_payload[0:3];reg [12:0] link_parity[0:3];
always @(posedge clk)begin
 if(!rstn)begin
  link_valid<=0;
  for(integer q=0;q<4;q=q+1)begin link_port[q]<=0;link_vc[q]<=0;link_pool[q]<=0;link_payload[q]<=0;link_parity[q]<=0;end
 end else begin
  link_valid<=sent;
  for(integer q=0;q<4;q=q+1)begin link_port[q]<=sent_port[q];link_vc[q]<=sent_vc[q];link_pool[q]<=sent_pool[q];link_payload[q]<=sent_payload[q];link_parity[q]<=sent_parity[q];end
 end
end
wire [1:0] top_response_valid;
wire [3:0] top_response_port;
wire [3:0] top_response_vc;
wire [1:0] top_response_pool;
wire [5:0] top_response_account;
wire [618:0] top_response_read_payload;
wire [100:0] top_response_write_payload;
wire [1:0] top_response_retired;
wire [1:0] top_response_metadata_error;
wire  top_response_fault_stop_request;
upli_endpoint_ip_top #(.C_IS_TL(TL),.C_NUM_PORTS(PORTS),.C_CREDIT_WIDTH(CW),.C_DEFAULT_CAPACITY(CAP)) top(
.i_clk(clk),
// Memory adapter defaults off; legacy owner remains unchanged.
.o_memory_issue_ready(),
.o_memory_command_valid(),
.i_memory_command_ready(1'd0),
.o_memory_command_token(),
.o_memory_command_station(),
.o_memory_command_port(),
.o_memory_command_vc(),
.o_memory_command_pool(),
.o_memory_command_payload(),
.o_memory_command_data(),
.o_memory_command_be(),
.o_memory_command_poison(),
.o_memory_command_data_pools(),
.i_memory_result_valid(1'd0),
.o_memory_result_ready(),
.i_memory_result_token(10'd0),
.i_memory_result_status(4'd0),
.i_memory_result_data(2048'd0),
.i_memory_result_poison(4'd0),
.o_memory_completion_valid(),
.i_memory_completion_ready(1'd0),
.o_memory_completion_token(),
.o_memory_completion_status(),
.o_memory_completion_data(),
.o_memory_completion_poison(),
.i_memory_final_valid(1'd0),
.o_memory_final_ready(),
.i_memory_final_token(10'd0),
.o_memory_release_valid(),
.o_memory_release_token(),
.o_memory_busy(),
.o_memory_error(),
.o_memory_error_sticky(),
.i_rstn(rstn),
.i_originator_ready(1'b1),
.i_originator_peer_req(cq),
.i_originator_peer_ack(ca),
.o_originator_req(oq),
.o_originator_ack(oa),
.o_originator_tx_connected(otx),
.o_originator_rx_connected(orx),
.o_originator_beats_connected(ob),
.i_completer_ready(peer_ready),
.i_completer_peer_req(oq),
.i_completer_peer_ack(oa),
.o_completer_req(cq),
.o_completer_ack(ca),
.o_completer_tx_connected(ctx),
.o_completer_rx_connected(crx),
.o_completer_beats_connected(cb),
.i_fault_ack(fault_ack),
.i_response_select_valid(2'b11),
.i_response_select_port({select_port,select_port}),
.i_response_retire_ready({response_ready,response_ready}),
.o_response_valid(top_response_valid),
.o_response_port(top_response_port),
.o_response_vc(top_response_vc),
.o_response_pool(top_response_pool),
.o_response_account(top_response_account),
.o_response_read_payload(top_response_read_payload),
.o_response_write_payload(top_response_write_payload),
.o_response_retired(top_response_retired),
.o_response_metadata_error(top_response_metadata_error),
.o_response_fault_stop_request(top_response_fault_stop_request),
.i_context_station(8'd0),
.i_backend_issue_ready(1'b0),
.i_backend_release_valid(1'b0),
.i_backend_release_token(10'd0),
.o_backend_issue_valid(),.o_backend_issue_token(),.o_backend_release_ready(),
.o_context_request_ready(),.o_context_request_token(),.o_context_error(),.o_context_count(),
.o_backend_issue_station(),.o_backend_issue_port(),.o_backend_issue_vc(),.o_backend_issue_pool(),
.o_backend_issue_payload(),.o_backend_issue_data(),.o_backend_issue_be(),.o_backend_issue_poison(),.o_backend_issue_data_pools(),
.o_drop_roles(top_drop_roles),
.o_drop_ports(top_drop_ports),
.o_notify_roles(top_notify_roles),
.o_ack_accepted(top_ack_accepted),
.o_reset_required(top_reset_required),
.o_reason_sticky(top_reason_sticky),
.o_init_incomplete(top_init_incomplete),
.o_data_error_observed(top_data_error_observed),
.o_raw_credit_valid_error(top_raw_credit_valid_error),
.o_raw_credit_control_error(top_raw_credit_control_error),
.o_raw_credit_error(top_raw_credit_error),
.o_backend_implemented(top_backend_implemented),
.i_tx_req_candidate_valid(i_req_candidate_valid),
.i_tx_req_candidate_port(i_req_candidate_port),
.i_tx_req_candidate_vc(i_req_candidate_vc),
.i_tx_req_candidate_pool(i_req_candidate_pool),
.i_tx_req_candidate_has_data(i_req_candidate_has_data),
.i_tx_req_candidate_num_beats(i_req_candidate_num_beats),
.i_tx_req_candidate_data_pools(i_req_candidate_data_pools),
.i_tx_req_candidate_request(i_req_candidate_request),
.i_tx_req_candidate_data(i_req_candidate_data),
.i_tx_req_candidate_byte_enable(i_req_candidate_byte_enable),
.i_tx_req_candidate_error(i_req_candidate_error),
.i_tx_req_credit_valid(credit_override ? 4'b0001 : i_req_credit_valid),
.i_tx_req_credit_pool(credit_override ? 4'b0001 : i_req_credit_pool),
.i_tx_req_credit_vc(credit_override ? 8'd3 : i_req_credit_vc),
.i_tx_req_credit_num(credit_override ? 8'd0 : i_req_credit_num),
.i_tx_req_credit_init_done(i_req_credit_init_done),
.i_tx_data_credit_valid(i_data_credit_valid),
.i_tx_data_credit_pool(i_data_credit_pool),
.i_tx_data_credit_vc(i_data_credit_vc),
.i_tx_data_credit_num(i_data_credit_num),
.i_tx_data_credit_init_done(i_data_credit_init_done),
.o_tx_req_candidate_accepted(o_req_candidate_accepted),
.o_tx_req_valid(o_req_valid),
.o_tx_req_port(o_req_port),
.o_tx_req_vc(o_req_vc),
.o_tx_req_pool(o_req_pool),
.o_tx_req_payload(o_req_payload),
.o_tx_data_valid(o_data_valid),
.o_tx_data_port(o_data_port),
.o_tx_data_vc(o_data_vc),
.o_tx_data_pool(o_data_pool),
.o_tx_data_offset(o_data_offset),
.o_tx_data_last(o_data_last),
.o_tx_data_payload(o_data_payload),
.o_tx_data_byte_enable(o_data_byte_enable),
.o_tx_data_error(o_data_error),
.o_tx_req_balances(o_req_balances),
.o_tx_data_balances(o_data_balances),
.o_tx_req_init(o_req_init),
.o_tx_data_init(o_data_init),
.o_tx_req_credit_error(o_req_credit_error),
.o_tx_data_credit_error(o_data_credit_error),
.o_tx_req_data_credit_error_sticky(o_req_data_credit_error_sticky),
.o_tx_req_busy(o_req_busy),
.o_tx_req_tdm_known(o_req_tdm_known),
.o_tx_req_tdm_port(o_req_tdm_port),
.o_tx_req_asi(o_req_asi),
.o_tx_req_auth_tag(o_req_auth_tag),
.o_tx_req_src(o_req_src),
.o_tx_req_dst(o_req_dst),
.o_tx_req_tag(o_req_tag),
.o_tx_req_num_beats(o_req_num_beats),
.o_tx_req_address(o_req_address),
.o_tx_req_command(o_req_command),
.o_tx_req_length(o_req_length),
.o_tx_req_attr(o_req_attr),
.o_tx_req_metadata(o_req_metadata),
.o_tx_req_valid_parity(o_req_valid_parity),
.o_tx_req_auth_tag_parity(o_req_auth_tag_parity),
.o_tx_req_address_parity(o_req_address_parity),
.o_tx_req_control_parity(o_req_control_parity),
.o_tx_data_valid_parity(o_data_valid_parity),
.o_tx_data_byte_enable_parity(o_data_byte_enable_parity),
.o_tx_data_fields_parity(o_data_fields_parity),
.o_tx_data_parity(o_data_parity),
.i_tx_rd_candidate_valid(i_rd_candidate_valid),
.i_tx_rd_candidate_port(i_rd_candidate_port),
.i_tx_rd_candidate_vc(i_rd_candidate_vc),
.i_tx_rd_candidate_pools(i_rd_candidate_pools),
.i_tx_rd_candidate_payload(i_rd_candidate_payload),
.i_tx_rd_credit_valid(i_rd_credit_valid),
.i_tx_rd_credit_pool(i_rd_credit_pool),
.i_tx_rd_credit_vc(i_rd_credit_vc),
.i_tx_rd_credit_num(i_rd_credit_num),
.i_tx_rd_credit_init_done(i_rd_credit_init_done),
.o_tx_rd_candidate_accepted(o_rd_candidate_accepted),
.o_tx_rd_candidate_error(o_rd_candidate_error),
.o_tx_rd_valid(o_rd_valid),
.o_tx_rd_port(o_rd_port),
.o_tx_rd_auth_tag(o_rd_auth_tag),
.o_tx_rd_src(o_rd_src),
.o_tx_rd_dst(o_rd_dst),
.o_tx_rd_tag(o_rd_tag),
.o_tx_rd_num_beats(o_rd_num_beats),
.o_tx_rd_data(o_rd_data),
.o_tx_rd_status(o_rd_status),
.o_tx_rd_offset(o_rd_offset),
.o_tx_rd_last(o_rd_last),
.o_tx_rd_data_error(o_rd_data_error),
.o_tx_rd_type_info(o_rd_type_info),
.o_tx_rd_vc(o_rd_vc),
.o_tx_rd_pool(o_rd_pool),
.o_tx_rd_valid_parity(o_rd_valid_parity),
.o_tx_rd_auth_tag_parity(o_rd_auth_tag_parity),
.o_tx_rd_data_parity(o_rd_data_parity),
.o_tx_rd_control_parity(o_rd_control_parity),
.o_tx_rd_payload(o_rd_payload),
.o_tx_rd_busy(o_rd_busy),
.o_tx_rd_balances(o_rd_balances),
.o_tx_rd_init_confirmed(o_rd_init_confirmed),
.o_tx_rd_credit_error(o_rd_credit_error),
.o_tx_rd_credit_error_sticky(o_rd_credit_error_sticky),
.o_tx_rd_tdm_known(o_rd_tdm_known),
.o_tx_rd_tdm_port(o_rd_tdm_port),
.i_tx_wr_candidate_valid(i_wr_candidate_valid),
.i_tx_wr_candidate_port(i_wr_candidate_port),
.i_tx_wr_candidate_vc(i_wr_candidate_vc),
.i_tx_wr_candidate_pool(i_wr_candidate_pool),
.i_tx_wr_candidate_payload(i_wr_candidate_payload),
.i_tx_wr_credit_valid(i_wr_credit_valid),
.i_tx_wr_credit_pool(i_wr_credit_pool),
.i_tx_wr_credit_vc(i_wr_credit_vc),
.i_tx_wr_credit_num(i_wr_credit_num),
.i_tx_wr_credit_init_done(i_wr_credit_init_done),
.o_tx_wr_candidate_accepted(o_wr_candidate_accepted),
.o_tx_wr_valid(o_wr_valid),
.o_tx_wr_type_info(o_wr_type_info),
.o_tx_wr_tag(o_wr_tag),
.o_tx_wr_status(o_wr_status),
.o_tx_wr_src(o_wr_src),
.o_tx_wr_dst(o_wr_dst),
.o_tx_wr_port(o_wr_port),
.o_tx_wr_vc(o_wr_vc),
.o_tx_wr_pool(o_wr_pool),
.o_tx_wr_auth_tag(o_wr_auth_tag),
.o_tx_wr_valid_parity(o_wr_valid_parity),
.o_tx_wr_auth_tag_parity(o_wr_auth_tag_parity),
.o_tx_wr_control_parity(o_wr_control_parity),
.o_tx_wr_balances(o_wr_balances),
.o_tx_wr_init_confirmed(o_wr_init_confirmed),
.o_tx_wr_credit_error(o_wr_credit_error),
.o_tx_wr_credit_error_sticky(o_wr_credit_error_sticky),
.o_tx_wr_tdm_known(o_wr_tdm_known),
.o_tx_wr_tdm_port(o_wr_tdm_port),
.i_tx_req_credit_valid_parity(credit_override ? 1'b0 : i_req_credit_valid_parity ^ credit_fault[0]),
.i_tx_req_credit_parity(credit_override ? 1'b1 : i_req_credit_parity),
.i_tx_data_credit_valid_parity(i_data_credit_valid_parity ^ credit_fault[1]),
.i_tx_data_credit_parity(i_data_credit_parity),
.i_tx_rd_credit_valid_parity(i_rd_credit_valid_parity ^ credit_fault[2]),
.i_tx_rd_credit_parity(i_rd_credit_parity),
.i_tx_wr_credit_valid_parity(i_wr_credit_valid_parity ^ credit_fault[3]),
.i_tx_wr_credit_parity(i_wr_credit_parity),
.o_tx_credit_valid_parity_error(o_credit_valid_parity_error),
.o_tx_credit_control_parity_error(o_credit_control_parity_error),
.o_tx_credit_parity_error(o_credit_parity_error),
.o_tx_credit_integrity_ok(o_credit_integrity_ok),
.i_rx_auth_enabled(1'b1),
.i_rx_select_port(select_port),
.i_req_class_known(1'b1),
.i_req_has_data((link_payload[0][27:22]==6'h28)||(link_payload[0][27:22]==6'h29)),
.o_rx_burst_error(),
.o_rx_burst_error_sticky(),
.o_rx_burst_active(),
.i_rx_req_valid(link_valid[0]),
.i_rx_req_port(link_port[0]),
.i_rx_req_vc(link_vc[0]),
.i_rx_req_pool(link_pool[0]),
.i_rx_req_payload(link_payload[0][183:0]),
.i_rx_req_parity(link_parity[0]),
.o_rx_req_consumer_port(path_req_consumer_port),
.o_rx_req_head_taken(path_req_head_taken),
.o_rx_req_head_payload(path_req_head_payload),
.o_rx_req_head_parity(path_req_head_parity),
.o_rx_req_head_vc(path_req_head_vc),
.o_rx_req_head_pool(path_req_head_pool),
.o_rx_req_head_account(path_req_head_account),
.o_rx_req_head_valid(path_req_head_valid),
.o_rx_req_consume_valid(path_req_consume_valid),
.o_rx_req_credit_valid(path_req_credit_valid),
.o_rx_req_credit_pool(path_req_credit_pool),
.o_rx_req_credit_vc(path_req_credit_vc),
.o_rx_req_credit_num(path_req_credit_num),
.o_rx_req_credit_init_done(path_req_credit_init_done),
.o_rx_req_credit_valid_parity(path_req_credit_valid_parity),
.o_rx_req_credit_parity(path_req_credit_parity),
.i_rx_data_valid(link_valid[1]),
.i_rx_data_port(link_port[1]),
.i_rx_data_vc(link_vc[1]),
.i_rx_data_pool(link_pool[1]),
.i_rx_data_payload(link_payload[1][579:0]),
.i_rx_data_parity(link_parity[1]),
.o_rx_data_consumer_port(path_data_consumer_port),
.o_rx_data_head_taken(path_data_head_taken),
.o_rx_data_head_payload(path_data_head_payload),
.o_rx_data_head_parity(path_data_head_parity),
.o_rx_data_head_vc(path_data_head_vc),
.o_rx_data_head_pool(path_data_head_pool),
.o_rx_data_head_account(path_data_head_account),
.o_rx_data_head_valid(path_data_head_valid),
.o_rx_data_consume_valid(path_data_consume_valid),
.o_rx_data_credit_valid(path_data_credit_valid),
.o_rx_data_credit_pool(path_data_credit_pool),
.o_rx_data_credit_vc(path_data_credit_vc),
.o_rx_data_credit_num(path_data_credit_num),
.o_rx_data_credit_init_done(path_data_credit_init_done),
.o_rx_data_credit_valid_parity(path_data_credit_valid_parity),
.o_rx_data_credit_parity(path_data_credit_parity),
.i_rx_rd_valid(link_valid[2]),
.i_rx_rd_port(link_port[2]),
.i_rx_rd_vc(link_vc[2]),
.i_rx_rd_pool(link_pool[2]),
.i_rx_rd_payload(link_payload[2][618:0]),
.i_rx_rd_parity(link_parity[2]),
.o_rx_rd_head_payload(path_rd_head_payload),
.o_rx_rd_head_parity(path_rd_head_parity),
.o_rx_rd_head_vc(path_rd_head_vc),
.o_rx_rd_head_pool(path_rd_head_pool),
.o_rx_rd_head_account(path_rd_head_account),
.o_rx_rd_head_valid(path_rd_head_valid),
.o_rx_rd_consume_valid(path_rd_consume_valid),
.o_rx_rd_credit_valid(path_rd_credit_valid),
.o_rx_rd_credit_pool(path_rd_credit_pool),
.o_rx_rd_credit_vc(path_rd_credit_vc),
.o_rx_rd_credit_num(path_rd_credit_num),
.o_rx_rd_credit_init_done(path_rd_credit_init_done),
.o_rx_rd_credit_valid_parity(path_rd_credit_valid_parity),
.o_rx_rd_credit_parity(path_rd_credit_parity),
.i_rx_wr_valid(link_valid[3]),
.i_rx_wr_port(link_port[3]),
.i_rx_wr_vc(link_vc[3]),
.i_rx_wr_pool(link_pool[3]),
.i_rx_wr_payload(link_payload[3][100:0]),
.i_rx_wr_parity(link_parity[3]),
.o_rx_wr_head_payload(path_wr_head_payload),
.o_rx_wr_head_parity(path_wr_head_parity),
.o_rx_wr_head_vc(path_wr_head_vc),
.o_rx_wr_head_pool(path_wr_head_pool),
.o_rx_wr_head_account(path_wr_head_account),
.o_rx_wr_head_valid(path_wr_head_valid),
.o_rx_wr_consume_valid(path_wr_consume_valid),
.o_rx_wr_credit_valid(path_wr_credit_valid),
.o_rx_wr_credit_pool(path_wr_credit_pool),
.o_rx_wr_credit_vc(path_wr_credit_vc),
.o_rx_wr_credit_num(path_wr_credit_num),
.o_rx_wr_credit_init_done(path_wr_credit_init_done),
.o_rx_wr_credit_valid_parity(path_wr_credit_valid_parity),
.o_rx_wr_credit_parity(path_wr_credit_parity),
.o_rx_receive_accepted(path_receive_accepted),
.o_rx_ingress_errors(path_ingress_errors),
.o_rx_head_errors(path_head_errors),
.o_rx_control_error(path_control_error),
.o_rx_data_error(path_data_error),
.o_rx_auth_error(path_auth_error),
.o_rx_auth_profile_error(path_auth_profile_error),
.o_rx_metadata_error(path_metadata_error),
.o_rx_fault_stop_request(path_fault_stop_request),
.o_rx_storage_diagnostic(path_storage_diagnostic),
.o_rx_counts(path_counts),
.o_rx_pending_count(path_pending_count),
.o_rx_order_counts(path_order_counts),
.o_rx_order_error(path_order_error),
.o_rx_order_error_sticky(path_order_error_sticky),
.o_rx_tdm_error(path_tdm_error),
.o_rx_tdm_error_sticky(path_tdm_error_sticky),
.o_rx_tdm_phase_known(path_tdm_phase_known),
.o_rx_tdm_expected_port(path_tdm_expected_port),
.i_rx_request_ready(request_ready),
.o_rx_request_valid(path_request_valid),
.o_rx_request_port(path_request_port),
.o_rx_request_vc(path_request_vc),
.o_rx_request_pool(path_request_pool),
.o_rx_request_payload(path_request_payload),
.o_rx_request_data(path_request_data),
.o_rx_request_be(path_request_be),
.o_rx_request_poison(path_request_poison),
.o_rx_request_data_pools(path_request_data_pools),
.o_rx_bridge_busy(path_bridge_busy),
.o_rx_bridge_error(path_bridge_error)
);

reg [1:0] response_held=0;
reg [626:0] held_read;reg [108:0] held_write;
wire [626:0] read_tuple={top_response_port[1:0],top_response_vc[1:0],top_response_pool[0],top_response_account[2:0],top_response_read_payload};
wire [108:0] write_tuple={top_response_port[3:2],top_response_vc[3:2],top_response_pool[1],top_response_account[5:3],top_response_write_payload};
integer response_checks=0;
integer cancelled=0; reg drop_seen=0; reg [3:0] dropped_channels=0; integer dropped_beats=0;
integer cycles=0,checks=0,accepted_req=0,accepted_rd=0,accepted_wr=0,round_index=0;
integer sent_count[0:3],retired_count[0:3],requests=0,total_requests=0,total_returns=0,total_heads=0,stalls=0;
integer nw[0:3][0:PORTS-1],nr[0:3][0:PORTS-1],hw[0:3][0:PORTS-1],hr[0:3][0:PORTS-1];
integer cw[0:3][0:PORTS-1],cr[0:3][0:PORTS-1],ledger[0:3][0:PORTS-1][0:4];
reg [621:0] nq[0:3][0:PORTS-1][0:255],hq[0:3][0:PORTS-1][0:255];
reg [2:0] credit_journal[0:3][0:PORTS-1][0:255];
reg [2500:0] descriptors[0:PORTS-1][0:255];
integer dw[0:PORTS-1],dr[0:PORTS-1],data_need[0:PORTS-1][0:255],data_sum[0:PORTS-1];
reg [2047:0] expected_data;reg [255:0] expected_be;reg [3:0] expected_poison,expected_pools;
reg [2500:0] held_tuple;reg held=0;reg [3:0] sampled_sent;
reg [618:0] payload;integer c,p,a,b,n,j,amount;
wire [3:0] cv[0:3],cp[0:3],ci[0:3];wire [7:0] cvc[0:3],cn[0:3];
wire [1:0] head_vc[0:3];wire head_pool[0:3];
wire [2500:0] descriptor={path_request_port,path_request_vc,path_request_pool,path_request_payload,path_request_data,path_request_be,path_request_poison,path_request_data_pools};
assign cv[0]=path_req_credit_valid;
assign cp[0]=path_req_credit_pool;
assign ci[0]=path_req_credit_init_done;
assign cvc[0]=path_req_credit_vc;
assign cn[0]=path_req_credit_num;
assign head_vc[0]=path_req_head_vc;
assign head_pool[0]=path_req_head_pool;
assign cv[1]=path_data_credit_valid;
assign cp[1]=path_data_credit_pool;
assign ci[1]=path_data_credit_init_done;
assign cvc[1]=path_data_credit_vc;
assign cn[1]=path_data_credit_num;
assign head_vc[1]=path_data_head_vc;
assign head_pool[1]=path_data_head_pool;
assign cv[2]=path_rd_credit_valid;
assign cp[2]=path_rd_credit_pool;
assign ci[2]=path_rd_credit_init_done;
assign cvc[2]=path_rd_credit_vc;
assign cn[2]=path_rd_credit_num;
assign head_vc[2]=path_rd_head_vc;
assign head_pool[2]=path_rd_head_pool;
assign cv[3]=path_wr_credit_valid;
assign cp[3]=path_wr_credit_pool;
assign ci[3]=path_wr_credit_init_done;
assign cvc[3]=path_wr_credit_vc;
assign cn[3]=path_wr_credit_num;
assign head_vc[3]=path_wr_head_vc;
assign head_pool[3]=path_wr_head_pool;
task automatic ck;input condition;input integer id;begin checks=checks+1;if(condition!==1'b1)$fatal(1,"IP_TOP_MISMATCH id=%0d cycle=%0d ports=%0d",id,cycles,PORTS);end endtask
task push_native;input integer ch;input integer port;input [1:0] vc;input pool;input [618:0] data;begin
 ck(nw[ch][port]<256,100);nq[ch][port][nw[ch][port]]={pool,vc,data};nw[ch][port]=nw[ch][port]+1;
end endtask
always @(negedge clk)begin
 cycles=cycles+1;
 if(!rstn)select_port<=0;else select_port<=(select_port+1)%PORTS;
end
always @(posedge clk)begin
 sampled_sent=link_valid & {{2{!originator_drop}},{2{!completer_drop}}};
 if(!rstn)begin
  accepted_req=0;accepted_rd=0;accepted_wr=0;requests=0;held=0;response_held=0;cancelled=0;drop_seen=0;
  for(c=0;c<4;c=c+1)begin
   sent_count[c]=0;retired_count[c]=0;
   for(p=0;p<PORTS;p=p+1)begin
    nw[c][p]=0;nr[c][p]=0;hw[c][p]=0;hr[c][p]=0;cw[c][p]=0;cr[c][p]=0;
    for(a=0;a<5;a=a+1)ledger[c][p][a]=0;
   end
  end
  for(p=0;p<PORTS;p=p+1)begin dw[p]=0;dr[p]=0;data_sum[p]=0;end
 end else if(!fault_mode) begin
  ck(path_storage_diagnostic==0&&path_order_error==0&&path_order_error_sticky==0,1);
  if(!allow_fault)ck(path_fault_stop_request==0&&path_bridge_error==0,2);
  if(!allow_fault)ck(path_tdm_error==0&&path_tdm_error_sticky==0,3);
  if(!allow_fault)ck(path_ingress_errors==0&&path_head_errors==0,4);
  if(path_data_error!=0)data_seen=data_seen+1;
  if(path_control_error!=0)control_seen=control_seen+1;
  ck(o_credit_parity_error==0&&o_credit_integrity_ok==15,5);
  ck(!o_req_data_credit_error_sticky&&!o_rd_credit_error_sticky&&!o_wr_credit_error_sticky,6);
  if(o_req_candidate_accepted)begin
   accepted_req=accepted_req+1;
   push_native(0,i_req_candidate_port,i_req_candidate_vc,i_req_candidate_pool,{435'd0,i_req_candidate_request});
   expected_data=0;expected_be=0;expected_poison=0;expected_pools=0;n=0;
   if(i_req_candidate_has_data)begin
    n=i_req_candidate_num_beats+1;
    for(b=0;b<n;b=b+1)begin
     payload={39'd0,i_req_candidate_data[b*512+:512],i_req_candidate_byte_enable[b*64+:64],b[1:0],(b==i_req_candidate_num_beats),i_req_candidate_error[b]};
     push_native(1,i_req_candidate_port,i_req_candidate_vc,i_req_candidate_data_pools[b],payload);
     expected_data[b*512+:512]=i_req_candidate_data[b*512+:512];expected_be[b*64+:64]=i_req_candidate_byte_enable[b*64+:64];expected_poison[b]=i_req_candidate_error[b] | (data_parity_flip && b==0);expected_pools[b]=i_req_candidate_data_pools[b];
    end
   end
   p=i_req_candidate_port;ck(dw[p]<256,7);
   descriptors[p][dw[p]]={i_req_candidate_port,i_req_candidate_vc,i_req_candidate_pool,i_req_candidate_request,expected_data,expected_be,expected_poison,expected_pools};
   data_sum[p]=data_sum[p]+n;data_need[p][dw[p]]=data_sum[p];dw[p]=dw[p]+1;
  end
  if(o_rd_candidate_accepted)begin
   accepted_rd=accepted_rd+1;n=i_rd_candidate_payload[523:522]+1;
   for(b=0;b<n;b=b+1)push_native(2,i_rd_candidate_port,i_rd_candidate_vc,i_rd_candidate_pools[b],i_rd_candidate_payload[b*619+:619]);
  end
  if(o_wr_candidate_accepted)begin accepted_wr=accepted_wr+1;push_native(3,i_wr_candidate_port,i_wr_candidate_vc,i_wr_candidate_pool,{518'd0,i_wr_candidate_payload});end
  ck(top_response_metadata_error==0&&!top_response_fault_stop_request,240);
  if(response_held[0])ck(top_response_valid[0]&&read_tuple===held_read,241);
  if(response_held[1])ck(top_response_valid[1]&&write_tuple===held_write,242);
  response_held=top_response_valid & {2{!response_ready}};
  if(top_response_valid[0])begin
   p=top_response_port[1:0];ck(hr[2][p]<hw[2][p],243);
   ck({top_response_pool[0],top_response_vc[1:0],top_response_read_payload}===hq[2][p][hr[2][p]],244);
   held_read=read_tuple;response_checks=response_checks+1;
  end
  if(top_response_valid[1])begin
   p=top_response_port[3:2];ck(hr[3][p]<hw[3][p],245);
   ck({top_response_pool[1],top_response_vc[3:2],518'd0,top_response_write_payload}===hq[3][p][hr[3][p]],246);
   held_write=write_tuple;response_checks=response_checks+1;
  end
  ck(top_response_retired===(top_response_valid & {2{response_ready}}),247);
  // Return events precede this edge's head journal update: only earlier actual transfers earn credits.
  for(c=0;c<4;c=c+1)begin
   for(p=0;p<PORTS;p=p+1)if(cv[c][p])begin
    a=cp[c][p]?4:cvc[c][p*2+:2];amount=cn[c][p*2+:2]+1;
    if(ci[c][p])for(j=0;j<amount;j=j+1)begin
     ck(cr[c][p]<cw[c][p],10);ck(credit_journal[c][p][cr[c][p]]==={cp[c][p],cvc[c][p*2+:2]},11);cr[c][p]=cr[c][p]+1;total_returns=total_returns+1;
    end
    ledger[c][p][a]=ledger[c][p][a]+amount;ck(ledger[c][p][a]<=CAP,12);
   end
   if(sent[c])begin
    if((c<2&&completer_drop)||(c>=2&&originator_drop))begin dropped_channels[c]=1;dropped_beats=dropped_beats+1;end
    p=sent_port[c];a=sent_pool[c]?4:sent_vc[c];ck(ledger[c][p][a]>0,13);ledger[c][p][a]=ledger[c][p][a]-1;
    ck(nr[c][p]<nw[c][p],14);ck({sent_pool[c],sent_vc[c],sent_payload[c]}===nq[c][p][nr[c][p]],15);
    nr[c][p]=nr[c][p]+1;hq[c][p][hw[c][p]]={sent_pool[c],sent_vc[c],sent_payload[c]};if(c==1&&data_parity_flip)hq[c][p][hw[c][p]][0]=1;hw[c][p]=hw[c][p]+1;sent_count[c]=sent_count[c]+1;
   end
   if(head_taken[c])begin
    p=head_port[c];ck(hr[c][p]<hw[c][p],16);ck({head_pool[c],head_vc[c],head_payload[c]}===hq[c][p][hr[c][p]],17);
    hr[c][p]=hr[c][p]+1;credit_journal[c][p][cw[c][p]]={head_pool[c],head_vc[c]};cw[c][p]=cw[c][p]+1;retired_count[c]=retired_count[c]+1;total_heads=total_heads+1;
   end
  end
  if(completer_drop)begin
   ck(!path_request_valid&&!path_bridge_busy&&!head_taken[0]&&!head_taken[1],26);
   if(!drop_seen)begin dr[0]=dr[0]+1;cancelled=1;drop_seen=1;end
   held=0;
  end
  if(held)ck(path_request_valid&&descriptor===held_tuple,20);
  held=path_request_valid&&!request_ready;
  if(path_request_valid)begin
   p=path_request_port;ck(p<PORTS&&dr[p]<dw[p],21);ck(descriptor===descriptors[p][dr[p]],22);
   ck(hr[0][p]==dr[p]+1&&hr[1][p]==data_need[p][dr[p]],23);
   ck(!head_taken[0]&&!head_taken[1],24);
   if(request_ready)begin dr[p]=dr[p]+1;requests=requests+1;total_requests=total_requests+1;end
   else begin held_tuple=descriptor;stalls=stalls+1;end
  end
 end
 #1;
 if(rstn&&!fault_mode)ck(path_receive_accepted===sampled_sent,25);
 if(rstn&&check_req_block)ck(!path_receive_accepted[0]&&!path_receive_accepted[1]&&!path_req_head_taken&&!path_data_head_taken,230);
 if(cycles>25000)$fatal(1,"IP_TOP_MISMATCH timeout");
end
function [511:0] pattern;input integer seed;integer j;begin for(j=0;j<64;j=j+1)pattern[j*8+:8]=(seed*17+j*29)&255;end endfunction
task drive_req;integer k,j,before_count;reg [1:0] number;begin
 for(k=0;k<24;k=k+1)begin
  @(negedge clk);#1;i_req_candidate_valid=1;i_req_candidate_port=k%PORTS;i_req_candidate_vc=(k/PORTS)%4;i_req_candidate_pool=k%2;
  number=k%4;i_req_candidate_has_data=(k%3)!=1;i_req_candidate_num_beats=number;i_req_candidate_data_pools=k%16;
  i_req_candidate_request={2'd2,64'h8000000000000001,10'd777,10'd999,(11'd1024+k[10:0]),(i_req_candidate_has_data?number:2'd0),57'h100000000001000,(i_req_candidate_has_data?((k%2)?6'h29:6'h28):6'd3),(i_req_candidate_has_data?{number,4'hf}:6'd63),8'ha5,(k[7:0]^round_index[7:0])};
  for(j=0;j<4;j=j+1)begin i_req_candidate_data[j*512+:512]=pattern(k*4+j+1+round_index*1000);i_req_candidate_byte_enable[j*64+:64]=64'hf0ff55aacc338001^(64'd1<<j);end
  i_req_candidate_error=k%16;before_count=accepted_req;
  while(accepted_req==before_count)begin @(posedge clk);#2;end
  @(negedge clk);#1;i_req_candidate_valid=0;i_req_candidate_request=~i_req_candidate_request;i_req_candidate_data=~i_req_candidate_data;
 end
end endtask
task drive_rd;integer k,j,before_count;reg [1:0] number,off;reg last_flag;begin
 repeat(3)@(negedge clk);
 for(k=0;k<24;k=k+1)begin
  @(negedge clk);#1;i_rd_candidate_valid=1;i_rd_candidate_port=(k+1)%PORTS;i_rd_candidate_vc=(k/PORTS+1)%4;i_rd_candidate_pools=k%16;number=k%4;
  for(j=0;j<4;j=j+1)begin off=(number==0)?((k/4)%4):j;last_flag=(number==0)?((k/4)%2):(j==number);
   i_rd_candidate_payload[j*619+:619]={64'h8000000000000001^(64'd1<<j),(10'd700+j[9:0]),10'd900,(11'd1500+k[10:0]),number,pattern(100+k*4+j+round_index*1000),((k%2)?4'd3:4'd0),off,last_flag,(j==1),2'd0};
  end
  before_count=accepted_rd;while(accepted_rd==before_count)begin @(posedge clk);#2;end
  @(negedge clk);#1;i_rd_candidate_valid=0;i_rd_candidate_payload=~i_rd_candidate_payload;
 end
end endtask
task drive_wr;integer k,before_count;begin
 repeat(7)@(negedge clk);
 for(k=0;k<24;k=k+1)begin
  @(negedge clk);#1;i_wr_candidate_valid=1;i_wr_candidate_port=(k+2)%PORTS;i_wr_candidate_vc=(k/PORTS+2)%4;i_wr_candidate_pool=(k/2)%2;
  i_wr_candidate_payload={64'h8000000000000001,2'd0,(11'd1800+k[10:0]),4'd0,10'd765,10'd987};before_count=accepted_wr;
  while(accepted_wr==before_count)begin @(posedge clk);#2;end
  @(negedge clk);#1;i_wr_candidate_valid=0;i_wr_candidate_payload=~i_wr_candidate_payload;
 end
end endtask
task drain;integer wait_cycles,all_done;begin
 wait_cycles=0;all_done=0;
 while(!all_done&&wait_cycles<5000)begin
  @(negedge clk);#1;all_done=1;
  for(integer ch=0;ch<4;ch=ch+1)for(integer pp=0;pp<PORTS;pp=pp+1)begin
   if(nw[ch][pp]!=nr[ch][pp]||nr[ch][pp]!=hr[ch][pp]||cr[ch][pp]!=cw[ch][pp])all_done=0;
   for(integer aa=0;aa<5;aa=aa+1)if(ledger[ch][pp][aa]!=CAP)all_done=0;
  end
  if(requests+cancelled!=accepted_req||path_counts!=0||path_bridge_busy)all_done=0;
  wait_cycles=wait_cycles+1;
 end
 ck(all_done,200);
end endtask
task start_epoch;integer limit;begin
 @(negedge clk);#1;rstn=0;peer_ready=0;consumer_enable=0;fault_mode=0;check_req_block=0;
 repeat(4)@(negedge clk);#1;rstn=1;
 repeat(5)@(negedge clk);#1;peer_ready=1;limit=0;
 while(!((&o_req_init[PORTS-1:0])&&(&o_data_init[PORTS-1:0])&&(&o_rd_init_confirmed[PORTS-1:0])&&(&o_wr_init_confirmed[PORTS-1:0]))&&limit<100)begin @(negedge clk);#1;limit=limit+1;end
 ck(limit<100,210);
end endtask
task one_request(input bit write_req);integer before_req,limit;begin
 @(negedge clk);#1;
 before_req=source_handshakes;i_req_candidate_valid=1;i_req_candidate_port=0;i_req_candidate_vc=3;i_req_candidate_pool=1;
 i_req_candidate_has_data=write_req;i_req_candidate_num_beats=0;i_req_candidate_data_pools=1;
 i_req_candidate_request={2'd2,64'h8000000000000001,10'd777,10'd999,11'd1024,2'd0,57'h100000000001000,(write_req?6'h28:6'h03),6'd15,8'hff,8'h5a};
 i_req_candidate_data={2048{1'b1}};i_req_candidate_byte_enable={256{1'b1}};i_req_candidate_error=0;
 limit=0;
 while(source_handshakes==before_req&&limit<100)begin @(posedge clk);#2;limit=limit+1;end
 ck(limit<100,220);@(negedge clk);#1;i_req_candidate_valid=0;
end endtask
initial begin
 for(round_index=0;round_index<2;round_index=round_index+1)begin
 start_epoch();
 fork
  drive_req();drive_rd();drive_wr();
  begin repeat(220)@(negedge clk);#1;consumer_enable=1;end
 join
 drain();
 ck(accepted_req==24&&accepted_rd==24&&accepted_wr==24&&requests==24,201);
 ck(sent_count[0]==24&&sent_count[1]==40&&sent_count[2]==60&&sent_count[3]==24,202);
 $display("IP_TOP_ROUND ports=%0d round=%0d requests=%0d req=%0d data=%0d rd=%0d wr=%0d",PORTS,round_index,requests,sent_count[0],sent_count[1],sent_count[2],sent_count[3]);
 if(round_index==0)begin
  @(negedge clk);#1;consumer_enable=0;
  fork : abandoned
   drive_req();drive_rd();drive_wr();
  join_none
  repeat(80)@(negedge clk);#1;
  ck(path_request_valid&&path_counts!=0,203);
  disable abandoned;i_req_candidate_valid=0;i_rd_candidate_valid=0;i_wr_candidate_valid=0;
  @(negedge clk);#1;rstn=0;repeat(4)@(negedge clk);#1;rstn=1;consumer_enable=1;
  repeat(80)@(negedge clk);#1;
  ck(requests==0&&!path_bridge_busy&&path_counts==0,204);
 end
 end
  // A real data parity error becomes poison while the descriptor and true credits progress.
 allow_fault=1;start_epoch();data_parity_flip=1;consumer_enable=1;
 one_request(1);data_parity_flip=0;drain();
 ck(data_seen>0&&top_drop_roles==0&&requests==1,221);
 // The same actual source can spend a Req credit before a corrupted return group arrives.
 start_epoch();fault_mode=1;consumer_enable=0;one_request(0);
 saved_bank=o_req_balances;credit_override=1;
 #1;ck(top_raw_credit_error==1&&top_drop_roles==ORIGINATOR_SCOPE&&!o_req_valid&&!o_data_valid,222);
 @(posedge clk);#2;ck(o_req_balances===saved_bank,223);
 @(negedge clk);#1;credit_override=0;fault_ack=3;
 repeat(4)@(negedge clk);#1;ck(top_drop_roles==ORIGINATOR_SCOPE&&top_reset_required==ORIGINATOR_SCOPE&&top_notify_roles==0,224);fault_ack=0;
 // A bad Request control beat uses the forward Completer scope and cancels its holding.
 start_epoch();fault_mode=1;native_flip=1;one_request(0);native_flip=0;
 repeat(3)@(negedge clk);#1;
 ck(top_drop_roles==COMPLETER_SCOPE&&top_reset_required==COMPLETER_SCOPE&&!path_bridge_busy&&!path_request_valid,225);
 check_req_block=1;if(!TL)one_request(0);repeat(4)@(negedge clk);#1;
 // Keep presenting real response candidates: same-role TX must not emit after Drop.
 i_wr_candidate_valid=1;i_wr_candidate_port=0;i_wr_candidate_vc=0;i_wr_candidate_pool=0;
 i_wr_candidate_payload={64'h8000000000000001,2'd0,11'd1024,4'd0,10'd999,10'd777};
 repeat(10)begin @(negedge clk);#1;ck(!o_wr_valid&&!o_wr_candidate_accepted&&!path_receive_accepted[0]&&!path_receive_accepted[1],226);end
 i_wr_candidate_valid=0;fault_ack=3;repeat(4)@(negedge clk);#1;ck(top_drop_roles==COMPLETER_SCOPE&&top_notify_roles==0,227);fault_ack=0;
 // Reset the complete transport/ownership epoch and reuse the same request Tag.
 start_epoch();fault_mode=0;allow_fault=0;consumer_enable=1;one_request(0);drain();
 ck(top_drop_roles==0&&top_reason_sticky==0&&requests==1&&!top_backend_implemented&&response_checks>100,228);
 ck(stalls>100,205);
 $display("IP_TOP_PASS ports=%0d tl=%0d requests=%0d heads=%0d returns=%0d stalls=%0d dropped=%0d checks=%0d cycles=%0d",PORTS,TL,total_requests,total_heads,total_returns,stalls,dropped_beats,checks,cycles);
 $finish;
end
endmodule
