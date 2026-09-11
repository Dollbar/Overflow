`timescale 1ns/1ps
module tb;
parameter PORTS=1;
parameter CW=4;
parameter CAP=4;
localparam C_NUM_PORTS=PORTS, C_CREDIT_WIDTH=CW;
reg clk=0; always #5 clk=~clk;
reg rstn=0,peer_ready=0,consumer_enable=0;
reg [3:0] parity_flip=0,valid_parity_flip=0;
wire oq,oa,cq,ca,otx,orx,ctx,crx,ob,cb;
upli_connection_side orig(.i_clk(clk),.i_rstn(rstn),.i_ready(1'b1),.i_peer_req(cq),.i_peer_ack(ca),.o_req(oq),.o_ack(oa),.o_tx_connected(otx),.o_rx_connected(orx),.o_beats_connected(ob));
upli_connection_side #(.C_IS_COMPLETER(1)) comp(.i_clk(clk),.i_rstn(rstn),.i_ready(peer_ready),.i_peer_req(oq),.i_peer_ack(oa),.o_req(cq),.o_ack(ca),.o_tx_connected(ctx),.o_rx_connected(crx),.o_beats_connected(cb));
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
upli_station_tx #(.C_NUM_PORTS(PORTS),.C_CREDIT_WIDTH(CW),.C_DEFAULT_CAPACITY(CAP)) dut(
.i_clk(i_clk),
.i_rstn(i_rstn),
.i_originator_credit_connected(i_originator_credit_connected),
.i_originator_beats_connected(i_originator_beats_connected),
.i_req_candidate_valid(i_req_candidate_valid),
.i_req_candidate_port(i_req_candidate_port),
.i_req_candidate_vc(i_req_candidate_vc),
.i_req_candidate_pool(i_req_candidate_pool),
.i_req_candidate_has_data(i_req_candidate_has_data),
.i_req_candidate_num_beats(i_req_candidate_num_beats),
.i_req_candidate_data_pools(i_req_candidate_data_pools),
.i_req_candidate_request(i_req_candidate_request),
.i_req_candidate_data(i_req_candidate_data),
.i_req_candidate_byte_enable(i_req_candidate_byte_enable),
.i_req_candidate_error(i_req_candidate_error),
.i_req_credit_valid(i_req_credit_valid),
.i_req_credit_pool(i_req_credit_pool),
.i_req_credit_vc(i_req_credit_vc),
.i_req_credit_num(i_req_credit_num),
.i_req_credit_init_done(i_req_credit_init_done),
.i_data_credit_valid(i_data_credit_valid),
.i_data_credit_pool(i_data_credit_pool),
.i_data_credit_vc(i_data_credit_vc),
.i_data_credit_num(i_data_credit_num),
.i_data_credit_init_done(i_data_credit_init_done),
.o_req_candidate_accepted(o_req_candidate_accepted),
.o_req_valid(o_req_valid),
.o_req_port(o_req_port),
.o_req_vc(o_req_vc),
.o_req_pool(o_req_pool),
.o_req_payload(o_req_payload),
.o_data_valid(o_data_valid),
.o_data_port(o_data_port),
.o_data_vc(o_data_vc),
.o_data_pool(o_data_pool),
.o_data_offset(o_data_offset),
.o_data_last(o_data_last),
.o_data_payload(o_data_payload),
.o_data_byte_enable(o_data_byte_enable),
.o_data_error(o_data_error),
.o_req_balances(o_req_balances),
.o_data_balances(o_data_balances),
.o_req_init(o_req_init),
.o_data_init(o_data_init),
.o_req_credit_error(o_req_credit_error),
.o_data_credit_error(o_data_credit_error),
.o_req_data_credit_error_sticky(o_req_data_credit_error_sticky),
.o_req_busy(o_req_busy),
.o_req_tdm_known(o_req_tdm_known),
.o_req_tdm_port(o_req_tdm_port),
.o_req_asi(o_req_asi),
.o_req_auth_tag(o_req_auth_tag),
.o_req_src(o_req_src),
.o_req_dst(o_req_dst),
.o_req_tag(o_req_tag),
.o_req_num_beats(o_req_num_beats),
.o_req_address(o_req_address),
.o_req_command(o_req_command),
.o_req_length(o_req_length),
.o_req_attr(o_req_attr),
.o_req_metadata(o_req_metadata),
.o_req_valid_parity(o_req_valid_parity),
.o_req_auth_tag_parity(o_req_auth_tag_parity),
.o_req_address_parity(o_req_address_parity),
.o_req_control_parity(o_req_control_parity),
.o_data_valid_parity(o_data_valid_parity),
.o_data_byte_enable_parity(o_data_byte_enable_parity),
.o_data_fields_parity(o_data_fields_parity),
.o_data_parity(o_data_parity),
.i_completer_credit_connected(i_completer_credit_connected),
.i_completer_beats_connected(i_completer_beats_connected),
.i_rd_candidate_valid(i_rd_candidate_valid),
.i_rd_candidate_port(i_rd_candidate_port),
.i_rd_candidate_vc(i_rd_candidate_vc),
.i_rd_candidate_pools(i_rd_candidate_pools),
.i_rd_candidate_payload(i_rd_candidate_payload),
.i_rd_credit_valid(i_rd_credit_valid),
.i_rd_credit_pool(i_rd_credit_pool),
.i_rd_credit_vc(i_rd_credit_vc),
.i_rd_credit_num(i_rd_credit_num),
.i_rd_credit_init_done(i_rd_credit_init_done),
.o_rd_candidate_accepted(o_rd_candidate_accepted),
.o_rd_candidate_error(o_rd_candidate_error),
.o_rd_valid(o_rd_valid),
.o_rd_port(o_rd_port),
.o_rd_auth_tag(o_rd_auth_tag),
.o_rd_src(o_rd_src),
.o_rd_dst(o_rd_dst),
.o_rd_tag(o_rd_tag),
.o_rd_num_beats(o_rd_num_beats),
.o_rd_data(o_rd_data),
.o_rd_status(o_rd_status),
.o_rd_offset(o_rd_offset),
.o_rd_last(o_rd_last),
.o_rd_data_error(o_rd_data_error),
.o_rd_type_info(o_rd_type_info),
.o_rd_vc(o_rd_vc),
.o_rd_pool(o_rd_pool),
.o_rd_valid_parity(o_rd_valid_parity),
.o_rd_auth_tag_parity(o_rd_auth_tag_parity),
.o_rd_data_parity(o_rd_data_parity),
.o_rd_control_parity(o_rd_control_parity),
.o_rd_payload(o_rd_payload),
.o_rd_busy(o_rd_busy),
.o_rd_balances(o_rd_balances),
.o_rd_init_confirmed(o_rd_init_confirmed),
.o_rd_credit_error(o_rd_credit_error),
.o_rd_credit_error_sticky(o_rd_credit_error_sticky),
.o_rd_tdm_known(o_rd_tdm_known),
.o_rd_tdm_port(o_rd_tdm_port),
.i_wr_candidate_valid(i_wr_candidate_valid),
.i_wr_candidate_port(i_wr_candidate_port),
.i_wr_candidate_vc(i_wr_candidate_vc),
.i_wr_candidate_pool(i_wr_candidate_pool),
.i_wr_candidate_payload(i_wr_candidate_payload),
.i_wr_credit_valid(i_wr_credit_valid),
.i_wr_credit_pool(i_wr_credit_pool),
.i_wr_credit_vc(i_wr_credit_vc),
.i_wr_credit_num(i_wr_credit_num),
.i_wr_credit_init_done(i_wr_credit_init_done),
.o_wr_candidate_accepted(o_wr_candidate_accepted),
.o_wr_valid(o_wr_valid),
.o_wr_type_info(o_wr_type_info),
.o_wr_tag(o_wr_tag),
.o_wr_status(o_wr_status),
.o_wr_src(o_wr_src),
.o_wr_dst(o_wr_dst),
.o_wr_port(o_wr_port),
.o_wr_vc(o_wr_vc),
.o_wr_pool(o_wr_pool),
.o_wr_auth_tag(o_wr_auth_tag),
.o_wr_valid_parity(o_wr_valid_parity),
.o_wr_auth_tag_parity(o_wr_auth_tag_parity),
.o_wr_control_parity(o_wr_control_parity),
.o_wr_balances(o_wr_balances),
.o_wr_init_confirmed(o_wr_init_confirmed),
.o_wr_credit_error(o_wr_credit_error),
.o_wr_credit_error_sticky(o_wr_credit_error_sticky),
.o_wr_tdm_known(o_wr_tdm_known),
.o_wr_tdm_port(o_wr_tdm_port),
.i_req_credit_valid_parity(i_req_credit_valid_parity),
.i_req_credit_parity(i_req_credit_parity),
.i_data_credit_valid_parity(i_data_credit_valid_parity),
.i_data_credit_parity(i_data_credit_parity),
.i_rd_credit_valid_parity(i_rd_credit_valid_parity),
.i_rd_credit_parity(i_rd_credit_parity),
.i_wr_credit_valid_parity(i_wr_credit_valid_parity),
.i_wr_credit_parity(i_wr_credit_parity),
.o_credit_valid_parity_error(o_credit_valid_parity_error),
.o_credit_control_parity_error(o_credit_control_parity_error),
.o_credit_parity_error(o_credit_parity_error),
.o_credit_integrity_ok(o_credit_integrity_ok)
);
wire [3:0] sent;
wire [1:0] sent_port[0:3],sent_vc[0:3];
wire sent_pool[0:3];
wire [618:0] sent_payload[0:3],head_payload[0:3];
wire [1:0] head_vc[0:3];wire head_pool[0:3],head_valid[0:3];
wire [2:0] diagnostic[0:3];
reg [1:0] consume_port=0;reg [2:0] consume_account=0;
wire [PORTS*5*CW-1:0] counts[0:3];
assign sent[0]=o_req_valid;
assign sent_port[0]=o_req_port;assign sent_vc[0]=o_req_vc;assign sent_pool[0]=o_req_pool;
assign sent_payload[0]={435'd0,{o_req_asi,o_req_auth_tag,o_req_src,o_req_dst,o_req_tag,o_req_num_beats,o_req_address,o_req_command,o_req_length,o_req_attr,o_req_metadata}};
wire [3:0] req_cv,req_cp,req_ci;wire [7:0] req_cvc,req_cn;
wire req_vp,req_fp;
wire [183:0] req_head;
upli_receive_channel #(.C_NUM_PORTS(PORTS),.C_PAYLOAD_WIDTH(184),.C_CREDIT_WIDTH(CW),.C_DEFAULT_CAPACITY(CAP)) rx_req(
.i_clk(clk),.i_rstn(rstn),.i_credit_connected(ctx),.i_beats_connected(cb),
.i_receive_valid(sent[0]),.i_receive_port(sent_port[0]),.i_receive_vc(sent_vc[0]),.i_receive_pool(sent_pool[0]),.i_receive_payload(sent_payload[0][183:0]),
.i_consumer_port(consume_port),.i_consumer_account(consume_account),.i_consumer_ready(consumer_enable),
.o_head_payload(req_head),.o_head_vc(head_vc[0]),.o_head_pool(head_pool[0]),.o_head_valid(),.o_consume_valid(head_valid[0]),.o_receive_accepted(),.o_diagnostic(diagnostic[0]),.o_counts(counts[0]),.o_pending_count(),
.o_credit_valid(req_cv),.o_credit_pool(req_cp),.o_credit_vc(req_cvc),.o_credit_num(req_cn),.o_credit_init_done(req_ci));
assign head_payload[0]= {435'd0,req_head};
upli_credit_return_adapter ret_req(.i_credit_valid(req_cv),.i_credit_pool(req_cp),.i_credit_vc(req_cvc),.i_credit_num(req_cn),.i_credit_init_done(req_ci),
.o_credit_valid(i_req_credit_valid),.o_credit_pool(i_req_credit_pool),.o_credit_vc(i_req_credit_vc),.o_credit_num(i_req_credit_num),.o_credit_init_done(i_req_credit_init_done),.o_credit_valid_parity(req_vp),.o_credit_parity(req_fp));
assign i_req_credit_valid_parity=req_vp^valid_parity_flip[0];
assign i_req_credit_parity=req_fp^parity_flip[0];
assign sent[1]=o_data_valid;
assign sent_port[1]=o_data_port;assign sent_vc[1]=o_data_vc;assign sent_pool[1]=o_data_pool;
assign sent_payload[1]={39'd0,{o_data_payload,o_data_byte_enable,o_data_offset,o_data_last,o_data_error}};
wire [3:0] data_cv,data_cp,data_ci;wire [7:0] data_cvc,data_cn;
wire data_vp,data_fp;
wire [579:0] data_head;
upli_receive_channel #(.C_NUM_PORTS(PORTS),.C_PAYLOAD_WIDTH(580),.C_CREDIT_WIDTH(CW),.C_DEFAULT_CAPACITY(CAP)) rx_data(
.i_clk(clk),.i_rstn(rstn),.i_credit_connected(ctx),.i_beats_connected(cb),
.i_receive_valid(sent[1]),.i_receive_port(sent_port[1]),.i_receive_vc(sent_vc[1]),.i_receive_pool(sent_pool[1]),.i_receive_payload(sent_payload[1][579:0]),
.i_consumer_port(consume_port),.i_consumer_account(consume_account),.i_consumer_ready(consumer_enable),
.o_head_payload(data_head),.o_head_vc(head_vc[1]),.o_head_pool(head_pool[1]),.o_head_valid(),.o_consume_valid(head_valid[1]),.o_receive_accepted(),.o_diagnostic(diagnostic[1]),.o_counts(counts[1]),.o_pending_count(),
.o_credit_valid(data_cv),.o_credit_pool(data_cp),.o_credit_vc(data_cvc),.o_credit_num(data_cn),.o_credit_init_done(data_ci));
assign head_payload[1]= {39'd0,data_head};
upli_credit_return_adapter ret_data(.i_credit_valid(data_cv),.i_credit_pool(data_cp),.i_credit_vc(data_cvc),.i_credit_num(data_cn),.i_credit_init_done(data_ci),
.o_credit_valid(i_data_credit_valid),.o_credit_pool(i_data_credit_pool),.o_credit_vc(i_data_credit_vc),.o_credit_num(i_data_credit_num),.o_credit_init_done(i_data_credit_init_done),.o_credit_valid_parity(data_vp),.o_credit_parity(data_fp));
assign i_data_credit_valid_parity=data_vp^valid_parity_flip[1];
assign i_data_credit_parity=data_fp^parity_flip[1];
assign sent[2]=o_rd_valid;
assign sent_port[2]=o_rd_port;assign sent_vc[2]=o_rd_vc;assign sent_pool[2]=o_rd_pool;
assign sent_payload[2]={o_rd_auth_tag,o_rd_src,o_rd_dst,o_rd_tag,o_rd_num_beats,o_rd_data,o_rd_status,o_rd_offset,o_rd_last,o_rd_data_error,o_rd_type_info};
wire [3:0] rd_cv,rd_cp,rd_ci;wire [7:0] rd_cvc,rd_cn;
wire rd_vp,rd_fp;
wire [618:0] rd_head;
upli_receive_channel #(.C_NUM_PORTS(PORTS),.C_PAYLOAD_WIDTH(619),.C_CREDIT_WIDTH(CW),.C_DEFAULT_CAPACITY(CAP)) rx_rd(
.i_clk(clk),.i_rstn(rstn),.i_credit_connected(otx),.i_beats_connected(ob),
.i_receive_valid(sent[2]),.i_receive_port(sent_port[2]),.i_receive_vc(sent_vc[2]),.i_receive_pool(sent_pool[2]),.i_receive_payload(sent_payload[2][618:0]),
.i_consumer_port(consume_port),.i_consumer_account(consume_account),.i_consumer_ready(consumer_enable),
.o_head_payload(rd_head),.o_head_vc(head_vc[2]),.o_head_pool(head_pool[2]),.o_head_valid(),.o_consume_valid(head_valid[2]),.o_receive_accepted(),.o_diagnostic(diagnostic[2]),.o_counts(counts[2]),.o_pending_count(),
.o_credit_valid(rd_cv),.o_credit_pool(rd_cp),.o_credit_vc(rd_cvc),.o_credit_num(rd_cn),.o_credit_init_done(rd_ci));
assign head_payload[2]= rd_head;
upli_credit_return_adapter ret_rd(.i_credit_valid(rd_cv),.i_credit_pool(rd_cp),.i_credit_vc(rd_cvc),.i_credit_num(rd_cn),.i_credit_init_done(rd_ci),
.o_credit_valid(i_rd_credit_valid),.o_credit_pool(i_rd_credit_pool),.o_credit_vc(i_rd_credit_vc),.o_credit_num(i_rd_credit_num),.o_credit_init_done(i_rd_credit_init_done),.o_credit_valid_parity(rd_vp),.o_credit_parity(rd_fp));
assign i_rd_credit_valid_parity=rd_vp^valid_parity_flip[2];
assign i_rd_credit_parity=rd_fp^parity_flip[2];
assign sent[3]=o_wr_valid;
assign sent_port[3]=o_wr_port;assign sent_vc[3]=o_wr_vc;assign sent_pool[3]=o_wr_pool;
assign sent_payload[3]={518'd0,{o_wr_auth_tag,o_wr_type_info,o_wr_tag,o_wr_status,o_wr_src,o_wr_dst}};
wire [3:0] wr_cv,wr_cp,wr_ci;wire [7:0] wr_cvc,wr_cn;
wire wr_vp,wr_fp;
wire [100:0] wr_head;
upli_receive_channel #(.C_NUM_PORTS(PORTS),.C_PAYLOAD_WIDTH(101),.C_CREDIT_WIDTH(CW),.C_DEFAULT_CAPACITY(CAP)) rx_wr(
.i_clk(clk),.i_rstn(rstn),.i_credit_connected(otx),.i_beats_connected(ob),
.i_receive_valid(sent[3]),.i_receive_port(sent_port[3]),.i_receive_vc(sent_vc[3]),.i_receive_pool(sent_pool[3]),.i_receive_payload(sent_payload[3][100:0]),
.i_consumer_port(consume_port),.i_consumer_account(consume_account),.i_consumer_ready(consumer_enable),
.o_head_payload(wr_head),.o_head_vc(head_vc[3]),.o_head_pool(head_pool[3]),.o_head_valid(),.o_consume_valid(head_valid[3]),.o_receive_accepted(),.o_diagnostic(diagnostic[3]),.o_counts(counts[3]),.o_pending_count(),
.o_credit_valid(wr_cv),.o_credit_pool(wr_cp),.o_credit_vc(wr_cvc),.o_credit_num(wr_cn),.o_credit_init_done(wr_ci));
assign head_payload[3]= {518'd0,wr_head};
upli_credit_return_adapter ret_wr(.i_credit_valid(wr_cv),.i_credit_pool(wr_cp),.i_credit_vc(wr_cvc),.i_credit_num(wr_cn),.i_credit_init_done(wr_ci),
.o_credit_valid(i_wr_credit_valid),.o_credit_pool(i_wr_credit_pool),.o_credit_vc(i_wr_credit_vc),.o_credit_num(i_wr_credit_num),.o_credit_init_done(i_wr_credit_init_done),.o_credit_valid_parity(wr_vp),.o_credit_parity(wr_fp));
assign i_wr_credit_valid_parity=wr_vp^valid_parity_flip[3];
assign i_wr_credit_parity=wr_fp^parity_flip[3];

integer cycles=0,checks=0,accepted_req=0,accepted_rd=0,accepted_wr=0;
integer sent_count[0:3],retired_count[0:3];
integer phase[0:2];
integer nw[0:3][0:PORTS-1],nr[0:3][0:PORTS-1];
integer rw[0:3][0:PORTS*5-1],rr[0:3][0:PORTS*5-1];
reg [621:0] nq[0:3][0:PORTS-1][0:255];
reg [621:0] rq[0:3][0:PORTS*5-1][0:255];
integer c,p,a,b,n,slot,group;
reg [618:0] payload;
reg [621:0] actual;
reg [3:0] expected_parity_errors;
integer round_index=0,parity_fault_seen=0,phase_divergence=0;
task ck;input condition;input integer id;begin checks=checks+1;if(condition!==1'b1)$fatal(1,"STATION_MISMATCH id=%0d cycle=%0d ports=%0d",id,cycles,PORTS);end endtask
task push_native;input integer ch;input integer port;input [1:0] vc;input pool;input [618:0] data;begin
ck(nw[ch][port]<256,100);nq[ch][port][nw[ch][port]]={pool,vc,data};nw[ch][port]=nw[ch][port]+1;
end endtask
always @(posedge clk) begin
 cycles=cycles+1;
 if(!rstn) begin
  accepted_req=0;accepted_rd=0;accepted_wr=0;
  for(c=0;c<4;c=c+1)begin
   sent_count[c]=0;retired_count[c]=0;
   for(p=0;p<PORTS;p=p+1)begin nw[c][p]=0;nr[c][p]=0;end
   for(a=0;a<PORTS*5;a=a+1)begin rw[c][a]=0;rr[c][a]=0;end
  end
  for(c=0;c<3;c=c+1)phase[c]=-1;
 end else begin
  ck(o_req_candidate_accepted===o_req_valid,101);ck((!o_rd_candidate_accepted||o_rd_valid) && (o_wr_candidate_accepted===o_wr_valid),102);
  ck(!o_rd_candidate_error,103);
  ck(o_req_payload===sent_payload[0][183:0]&&o_rd_payload===sent_payload[2],104);
  ck(o_req_valid_parity===o_req_valid&&o_data_valid_parity===o_data_valid&&o_rd_valid_parity===o_rd_valid&&o_wr_valid_parity===o_wr_valid,105);
  ck(o_req_auth_tag_parity===(^o_req_auth_tag)&&o_req_address_parity===(^o_req_address),106);
  ck(o_req_control_parity===(^{o_req_tag,o_req_length,o_req_attr,o_req_command,o_req_metadata,o_req_vc,o_req_asi,o_req_src,o_req_dst,o_req_port,o_req_num_beats,o_req_pool}),107);
  ck(o_data_fields_parity===(^{o_data_last,o_data_error,o_data_offset,o_data_port,o_data_vc,o_data_pool})&&o_data_byte_enable_parity===(^o_data_byte_enable),108);
  ck(o_rd_auth_tag_parity===(^o_rd_auth_tag)&&o_rd_control_parity===(^{o_rd_type_info,o_rd_tag,o_rd_status,o_rd_offset,o_rd_last,o_rd_num_beats,o_rd_vc,o_rd_src,o_rd_dst,o_rd_port,o_rd_data_error,o_rd_pool}),109);
  ck(o_wr_auth_tag_parity===(^o_wr_auth_tag)&&o_wr_control_parity===(^{o_wr_type_info,o_wr_tag,o_wr_status,o_wr_src,o_wr_dst,o_wr_port,o_wr_vc,o_wr_pool}),194);
  for(integer lane=0;lane<8;lane=lane+1)ck(o_data_parity[lane]===(^o_data_payload[lane*64+:64])&&o_rd_data_parity[lane]===(^o_rd_data[lane*64+:64]),195);
  if(phase[0]>=0&&phase[1]>=0&&phase[2]>=0&&(phase[0]!=phase[1]||phase[1]!=phase[2]))phase_divergence=phase_divergence+1;
  if(o_req_candidate_accepted)begin
   accepted_req=accepted_req+1;
   push_native(0,i_req_candidate_port,i_req_candidate_vc,i_req_candidate_pool,{435'd0,i_req_candidate_request});
   if(i_req_candidate_has_data)for(b=0;b<=i_req_candidate_num_beats;b=b+1)begin
    payload={39'd0,i_req_candidate_data[b*512+:512],i_req_candidate_byte_enable[b*64+:64],b[1:0],(b==i_req_candidate_num_beats),i_req_candidate_error[b]};
    push_native(1,i_req_candidate_port,i_req_candidate_vc,i_req_candidate_data_pools[b],payload);
   end
  end
  if(o_rd_candidate_accepted)begin
   accepted_rd=accepted_rd+1;n=i_rd_candidate_payload[523:522]+1;
   for(b=0;b<n;b=b+1)push_native(2,i_rd_candidate_port,i_rd_candidate_vc,i_rd_candidate_pools[b],i_rd_candidate_payload[b*619+:619]);
  end
  if(o_wr_candidate_accepted)begin accepted_wr=accepted_wr+1;push_native(3,i_wr_candidate_port,i_wr_candidate_vc,i_wr_candidate_pool,{518'd0,i_wr_candidate_payload});end
  for(c=0;c<4;c=c+1)begin
   ck(diagnostic[c]==0,110+c);
   if(sent[c])begin
    p=sent_port[c];ck(p<PORTS,120+c);ck(nr[c][p]<nw[c][p],130+c);
    actual={sent_pool[c],sent_vc[c],sent_payload[c]};ck(actual===nq[c][p][nr[c][p]],140+c);nr[c][p]=nr[c][p]+1;
    a=p*5+(sent_pool[c]?4:sent_vc[c]);ck(rw[c][a]<256,150+c);rq[c][a][rw[c][a]]=actual;rw[c][a]=rw[c][a]+1;sent_count[c]=sent_count[c]+1;
    group=(c<2)?0:c-1;if(phase[group]<0)phase[group]=p;ck(p==phase[group],160+c);
   end
   if(consumer_enable&&head_valid[c])begin
    a=consume_port*5+consume_account;ck(rr[c][a]<rw[c][a],170+c);
    ck({head_pool[c],head_vc[c],head_payload[c]}===rq[c][a][rr[c][a]],180+c);rr[c][a]=rr[c][a]+1;retired_count[c]=retired_count[c]+1;
   end
  end
  for(c=0;c<3;c=c+1)if(phase[c]>=0)phase[c]=(phase[c]+1)%PORTS;
  ck(!(o_req_data_credit_error_sticky||o_rd_credit_error_sticky||o_wr_credit_error_sticky),190);
  expected_parity_errors=valid_parity_flip|(parity_flip&{(|i_wr_credit_valid),(|i_rd_credit_valid),(|i_data_credit_valid),(|i_req_credit_valid)});
  ck(o_credit_parity_error===expected_parity_errors,191);if(expected_parity_errors!=0)parity_fault_seen=parity_fault_seen+1;
  ck(o_credit_valid_parity_error===valid_parity_flip,192);
  ck(o_credit_control_parity_error===(parity_flip&{(|i_wr_credit_valid),(|i_rd_credit_valid),(|i_data_credit_valid),(|i_req_credit_valid)}),207);
  ck(o_credit_integrity_ok===~expected_parity_errors,193);
 end
 if(cycles>20000)$fatal(1,"STATION_TIMEOUT");
end
always @(negedge clk) begin
 if(!rstn)begin consume_port<=0;consume_account<=0;end
 else if(consume_account==4)begin consume_account<=0;consume_port<=(consume_port+1)%PORTS;end
 else consume_account<=consume_account+1;
end
function [511:0] pattern;input integer seed;integer j;begin for(j=0;j<64;j=j+1)pattern[j*8+:8]=(seed*17+j*29)&255;end endfunction
task drive_req;integer k,j,before_count;reg [1:0] number;begin
 for(k=0;k<24;k=k+1)begin
  @(negedge clk);#1;i_req_candidate_valid=1;i_req_candidate_port=k%PORTS;i_req_candidate_vc=(k/PORTS)%4;i_req_candidate_pool=k%2;
  number=k%4;i_req_candidate_has_data=(k%3)!=1;i_req_candidate_num_beats=number;i_req_candidate_data_pools=k%16;
  i_req_candidate_request={2'd2,64'h8000000000000001,10'd777,10'd999,(11'd1024+k[10:0]),(i_req_candidate_has_data?number:2'd0),57'h100000000001000,(i_req_candidate_has_data?6'h28:6'd3),(i_req_candidate_has_data?{number,4'hf}:6'd63),8'ha5,(k[7:0]^round_index[7:0])};
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
  i_wr_candidate_payload={64'h8000000000000001,2'd1,(11'd1800+k[10:0]),4'd0,10'd765,10'd987};before_count=accepted_wr;
  while(accepted_wr==before_count)begin @(posedge clk);#2;end
  @(negedge clk);#1;i_wr_candidate_valid=0;i_wr_candidate_payload=~i_wr_candidate_payload;
 end
end endtask
task drain;integer wait_cycles,all_done;begin
 wait_cycles=0;all_done=0;
 while(!all_done&&wait_cycles<5000)begin
  @(negedge clk);#1;all_done=1;
  for(integer ch=0;ch<4;ch=ch+1)begin
   if(sent_count[ch]!=retired_count[ch]||counts[ch]!=0)all_done=0;
   for(integer pp=0;pp<PORTS;pp=pp+1)if(nw[ch][pp]!=nr[ch][pp])all_done=0;
  end
  wait_cycles=wait_cycles+1;
 end
 ck(all_done,200);
end endtask
initial begin
 for(round_index=0;round_index<2;round_index=round_index+1)begin
 rstn=0;peer_ready=0;consumer_enable=0;parity_flip=0;valid_parity_flip=0;
 repeat(4)@(negedge clk);#1;rstn=1;
 repeat(5)@(negedge clk);#1;peer_ready=1;
 @(negedge clk);#1;parity_flip=15;
 repeat(40)@(negedge clk);#1;parity_flip=0;
 wait((&o_req_init[PORTS-1:0])&&(&o_data_init[PORTS-1:0])&&(&o_rd_init_confirmed[PORTS-1:0])&&(&o_wr_init_confirmed[PORTS-1:0]));
 @(negedge clk);#1;valid_parity_flip=15;
 repeat(2)@(negedge clk);#1;valid_parity_flip=0;
 fork
  drive_req();drive_rd();drive_wr();
  begin repeat(220)@(negedge clk);#1;consumer_enable=1;end
 join
 drain();
 ck(parity_fault_seen>0,203);if(PORTS>1)ck(phase_divergence>0,204);
 ck(accepted_req==24&&accepted_rd==24&&accepted_wr==24,201);
 ck(sent_count[0]==24&&sent_count[1]>24&&sent_count[2]==60&&sent_count[3]==24,202);
 $display("STATION_PASS ports=%0d cap=%0d cycles=%0d checks=%0d req=%0d data=%0d rd=%0d wr=%0d",PORTS,CAP,cycles,checks,sent_count[0],sent_count[1],sent_count[2],sent_count[3]);
 if(round_index==0)begin
  @(negedge clk);#1;consumer_enable=0;
  fork : abandoned_round
   drive_req();drive_rd();drive_wr();
  join_none
  repeat(60)@(negedge clk);#1;
  ck((counts[0]|counts[1]|counts[2]|counts[3])!=0,205);
  $display("STATION_RESET_PENDING req=%0d data=%0d rd=%0d wr=%0d",sent_count[0]-retired_count[0],sent_count[1]-retired_count[1],sent_count[2]-retired_count[2],sent_count[3]-retired_count[3]);
  disable abandoned_round;
  i_req_candidate_valid=0;i_rd_candidate_valid=0;i_wr_candidate_valid=0;rstn=0;
  repeat(4)@(negedge clk);#1;rstn=1;consumer_enable=1;
  repeat(80)@(negedge clk);#1;
  ck(sent_count[0]+sent_count[1]+sent_count[2]+sent_count[3]+retired_count[0]+retired_count[1]+retired_count[2]+retired_count[3]==0,206);
 end
 end
 $finish;
end
endmodule
