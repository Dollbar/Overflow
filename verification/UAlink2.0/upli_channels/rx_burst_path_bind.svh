// Inserted into a snapshot of the production native path TB; no production file is edited.
wire observed_data_valid=o_data_valid;
wire [1:0] observed_data_offset=o_data_offset;
wire observed_data_last=o_data_last;
wire [1:0] observed_data_vc=o_data_vc;
wire [9:0] burst_error,burst_sticky;
wire [PORTS-1:0] burst_active;
wire classified=(o_req_command==6'h03)||(o_req_command==6'h28)||(o_req_command==6'h29);
wire carries_data=(o_req_command==6'h28)||(o_req_command==6'h29);
upli_native_rx_burst_monitor #(.C_NUM_PORTS(PORTS)) burst_monitor(
.i_clk(clk),.i_rstn(rstn),.i_tdm_known(path_tdm_phase_known[0]),.i_tdm_port(path_tdm_expected_port[1:0]),
.i_req_valid(o_req_valid),.i_req_port(o_req_port),.i_req_class_known(classified),.i_req_has_data(carries_data),.i_req_vc(o_req_vc),.i_req_num_beats(o_req_num_beats),
.i_data_valid(observed_data_valid),.i_data_port(o_data_port),.i_data_vc(observed_data_vc),.i_data_offset(observed_data_offset),.i_data_last(observed_data_last),
.o_error(burst_error),.o_error_sticky(burst_sticky),.o_active(burst_active));
integer burst_req_events=0,burst_data_events=0,burst_sampled_edges=0;
always @(posedge clk)begin
 if(rstn)begin
  burst_sampled_edges=burst_sampled_edges+1;
  if(burst_error||burst_sticky)$fatal(1,"BURST_PATH_ERROR ports=%0d error=%h sticky=%h",PORTS,burst_error,burst_sticky);
  if(o_req_valid)burst_req_events=burst_req_events+1;
  if(o_data_valid)burst_data_events=burst_data_events+1;
 end
end
final begin
 $display("BURST_PATH_COUNTS ports=%0d edges=%0d req=%0d data=%0d",PORTS,burst_sampled_edges,burst_req_events,burst_data_events);
end
