`timescale 1ns/1ps
module tb;
parameter P=1,TL=0;
localparam C_NUM_PORTS=P,C_CREDIT_WIDTH=4,C_ORDER_COUNT_WIDTH=7,C_PENDING_WIDTH=3;
reg  i_clk=0;
reg  i_rstn=0;
reg  i_originator_ready=0;
wire  i_originator_peer_req;
wire  i_originator_peer_ack;
wire  o_originator_req;
wire  o_originator_ack;
wire  o_originator_tx_connected;
wire  o_originator_rx_connected;
wire  o_originator_beats_connected;
reg  i_completer_ready=0;
wire  i_completer_peer_req;
wire  i_completer_peer_ack;
wire  o_completer_req;
wire  o_completer_ack;
wire  o_completer_tx_connected;
wire  o_completer_rx_connected;
wire  o_completer_beats_connected;
reg [1:0] i_fault_ack=0;
wire [1:0] o_drop_roles;
wire [2*C_NUM_PORTS-1:0] o_drop_ports;
wire [1:0] o_notify_roles;
wire [1:0] o_ack_accepted;
wire [1:0] o_reset_required;
wire [31:0] o_reason_sticky;
wire [1:0] o_init_incomplete;
wire [3:0] o_data_error_observed;
wire [3:0] o_raw_credit_valid_error;
wire [3:0] o_raw_credit_control_error;
wire [3:0] o_raw_credit_error;
wire  o_backend_implemented;
reg  i_tx_req_candidate_valid=0;
reg [1:0] i_tx_req_candidate_port=0;
reg [1:0] i_tx_req_candidate_vc=0;
reg  i_tx_req_candidate_pool=0;
reg  i_tx_req_candidate_has_data=0;
reg [1:0] i_tx_req_candidate_num_beats=0;
reg [3:0] i_tx_req_candidate_data_pools=0;
reg [183:0] i_tx_req_candidate_request=0;
reg [2047:0] i_tx_req_candidate_data=0;
reg [255:0] i_tx_req_candidate_byte_enable=0;
reg [3:0] i_tx_req_candidate_error=0;
reg [3:0] i_tx_req_credit_valid=0;
reg [3:0] i_tx_req_credit_pool=0;
reg [7:0] i_tx_req_credit_vc=0;
reg [7:0] i_tx_req_credit_num=0;
reg [3:0] i_tx_req_credit_init_done=0;
reg [3:0] i_tx_data_credit_valid=0;
reg [3:0] i_tx_data_credit_pool=0;
reg [7:0] i_tx_data_credit_vc=0;
reg [7:0] i_tx_data_credit_num=0;
reg [3:0] i_tx_data_credit_init_done=0;
wire  o_tx_req_candidate_accepted;
wire  o_tx_req_valid;
wire [1:0] o_tx_req_port;
wire [1:0] o_tx_req_vc;
wire  o_tx_req_pool;
wire [183:0] o_tx_req_payload;
wire  o_tx_data_valid;
wire [1:0] o_tx_data_port;
wire [1:0] o_tx_data_vc;
wire  o_tx_data_pool;
wire [1:0] o_tx_data_offset;
wire  o_tx_data_last;
wire [511:0] o_tx_data_payload;
wire [63:0] o_tx_data_byte_enable;
wire  o_tx_data_error;
wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_tx_req_balances;
wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_tx_data_balances;
wire [3:0] o_tx_req_init;
wire [3:0] o_tx_data_init;
wire  o_tx_req_credit_error;
wire  o_tx_data_credit_error;
wire  o_tx_req_data_credit_error_sticky;
wire [3:0] o_tx_req_busy;
wire  o_tx_req_tdm_known;
wire [1:0] o_tx_req_tdm_port;
wire [1:0] o_tx_req_asi;
wire [63:0] o_tx_req_auth_tag;
wire [9:0] o_tx_req_src;
wire [9:0] o_tx_req_dst;
wire [10:0] o_tx_req_tag;
wire [1:0] o_tx_req_num_beats;
wire [56:0] o_tx_req_address;
wire [5:0] o_tx_req_command;
wire [5:0] o_tx_req_length;
wire [7:0] o_tx_req_attr;
wire [7:0] o_tx_req_metadata;
wire  o_tx_req_valid_parity;
wire  o_tx_req_auth_tag_parity;
wire  o_tx_req_address_parity;
wire  o_tx_req_control_parity;
wire  o_tx_data_valid_parity;
wire  o_tx_data_byte_enable_parity;
wire  o_tx_data_fields_parity;
wire [7:0] o_tx_data_parity;
reg  i_tx_rd_candidate_valid=0;
reg [1:0] i_tx_rd_candidate_port=0;
reg [1:0] i_tx_rd_candidate_vc=0;
reg [3:0] i_tx_rd_candidate_pools=0;
reg [2475:0] i_tx_rd_candidate_payload=0;
reg [3:0] i_tx_rd_credit_valid=0;
reg [3:0] i_tx_rd_credit_pool=0;
reg [7:0] i_tx_rd_credit_vc=0;
reg [7:0] i_tx_rd_credit_num=0;
reg [3:0] i_tx_rd_credit_init_done=0;
wire  o_tx_rd_candidate_accepted;
wire  o_tx_rd_candidate_error;
wire  o_tx_rd_valid;
wire [1:0] o_tx_rd_port;
wire [63:0] o_tx_rd_auth_tag;
wire [9:0] o_tx_rd_src;
wire [9:0] o_tx_rd_dst;
wire [10:0] o_tx_rd_tag;
wire [1:0] o_tx_rd_num_beats;
wire [511:0] o_tx_rd_data;
wire [3:0] o_tx_rd_status;
wire [1:0] o_tx_rd_offset;
wire  o_tx_rd_last;
wire  o_tx_rd_data_error;
wire [1:0] o_tx_rd_type_info;
wire [1:0] o_tx_rd_vc;
wire  o_tx_rd_pool;
wire  o_tx_rd_valid_parity;
wire  o_tx_rd_auth_tag_parity;
wire [7:0] o_tx_rd_data_parity;
wire  o_tx_rd_control_parity;
wire [618:0] o_tx_rd_payload;
wire [3:0] o_tx_rd_busy;
wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_tx_rd_balances;
wire [3:0] o_tx_rd_init_confirmed;
wire  o_tx_rd_credit_error;
wire  o_tx_rd_credit_error_sticky;
wire  o_tx_rd_tdm_known;
wire [1:0] o_tx_rd_tdm_port;
reg  i_tx_wr_candidate_valid=0;
reg [1:0] i_tx_wr_candidate_port=0;
reg [1:0] i_tx_wr_candidate_vc=0;
reg  i_tx_wr_candidate_pool=0;
reg [100:0] i_tx_wr_candidate_payload=0;
reg [3:0] i_tx_wr_credit_valid=0;
reg [3:0] i_tx_wr_credit_pool=0;
reg [7:0] i_tx_wr_credit_vc=0;
reg [7:0] i_tx_wr_credit_num=0;
reg [3:0] i_tx_wr_credit_init_done=0;
wire  o_tx_wr_candidate_accepted;
wire  o_tx_wr_valid;
wire [1:0] o_tx_wr_type_info;
wire [10:0] o_tx_wr_tag;
wire [3:0] o_tx_wr_status;
wire [9:0] o_tx_wr_src;
wire [9:0] o_tx_wr_dst;
wire [1:0] o_tx_wr_port;
wire [1:0] o_tx_wr_vc;
wire  o_tx_wr_pool;
wire [63:0] o_tx_wr_auth_tag;
wire  o_tx_wr_valid_parity;
wire  o_tx_wr_auth_tag_parity;
wire  o_tx_wr_control_parity;
wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_tx_wr_balances;
wire [3:0] o_tx_wr_init_confirmed;
wire  o_tx_wr_credit_error;
wire  o_tx_wr_credit_error_sticky;
wire  o_tx_wr_tdm_known;
wire [1:0] o_tx_wr_tdm_port;
reg  i_tx_req_credit_valid_parity=0;
reg  i_tx_req_credit_parity=0;
reg  i_tx_data_credit_valid_parity=0;
reg  i_tx_data_credit_parity=0;
reg  i_tx_rd_credit_valid_parity=0;
reg  i_tx_rd_credit_parity=0;
reg  i_tx_wr_credit_valid_parity=0;
reg  i_tx_wr_credit_parity=0;
wire [3:0] o_tx_credit_valid_parity_error;
wire [3:0] o_tx_credit_control_parity_error;
wire [3:0] o_tx_credit_parity_error;
wire [3:0] o_tx_credit_integrity_ok;
reg  i_rx_auth_enabled=0;
reg [1:0] i_rx_select_port=0;
reg  i_rx_req_valid=0;
reg [1:0] i_rx_req_port=0;
reg [1:0] i_rx_req_vc=0;
reg  i_rx_req_pool=0;
reg [183:0] i_rx_req_payload=0;
reg [12:0] i_rx_req_parity=0;
wire [1:0] o_rx_req_consumer_port;
wire  o_rx_req_head_taken;
wire [183:0] o_rx_req_head_payload;
wire [12:0] o_rx_req_head_parity;
wire [1:0] o_rx_req_head_vc;
wire  o_rx_req_head_pool;
wire [2:0] o_rx_req_head_account;
wire  o_rx_req_head_valid;
wire  o_rx_req_consume_valid;
wire [3:0] o_rx_req_credit_valid;
wire [3:0] o_rx_req_credit_pool;
wire [7:0] o_rx_req_credit_vc;
wire [7:0] o_rx_req_credit_num;
wire [3:0] o_rx_req_credit_init_done;
wire  o_rx_req_credit_valid_parity;
wire  o_rx_req_credit_parity;
reg  i_rx_data_valid=0;
reg [1:0] i_rx_data_port=0;
reg [1:0] i_rx_data_vc=0;
reg  i_rx_data_pool=0;
reg [579:0] i_rx_data_payload=0;
reg [12:0] i_rx_data_parity=0;
wire [1:0] o_rx_data_consumer_port;
wire  o_rx_data_head_taken;
wire [579:0] o_rx_data_head_payload;
wire [12:0] o_rx_data_head_parity;
wire [1:0] o_rx_data_head_vc;
wire  o_rx_data_head_pool;
wire [2:0] o_rx_data_head_account;
wire  o_rx_data_head_valid;
wire  o_rx_data_consume_valid;
wire [3:0] o_rx_data_credit_valid;
wire [3:0] o_rx_data_credit_pool;
wire [7:0] o_rx_data_credit_vc;
wire [7:0] o_rx_data_credit_num;
wire [3:0] o_rx_data_credit_init_done;
wire  o_rx_data_credit_valid_parity;
wire  o_rx_data_credit_parity;
reg  i_rx_rd_valid=0;
reg [1:0] i_rx_rd_port=0;
reg [1:0] i_rx_rd_vc=0;
reg  i_rx_rd_pool=0;
reg [618:0] i_rx_rd_payload=0;
reg [12:0] i_rx_rd_parity=0;
wire [618:0] o_rx_rd_head_payload;
wire [12:0] o_rx_rd_head_parity;
wire [1:0] o_rx_rd_head_vc;
wire  o_rx_rd_head_pool;
wire [2:0] o_rx_rd_head_account;
wire  o_rx_rd_head_valid;
wire  o_rx_rd_consume_valid;
wire [3:0] o_rx_rd_credit_valid;
wire [3:0] o_rx_rd_credit_pool;
wire [7:0] o_rx_rd_credit_vc;
wire [7:0] o_rx_rd_credit_num;
wire [3:0] o_rx_rd_credit_init_done;
wire  o_rx_rd_credit_valid_parity;
wire  o_rx_rd_credit_parity;
reg  i_rx_wr_valid=0;
reg [1:0] i_rx_wr_port=0;
reg [1:0] i_rx_wr_vc=0;
reg  i_rx_wr_pool=0;
reg [100:0] i_rx_wr_payload=0;
reg [12:0] i_rx_wr_parity=0;
wire [100:0] o_rx_wr_head_payload;
wire [12:0] o_rx_wr_head_parity;
wire [1:0] o_rx_wr_head_vc;
wire  o_rx_wr_head_pool;
wire [2:0] o_rx_wr_head_account;
wire  o_rx_wr_head_valid;
wire  o_rx_wr_consume_valid;
wire [3:0] o_rx_wr_credit_valid;
wire [3:0] o_rx_wr_credit_pool;
wire [7:0] o_rx_wr_credit_vc;
wire [7:0] o_rx_wr_credit_num;
wire [3:0] o_rx_wr_credit_init_done;
wire  o_rx_wr_credit_valid_parity;
wire  o_rx_wr_credit_parity;
wire [3:0] o_rx_receive_accepted;
wire [51:0] o_rx_ingress_errors;
wire [51:0] o_rx_head_errors;
wire [3:0] o_rx_control_error;
wire [3:0] o_rx_data_error;
wire [3:0] o_rx_auth_error;
wire [3:0] o_rx_auth_profile_error;
wire [3:0] o_rx_metadata_error;
wire [3:0] o_rx_fault_stop_request;
wire [11:0] o_rx_storage_diagnostic;
wire [4*C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_rx_counts;
wire [16*C_PENDING_WIDTH-1:0] o_rx_pending_count;
wire [4*C_NUM_PORTS*C_ORDER_COUNT_WIDTH-1:0] o_rx_order_counts;
wire [4*C_NUM_PORTS-1:0] o_rx_order_error;
wire [4*C_NUM_PORTS-1:0] o_rx_order_error_sticky;
wire [3:0] o_rx_tdm_error;
wire [3:0] o_rx_tdm_error_sticky;
wire [2:0] o_rx_tdm_phase_known;
wire [5:0] o_rx_tdm_expected_port;
reg  i_rx_request_ready=0;
wire  o_rx_request_valid;
wire [1:0] o_rx_request_port;
wire [1:0] o_rx_request_vc;
wire  o_rx_request_pool;
wire [183:0] o_rx_request_payload;
wire [2047:0] o_rx_request_data;
wire [255:0] o_rx_request_be;
wire [3:0] o_rx_request_poison;
wire [3:0] o_rx_request_data_pools;
wire  o_rx_bridge_busy;
wire  o_rx_bridge_error;
reg [1:0] i_response_select_valid=0;
reg [3:0] i_response_select_port=0;
reg [1:0] i_response_retire_ready=0;
wire [1:0] o_response_valid;
wire [3:0] o_response_port;
wire [3:0] o_response_vc;
wire [1:0] o_response_pool;
wire [5:0] o_response_account;
wire [618:0] o_response_read_payload;
wire [100:0] o_response_write_payload;
wire [1:0] o_response_retired;
wire [1:0] o_response_metadata_error;
reg  i_req_class_known=0;
reg  i_req_has_data=0;
wire [9:0] o_rx_burst_error;
wire [9:0] o_rx_burst_error_sticky;
wire [C_NUM_PORTS-1:0] o_rx_burst_active;
assign i_originator_peer_req=o_completer_req;
assign i_originator_peer_ack=o_completer_ack;
assign i_completer_peer_req=o_originator_req;
assign i_completer_peer_ack=o_originator_ack;
always #5 i_clk=~i_clk;
upli_endpoint_ip_top #(.C_NUM_PORTS(P),.C_IS_TL(TL)) dut(
.i_clk(i_clk),
.i_rstn(i_rstn),
.i_originator_ready(i_originator_ready),
.i_originator_peer_req(i_originator_peer_req),
.i_originator_peer_ack(i_originator_peer_ack),
.o_originator_req(o_originator_req),
.o_originator_ack(o_originator_ack),
.o_originator_tx_connected(o_originator_tx_connected),
.o_originator_rx_connected(o_originator_rx_connected),
.o_originator_beats_connected(o_originator_beats_connected),
.i_completer_ready(i_completer_ready),
.i_completer_peer_req(i_completer_peer_req),
.i_completer_peer_ack(i_completer_peer_ack),
.o_completer_req(o_completer_req),
.o_completer_ack(o_completer_ack),
.o_completer_tx_connected(o_completer_tx_connected),
.o_completer_rx_connected(o_completer_rx_connected),
.o_completer_beats_connected(o_completer_beats_connected),
.i_fault_ack(i_fault_ack),
.o_drop_roles(o_drop_roles),
.o_drop_ports(o_drop_ports),
.o_notify_roles(o_notify_roles),
.o_ack_accepted(o_ack_accepted),
.o_reset_required(o_reset_required),
.o_reason_sticky(o_reason_sticky),
.o_init_incomplete(o_init_incomplete),
.o_data_error_observed(o_data_error_observed),
.o_raw_credit_valid_error(o_raw_credit_valid_error),
.o_raw_credit_control_error(o_raw_credit_control_error),
.o_raw_credit_error(o_raw_credit_error),
.o_backend_implemented(o_backend_implemented),
.i_tx_req_candidate_valid(i_tx_req_candidate_valid),
.i_tx_req_candidate_port(i_tx_req_candidate_port),
.i_tx_req_candidate_vc(i_tx_req_candidate_vc),
.i_tx_req_candidate_pool(i_tx_req_candidate_pool),
.i_tx_req_candidate_has_data(i_tx_req_candidate_has_data),
.i_tx_req_candidate_num_beats(i_tx_req_candidate_num_beats),
.i_tx_req_candidate_data_pools(i_tx_req_candidate_data_pools),
.i_tx_req_candidate_request(i_tx_req_candidate_request),
.i_tx_req_candidate_data(i_tx_req_candidate_data),
.i_tx_req_candidate_byte_enable(i_tx_req_candidate_byte_enable),
.i_tx_req_candidate_error(i_tx_req_candidate_error),
.i_tx_req_credit_valid(i_tx_req_credit_valid),
.i_tx_req_credit_pool(i_tx_req_credit_pool),
.i_tx_req_credit_vc(i_tx_req_credit_vc),
.i_tx_req_credit_num(i_tx_req_credit_num),
.i_tx_req_credit_init_done(i_tx_req_credit_init_done),
.i_tx_data_credit_valid(i_tx_data_credit_valid),
.i_tx_data_credit_pool(i_tx_data_credit_pool),
.i_tx_data_credit_vc(i_tx_data_credit_vc),
.i_tx_data_credit_num(i_tx_data_credit_num),
.i_tx_data_credit_init_done(i_tx_data_credit_init_done),
.o_tx_req_candidate_accepted(o_tx_req_candidate_accepted),
.o_tx_req_valid(o_tx_req_valid),
.o_tx_req_port(o_tx_req_port),
.o_tx_req_vc(o_tx_req_vc),
.o_tx_req_pool(o_tx_req_pool),
.o_tx_req_payload(o_tx_req_payload),
.o_tx_data_valid(o_tx_data_valid),
.o_tx_data_port(o_tx_data_port),
.o_tx_data_vc(o_tx_data_vc),
.o_tx_data_pool(o_tx_data_pool),
.o_tx_data_offset(o_tx_data_offset),
.o_tx_data_last(o_tx_data_last),
.o_tx_data_payload(o_tx_data_payload),
.o_tx_data_byte_enable(o_tx_data_byte_enable),
.o_tx_data_error(o_tx_data_error),
.o_tx_req_balances(o_tx_req_balances),
.o_tx_data_balances(o_tx_data_balances),
.o_tx_req_init(o_tx_req_init),
.o_tx_data_init(o_tx_data_init),
.o_tx_req_credit_error(o_tx_req_credit_error),
.o_tx_data_credit_error(o_tx_data_credit_error),
.o_tx_req_data_credit_error_sticky(o_tx_req_data_credit_error_sticky),
.o_tx_req_busy(o_tx_req_busy),
.o_tx_req_tdm_known(o_tx_req_tdm_known),
.o_tx_req_tdm_port(o_tx_req_tdm_port),
.o_tx_req_asi(o_tx_req_asi),
.o_tx_req_auth_tag(o_tx_req_auth_tag),
.o_tx_req_src(o_tx_req_src),
.o_tx_req_dst(o_tx_req_dst),
.o_tx_req_tag(o_tx_req_tag),
.o_tx_req_num_beats(o_tx_req_num_beats),
.o_tx_req_address(o_tx_req_address),
.o_tx_req_command(o_tx_req_command),
.o_tx_req_length(o_tx_req_length),
.o_tx_req_attr(o_tx_req_attr),
.o_tx_req_metadata(o_tx_req_metadata),
.o_tx_req_valid_parity(o_tx_req_valid_parity),
.o_tx_req_auth_tag_parity(o_tx_req_auth_tag_parity),
.o_tx_req_address_parity(o_tx_req_address_parity),
.o_tx_req_control_parity(o_tx_req_control_parity),
.o_tx_data_valid_parity(o_tx_data_valid_parity),
.o_tx_data_byte_enable_parity(o_tx_data_byte_enable_parity),
.o_tx_data_fields_parity(o_tx_data_fields_parity),
.o_tx_data_parity(o_tx_data_parity),
.i_tx_rd_candidate_valid(i_tx_rd_candidate_valid),
.i_tx_rd_candidate_port(i_tx_rd_candidate_port),
.i_tx_rd_candidate_vc(i_tx_rd_candidate_vc),
.i_tx_rd_candidate_pools(i_tx_rd_candidate_pools),
.i_tx_rd_candidate_payload(i_tx_rd_candidate_payload),
.i_tx_rd_credit_valid(i_tx_rd_credit_valid),
.i_tx_rd_credit_pool(i_tx_rd_credit_pool),
.i_tx_rd_credit_vc(i_tx_rd_credit_vc),
.i_tx_rd_credit_num(i_tx_rd_credit_num),
.i_tx_rd_credit_init_done(i_tx_rd_credit_init_done),
.o_tx_rd_candidate_accepted(o_tx_rd_candidate_accepted),
.o_tx_rd_candidate_error(o_tx_rd_candidate_error),
.o_tx_rd_valid(o_tx_rd_valid),
.o_tx_rd_port(o_tx_rd_port),
.o_tx_rd_auth_tag(o_tx_rd_auth_tag),
.o_tx_rd_src(o_tx_rd_src),
.o_tx_rd_dst(o_tx_rd_dst),
.o_tx_rd_tag(o_tx_rd_tag),
.o_tx_rd_num_beats(o_tx_rd_num_beats),
.o_tx_rd_data(o_tx_rd_data),
.o_tx_rd_status(o_tx_rd_status),
.o_tx_rd_offset(o_tx_rd_offset),
.o_tx_rd_last(o_tx_rd_last),
.o_tx_rd_data_error(o_tx_rd_data_error),
.o_tx_rd_type_info(o_tx_rd_type_info),
.o_tx_rd_vc(o_tx_rd_vc),
.o_tx_rd_pool(o_tx_rd_pool),
.o_tx_rd_valid_parity(o_tx_rd_valid_parity),
.o_tx_rd_auth_tag_parity(o_tx_rd_auth_tag_parity),
.o_tx_rd_data_parity(o_tx_rd_data_parity),
.o_tx_rd_control_parity(o_tx_rd_control_parity),
.o_tx_rd_payload(o_tx_rd_payload),
.o_tx_rd_busy(o_tx_rd_busy),
.o_tx_rd_balances(o_tx_rd_balances),
.o_tx_rd_init_confirmed(o_tx_rd_init_confirmed),
.o_tx_rd_credit_error(o_tx_rd_credit_error),
.o_tx_rd_credit_error_sticky(o_tx_rd_credit_error_sticky),
.o_tx_rd_tdm_known(o_tx_rd_tdm_known),
.o_tx_rd_tdm_port(o_tx_rd_tdm_port),
.i_tx_wr_candidate_valid(i_tx_wr_candidate_valid),
.i_tx_wr_candidate_port(i_tx_wr_candidate_port),
.i_tx_wr_candidate_vc(i_tx_wr_candidate_vc),
.i_tx_wr_candidate_pool(i_tx_wr_candidate_pool),
.i_tx_wr_candidate_payload(i_tx_wr_candidate_payload),
.i_tx_wr_credit_valid(i_tx_wr_credit_valid),
.i_tx_wr_credit_pool(i_tx_wr_credit_pool),
.i_tx_wr_credit_vc(i_tx_wr_credit_vc),
.i_tx_wr_credit_num(i_tx_wr_credit_num),
.i_tx_wr_credit_init_done(i_tx_wr_credit_init_done),
.o_tx_wr_candidate_accepted(o_tx_wr_candidate_accepted),
.o_tx_wr_valid(o_tx_wr_valid),
.o_tx_wr_type_info(o_tx_wr_type_info),
.o_tx_wr_tag(o_tx_wr_tag),
.o_tx_wr_status(o_tx_wr_status),
.o_tx_wr_src(o_tx_wr_src),
.o_tx_wr_dst(o_tx_wr_dst),
.o_tx_wr_port(o_tx_wr_port),
.o_tx_wr_vc(o_tx_wr_vc),
.o_tx_wr_pool(o_tx_wr_pool),
.o_tx_wr_auth_tag(o_tx_wr_auth_tag),
.o_tx_wr_valid_parity(o_tx_wr_valid_parity),
.o_tx_wr_auth_tag_parity(o_tx_wr_auth_tag_parity),
.o_tx_wr_control_parity(o_tx_wr_control_parity),
.o_tx_wr_balances(o_tx_wr_balances),
.o_tx_wr_init_confirmed(o_tx_wr_init_confirmed),
.o_tx_wr_credit_error(o_tx_wr_credit_error),
.o_tx_wr_credit_error_sticky(o_tx_wr_credit_error_sticky),
.o_tx_wr_tdm_known(o_tx_wr_tdm_known),
.o_tx_wr_tdm_port(o_tx_wr_tdm_port),
.i_tx_req_credit_valid_parity(i_tx_req_credit_valid_parity),
.i_tx_req_credit_parity(i_tx_req_credit_parity),
.i_tx_data_credit_valid_parity(i_tx_data_credit_valid_parity),
.i_tx_data_credit_parity(i_tx_data_credit_parity),
.i_tx_rd_credit_valid_parity(i_tx_rd_credit_valid_parity),
.i_tx_rd_credit_parity(i_tx_rd_credit_parity),
.i_tx_wr_credit_valid_parity(i_tx_wr_credit_valid_parity),
.i_tx_wr_credit_parity(i_tx_wr_credit_parity),
.o_tx_credit_valid_parity_error(o_tx_credit_valid_parity_error),
.o_tx_credit_control_parity_error(o_tx_credit_control_parity_error),
.o_tx_credit_parity_error(o_tx_credit_parity_error),
.o_tx_credit_integrity_ok(o_tx_credit_integrity_ok),
.i_rx_auth_enabled(i_rx_auth_enabled),
.i_rx_select_port(i_rx_select_port),
.i_rx_req_valid(i_rx_req_valid),
.i_rx_req_port(i_rx_req_port),
.i_rx_req_vc(i_rx_req_vc),
.i_rx_req_pool(i_rx_req_pool),
.i_rx_req_payload(i_rx_req_payload),
.i_rx_req_parity(i_rx_req_parity),
.o_rx_req_consumer_port(o_rx_req_consumer_port),
.o_rx_req_head_taken(o_rx_req_head_taken),
.o_rx_req_head_payload(o_rx_req_head_payload),
.o_rx_req_head_parity(o_rx_req_head_parity),
.o_rx_req_head_vc(o_rx_req_head_vc),
.o_rx_req_head_pool(o_rx_req_head_pool),
.o_rx_req_head_account(o_rx_req_head_account),
.o_rx_req_head_valid(o_rx_req_head_valid),
.o_rx_req_consume_valid(o_rx_req_consume_valid),
.o_rx_req_credit_valid(o_rx_req_credit_valid),
.o_rx_req_credit_pool(o_rx_req_credit_pool),
.o_rx_req_credit_vc(o_rx_req_credit_vc),
.o_rx_req_credit_num(o_rx_req_credit_num),
.o_rx_req_credit_init_done(o_rx_req_credit_init_done),
.o_rx_req_credit_valid_parity(o_rx_req_credit_valid_parity),
.o_rx_req_credit_parity(o_rx_req_credit_parity),
.i_rx_data_valid(i_rx_data_valid),
.i_rx_data_port(i_rx_data_port),
.i_rx_data_vc(i_rx_data_vc),
.i_rx_data_pool(i_rx_data_pool),
.i_rx_data_payload(i_rx_data_payload),
.i_rx_data_parity(i_rx_data_parity),
.o_rx_data_consumer_port(o_rx_data_consumer_port),
.o_rx_data_head_taken(o_rx_data_head_taken),
.o_rx_data_head_payload(o_rx_data_head_payload),
.o_rx_data_head_parity(o_rx_data_head_parity),
.o_rx_data_head_vc(o_rx_data_head_vc),
.o_rx_data_head_pool(o_rx_data_head_pool),
.o_rx_data_head_account(o_rx_data_head_account),
.o_rx_data_head_valid(o_rx_data_head_valid),
.o_rx_data_consume_valid(o_rx_data_consume_valid),
.o_rx_data_credit_valid(o_rx_data_credit_valid),
.o_rx_data_credit_pool(o_rx_data_credit_pool),
.o_rx_data_credit_vc(o_rx_data_credit_vc),
.o_rx_data_credit_num(o_rx_data_credit_num),
.o_rx_data_credit_init_done(o_rx_data_credit_init_done),
.o_rx_data_credit_valid_parity(o_rx_data_credit_valid_parity),
.o_rx_data_credit_parity(o_rx_data_credit_parity),
.i_rx_rd_valid(i_rx_rd_valid),
.i_rx_rd_port(i_rx_rd_port),
.i_rx_rd_vc(i_rx_rd_vc),
.i_rx_rd_pool(i_rx_rd_pool),
.i_rx_rd_payload(i_rx_rd_payload),
.i_rx_rd_parity(i_rx_rd_parity),
.o_rx_rd_head_payload(o_rx_rd_head_payload),
.o_rx_rd_head_parity(o_rx_rd_head_parity),
.o_rx_rd_head_vc(o_rx_rd_head_vc),
.o_rx_rd_head_pool(o_rx_rd_head_pool),
.o_rx_rd_head_account(o_rx_rd_head_account),
.o_rx_rd_head_valid(o_rx_rd_head_valid),
.o_rx_rd_consume_valid(o_rx_rd_consume_valid),
.o_rx_rd_credit_valid(o_rx_rd_credit_valid),
.o_rx_rd_credit_pool(o_rx_rd_credit_pool),
.o_rx_rd_credit_vc(o_rx_rd_credit_vc),
.o_rx_rd_credit_num(o_rx_rd_credit_num),
.o_rx_rd_credit_init_done(o_rx_rd_credit_init_done),
.o_rx_rd_credit_valid_parity(o_rx_rd_credit_valid_parity),
.o_rx_rd_credit_parity(o_rx_rd_credit_parity),
.i_rx_wr_valid(i_rx_wr_valid),
.i_rx_wr_port(i_rx_wr_port),
.i_rx_wr_vc(i_rx_wr_vc),
.i_rx_wr_pool(i_rx_wr_pool),
.i_rx_wr_payload(i_rx_wr_payload),
.i_rx_wr_parity(i_rx_wr_parity),
.o_rx_wr_head_payload(o_rx_wr_head_payload),
.o_rx_wr_head_parity(o_rx_wr_head_parity),
.o_rx_wr_head_vc(o_rx_wr_head_vc),
.o_rx_wr_head_pool(o_rx_wr_head_pool),
.o_rx_wr_head_account(o_rx_wr_head_account),
.o_rx_wr_head_valid(o_rx_wr_head_valid),
.o_rx_wr_consume_valid(o_rx_wr_consume_valid),
.o_rx_wr_credit_valid(o_rx_wr_credit_valid),
.o_rx_wr_credit_pool(o_rx_wr_credit_pool),
.o_rx_wr_credit_vc(o_rx_wr_credit_vc),
.o_rx_wr_credit_num(o_rx_wr_credit_num),
.o_rx_wr_credit_init_done(o_rx_wr_credit_init_done),
.o_rx_wr_credit_valid_parity(o_rx_wr_credit_valid_parity),
.o_rx_wr_credit_parity(o_rx_wr_credit_parity),
.o_rx_receive_accepted(o_rx_receive_accepted),
.o_rx_ingress_errors(o_rx_ingress_errors),
.o_rx_head_errors(o_rx_head_errors),
.o_rx_control_error(o_rx_control_error),
.o_rx_data_error(o_rx_data_error),
.o_rx_auth_error(o_rx_auth_error),
.o_rx_auth_profile_error(o_rx_auth_profile_error),
.o_rx_metadata_error(o_rx_metadata_error),
.o_rx_fault_stop_request(o_rx_fault_stop_request),
.o_rx_storage_diagnostic(o_rx_storage_diagnostic),
.o_rx_counts(o_rx_counts),
.o_rx_pending_count(o_rx_pending_count),
.o_rx_order_counts(o_rx_order_counts),
.o_rx_order_error(o_rx_order_error),
.o_rx_order_error_sticky(o_rx_order_error_sticky),
.o_rx_tdm_error(o_rx_tdm_error),
.o_rx_tdm_error_sticky(o_rx_tdm_error_sticky),
.o_rx_tdm_phase_known(o_rx_tdm_phase_known),
.o_rx_tdm_expected_port(o_rx_tdm_expected_port),
.i_rx_request_ready(i_rx_request_ready),
.o_rx_request_valid(o_rx_request_valid),
.o_rx_request_port(o_rx_request_port),
.o_rx_request_vc(o_rx_request_vc),
.o_rx_request_pool(o_rx_request_pool),
.o_rx_request_payload(o_rx_request_payload),
.o_rx_request_data(o_rx_request_data),
.o_rx_request_be(o_rx_request_be),
.o_rx_request_poison(o_rx_request_poison),
.o_rx_request_data_pools(o_rx_request_data_pools),
.o_rx_bridge_busy(o_rx_bridge_busy),
.o_rx_bridge_error(o_rx_bridge_error),
.i_response_select_valid(i_response_select_valid),
.i_response_select_port(i_response_select_port),
.i_response_retire_ready(i_response_retire_ready),
.o_response_valid(o_response_valid),
.o_response_port(o_response_port),
.o_response_vc(o_response_vc),
.o_response_pool(o_response_pool),
.o_response_account(o_response_account),
.o_response_read_payload(o_response_read_payload),
.o_response_write_payload(o_response_write_payload),
.o_response_retired(o_response_retired),
.o_response_metadata_error(o_response_metadata_error),
.i_req_class_known(i_req_class_known),
.i_req_has_data(i_req_has_data),
.o_rx_burst_error(o_rx_burst_error),
.o_rx_burst_error_sticky(o_rx_burst_error_sticky),
.o_rx_burst_active(o_rx_burst_active),
.i_context_station(8'd0),
.i_backend_issue_ready(1'b0),
.i_backend_release_valid(1'b0),
.i_backend_release_token(10'd0),
.o_backend_issue_valid(),.o_backend_issue_token(),.o_backend_release_ready(),
.o_context_request_ready(),.o_context_request_token(),.o_context_error(),.o_context_count(),
.o_backend_issue_station(),.o_backend_issue_port(),.o_backend_issue_vc(),.o_backend_issue_pool(),
.o_backend_issue_payload(),.o_backend_issue_data(),.o_backend_issue_be(),.o_backend_issue_poison(),.o_backend_issue_data_pools()
);
integer checks=0,cycles=0,reqs=0,beats=0,faults=0,n,p,k;
reg [9:0] history=0;reg overlay=0;reg [5:0] cmd,len;
reg [1:0] scope;
reg [67:0] req_control;
reg [8:0] data_control;
reg [7:0] dp;
integer b;
task ck;input condition;input integer id;begin checks=checks+1;if(condition!==1'b1)begin $display("DIAG ordersticky=%h profile=%h auth=%h rawcredit=%h txcredit=%b%b%b%b",o_rx_order_error_sticky,o_rx_auth_profile_error,o_rx_auth_error,o_raw_credit_error,o_tx_req_credit_error,o_tx_data_credit_error,o_tx_rd_credit_error,o_tx_wr_credit_error);$fatal(1,"BURST_FAULT_MISMATCH id=%0d cycle=%0d P=%0d TL=%0d err=%h sticky=%h drop=%h reasons=%h order=%h storage=%h metadata=%h tdm=%h bridge=%b",id,cycles,P,TL,o_rx_burst_error,o_rx_burst_error_sticky,o_drop_roles,o_reason_sticky,o_rx_order_error,o_rx_storage_diagnostic,o_rx_metadata_error,o_rx_tdm_error,o_rx_bridge_error);end end endtask
task tick;
 input rv,dv;input integer port;input [1:0] num,off;input last;input [1:0] vc;input known,hasdata,poison;input [9:0] expected;
 begin
 @(negedge i_clk);
 i_rx_req_valid=rv;i_rx_data_valid=dv;i_rx_req_port=port;i_rx_data_port=port;
 i_rx_req_vc=overlay?2'd2:vc;i_rx_data_vc=vc;i_rx_req_pool=1;i_rx_data_pool=1;i_req_class_known=known;i_req_has_data=hasdata;
 // Use existing bridge ordinary profile; monitor classification remains an explicit independent input.
 cmd=hasdata?6'h28:6'h03;len=hasdata?((num+1)*16-1):15;
 i_rx_req_payload={2'd0,64'd0,10'd777,10'd999,11'd1024,num,57'h100000000001000,cmd,len,8'hff,8'h5a};
 i_rx_data_payload={{512{1'b1}},64'h0123456789abcdef,off,last,poison};
 req_control={11'd1024,len,8'hff,cmd,8'h5a,i_rx_req_vc,2'd0,10'd777,10'd999,port[1:0],num,1'b1};
 data_control={1'b1,vc,port[1:0],off,poison,last};
 for(b=0;b<8;b=b+1)dp[b]=^i_rx_data_payload[68+b*64+:64];
 i_rx_req_parity={9'd0,1'b0,(^i_rx_req_payload[84:28]),(^req_control),rv};
 i_rx_data_parity={(^i_rx_data_payload[67:4]),dp,2'd0,(^data_control),dv};
 #2;cycles=cycles+1;
 ck(o_rx_burst_error===expected,1);
 ck(o_rx_control_error==0&&o_rx_auth_profile_error==0,2);
 scope=(history!=0||expected!=0)?(TL?2'b11:2'b10):2'b00;
 ck(o_drop_roles===scope,3);ck(o_drop_ports==={{P{scope[1]}},{P{scope[0]}}},4);
 if(expected!=0)faults=faults+1;
 if(rv)reqs=reqs+1;if(dv)beats=beats+1;
 @(posedge i_clk);#2;
 history=history|expected;
 ck(o_rx_burst_error_sticky===history,5);
 if(history!=0)begin ck(o_reason_sticky[20],6);ck(o_drop_roles===scope,7);end
 if(expected!=0)ck(o_rx_receive_accepted[1:0]==0,8);
 end
endtask
task epoch;
 begin
 @(negedge i_clk);i_rstn=0;i_rx_req_valid=0;i_rx_data_valid=0;i_rx_req_parity=0;i_rx_data_parity=0;i_fault_ack=0;
 i_originator_ready=1;i_completer_ready=1;
 repeat(4)@(posedge i_clk);
 @(negedge i_clk);i_rstn=1;history=0;
 repeat(35)@(posedge i_clk);#2;
 ck(o_originator_beats_connected&&o_completer_beats_connected,10);
 ck((&o_rx_req_credit_init_done[P-1:0])&&(&o_rx_data_credit_init_done[P-1:0]),11);
 ck(o_drop_roles==0&&o_rx_burst_error_sticky==0&&o_rx_burst_active==0,12);
 end
endtask
task tail_gap;input integer port;integer q;begin
 for(q=1;q<P;q=q+1)tick(0,0,(port+q)%P,3,3,1,0,0,1,0,0);
end endtask
task check_hold;
 begin
 @(negedge i_clk);i_fault_ack=3;
 tick(0,0,0,0,0,0,0,0,0,0,0);
 tick(0,0,0,0,0,0,0,1,0,0,0);
 ck(o_notify_roles==0&&o_reset_required==(TL?3:2),15);
 end
endtask
initial begin
 // All lengths and start ports; opaque command, complete error Data and idle classifier noise.
 for(n=1;n<=4;n=n+1)for(p=0;p<P;p=p+1)begin
  epoch();tick(1,1,p,n-1,0,n==1,3,1,1,1,0);
  for(k=1;k<n;k=k+1)begin tail_gap(p);tick(0,1,p,0,k,k==n-1,3,0,0,1,0);end
  ck(o_rx_burst_active==0,20);
 end
 // No-data Request overlays an old tail and changes VC/Num without stealing its context.
 epoch();tick(1,1,0,1,0,0,3,1,1,0,0);tail_gap(0);
 // Request VC changes while OrigData remains with original VC3.
 overlay=1;
 tick(1,1,0,0,1,1,3,1,0,0,0);overlay=0;ck(o_rx_burst_active==0,21);
 // Unknown classification and missing first both reach unique role fault controller.
 epoch();tick(1,0,0,0,0,0,0,0,0,0,10'h100);check_hold();
 epoch();tick(1,0,0,2,0,0,3,1,1,0,10'h002);check_hold();
 // Orphan Data, then wrong first Offset, Last and VC-preserving tail errors.
 epoch();tick(0,1,0,0,0,1,3,1,0,0,10'h004);check_hold();
 epoch();tick(1,1,0,1,1,0,3,1,1,0,10'h020);check_hold();
 epoch();tick(1,1,0,1,0,1,3,1,1,0,10'h040);check_hold();
 epoch();tick(1,1,0,1,0,0,3,1,1,0,0);tail_gap(0);tick(0,0,0,0,1,1,3,0,0,0,10'h010);check_hold();
 epoch();tick(1,1,0,1,0,0,3,1,1,0,0);tail_gap(0);tick(0,1,0,0,1,1,2,0,0,0,10'h080);check_hold();
 epoch();tick(1,1,0,1,0,0,3,1,1,0,0);tail_gap(0);tick(0,1,0,0,0,1,3,0,0,0,10'h020);check_hold();
 epoch();tick(1,1,0,1,0,0,3,1,1,0,0);tail_gap(0);tick(0,1,0,0,1,0,3,0,0,0,10'h040);check_hold();
 epoch();tick(1,0,0,0,0,0,2,1,0,0,0);tick(0,0,0,3,3,1,0,0,1,0,0);
 ck(o_rx_burst_active==0&&o_drop_roles==0,22);
 $display("BURST_FAULT_PASS P=%0d TL=%0d cycles=%0d req=%0d data=%0d faults=%0d checks=%0d",P,TL,cycles,reqs,beats,faults,checks);$finish;
end
endmodule
