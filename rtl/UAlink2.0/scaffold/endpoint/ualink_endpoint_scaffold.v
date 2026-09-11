// Generated structural inventory: every asserted bit is unimplemented.
// Run python3 scripts/materialize_ip_scaffold.py --check; then check_ip_structure.py.
`default_nettype none
module ualink_endpoint_scaffold(
 input wire i_clk,i_rstn,
 output wire [127:0] o_pending_features
);
wire implemented_1;
endpoint_request_admission u_endpoint_request_admission(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_1),.o_error());
assign o_pending_features[1]=!implemented_1;
wire implemented_7;
endpoint_atomic_transport u_endpoint_atomic_transport(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_7),.o_error());
assign o_pending_features[7]=!implemented_7;
wire implemented_13;
endpoint_response_formatter u_endpoint_response_formatter(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_13),.o_error());
assign o_pending_features[13]=!implemented_13;
wire implemented_14;
endpoint_ordering u_endpoint_ordering(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_14),.o_error());
assign o_pending_features[14]=!implemented_14;
wire implemented_15;
endpoint_memory_adapter u_endpoint_memory_adapter(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_15),.o_error());
assign o_pending_features[15]=!implemented_15;
wire implemented_16;
endpoint_message_handler u_endpoint_message_handler(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_16),.o_error());
assign o_pending_features[16]=!implemented_16;
wire implemented_17;
endpoint_completion_sink u_endpoint_completion_sink(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_17),.o_error());
assign o_pending_features[17]=!implemented_17;
wire implemented_18;
upli_station_port u_upli_station_port(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_18),.o_error());
assign o_pending_features[18]=!implemented_18;
wire implemented_19;
upli_request_channel u_upli_request_channel(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_19),.o_error());
assign o_pending_features[19]=!implemented_19;
wire implemented_20;
upli_read_response_channel u_upli_read_response_channel(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_20),.o_error());
assign o_pending_features[20]=!implemented_20;
wire implemented_21;
upli_write_response_channel u_upli_write_response_channel(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_21),.o_error());
assign o_pending_features[21]=!implemented_21;
wire implemented_22;
upli_orig_data_channel u_upli_orig_data_channel(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_22),.o_error());
assign o_pending_features[22]=!implemented_22;
wire implemented_23;
upli_tdm_scheduler u_upli_tdm_scheduler(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_23),.o_error());
assign o_pending_features[23]=!implemented_23;
wire implemented_24;
upli_parity u_upli_parity(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_24),.o_error());
assign o_pending_features[24]=!implemented_24;
wire implemented_25;
tl_port u_tl_port(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_25),.o_error());
assign o_pending_features[25]=!implemented_25;
wire implemented_26;
tl_transaction_demux u_tl_transaction_demux(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_26),.o_error());
assign o_pending_features[26]=!implemented_26;
wire implemented_27;
tl_vc_scheduler u_tl_vc_scheduler(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_27),.o_error());
assign o_pending_features[27]=!implemented_27;
wire implemented_28;
tl_stream_order u_tl_stream_order(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_28),.o_error());
assign o_pending_features[28]=!implemented_28;
wire implemented_29;
tl_request_compress u_tl_request_compress(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_29),.o_error());
assign o_pending_features[29]=!implemented_29;
wire implemented_30;
tl_request_decompress u_tl_request_decompress(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_30),.o_error());
assign o_pending_features[30]=!implemented_30;
wire implemented_31;
tl_response_compress u_tl_response_compress(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_31),.o_error());
assign o_pending_features[31]=!implemented_31;
wire implemented_32;
tl_response_decompress u_tl_response_decompress(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_32),.o_error());
assign o_pending_features[32]=!implemented_32;
wire implemented_33;
tl_address_cache u_tl_address_cache(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_33),.o_error());
assign o_pending_features[33]=!implemented_33;
wire implemented_34;
tl_message_control u_tl_message_control(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_34),.o_error());
assign o_pending_features[34]=!implemented_34;
wire implemented_35;
tl_poison_control u_tl_poison_control(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_35),.o_error());
assign o_pending_features[35]=!implemented_35;
wire implemented_36;
dl_port u_dl_port(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_36),.o_error());
assign o_pending_features[36]=!implemented_36;
wire implemented_37;
dl_tx_framer u_dl_tx_framer(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_37),.o_error());
assign o_pending_features[37]=!implemented_37;
wire implemented_38;
dl_rx_deframer u_dl_rx_deframer(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_38),.o_error());
assign o_pending_features[38]=!implemented_38;
wire implemented_39;
dl_crc_tx u_dl_crc_tx(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_39),.o_error());
assign o_pending_features[39]=!implemented_39;
wire implemented_40;
dl_crc_rx u_dl_crc_rx(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_40),.o_error());
assign o_pending_features[40]=!implemented_40;
wire implemented_41;
dl_link_state u_dl_link_state(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_41),.o_error());
assign o_pending_features[41]=!implemented_41;
wire implemented_42;
dl_watchdog u_dl_watchdog(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_42),.o_error());
assign o_pending_features[42]=!implemented_42;
wire implemented_43;
dl_resiliency u_dl_resiliency(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_43),.o_error());
assign o_pending_features[43]=!implemented_43;
wire implemented_44;
dl_folding u_dl_folding(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_44),.o_error());
assign o_pending_features[44]=!implemented_44;
wire implemented_45;
dl_uart_firmware_adapter u_dl_uart_firmware_adapter(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_45),.o_error());
assign o_pending_features[45]=!implemented_45;
wire implemented_46;
phy_port u_phy_port(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_46),.o_error());
assign o_pending_features[46]=!implemented_46;
wire implemented_47;
rs_rx_calendar_frame u_rs_rx_calendar_frame(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_47),.o_error());
assign o_pending_features[47]=!implemented_47;
wire implemented_48;
rs_rx_block_parser u_rs_rx_block_parser(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_48),.o_error());
assign o_pending_features[48]=!implemented_48;
wire implemented_49;
phy_pcs_tx u_phy_pcs_tx(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_49),.o_error());
assign o_pending_features[49]=!implemented_49;
wire implemented_50;
phy_pcs_rx u_phy_pcs_rx(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_50),.o_error());
assign o_pending_features[50]=!implemented_50;
wire implemented_51;
phy_fec_encode u_phy_fec_encode(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_51),.o_error());
assign o_pending_features[51]=!implemented_51;
wire implemented_52;
phy_fec_decode u_phy_fec_decode(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_52),.o_error());
assign o_pending_features[52]=!implemented_52;
wire implemented_53;
phy_fec_interleave u_phy_fec_interleave(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_53),.o_error());
assign o_pending_features[53]=!implemented_53;
wire implemented_54;
phy_fec_deinterleave u_phy_fec_deinterleave(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_54),.o_error());
assign o_pending_features[54]=!implemented_54;
wire implemented_55;
phy_scrambler_tx u_phy_scrambler_tx(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_55),.o_error());
assign o_pending_features[55]=!implemented_55;
wire implemented_56;
phy_scrambler_rx u_phy_scrambler_rx(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_56),.o_error());
assign o_pending_features[56]=!implemented_56;
wire implemented_57;
phy_lane_align u_phy_lane_align(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_57),.o_error());
assign o_pending_features[57]=!implemented_57;
wire implemented_58;
phy_deskew u_phy_deskew(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_58),.o_error());
assign o_pending_features[58]=!implemented_58;
wire implemented_59;
phy_rate_match u_phy_rate_match(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_59),.o_error());
assign o_pending_features[59]=!implemented_59;
wire implemented_60;
phy_lane_map u_phy_lane_map(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_60),.o_error());
assign o_pending_features[60]=!implemented_60;
wire implemented_61;
phy_mode_control u_phy_mode_control(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_61),.o_error());
assign o_pending_features[61]=!implemented_61;
wire implemented_62;
phy_serdes_adapter u_phy_serdes_adapter(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_62),.o_error());
assign o_pending_features[62]=!implemented_62;
wire implemented_63;
ualink_station u_ualink_station(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_63),.o_error());
assign o_pending_features[63]=!implemented_63;
wire implemented_64;
station_array u_station_array(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_64),.o_error());
assign o_pending_features[64]=!implemented_64;
wire implemented_65;
station_bifurcation u_station_bifurcation(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_65),.o_error());
assign o_pending_features[65]=!implemented_65;
wire implemented_66;
station_port_identity u_station_port_identity(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_66),.o_error());
assign o_pending_features[66]=!implemented_66;
wire implemented_67;
station_rate_controller u_station_rate_controller(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_67),.o_error());
assign o_pending_features[67]=!implemented_67;
wire implemented_68;
tx_pacing u_tx_pacing(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_68),.o_error());
assign o_pending_features[68]=!implemented_68;
wire implemented_69;
inc_request_classifier u_inc_request_classifier(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_69),.o_error());
assign o_pending_features[69]=!implemented_69;
wire implemented_70;
security_core u_security_core(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_70),.o_error());
assign o_pending_features[70]=!implemented_70;
wire implemented_71;
security_request_map u_security_request_map(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_71),.o_error());
assign o_pending_features[71]=!implemented_71;
wire implemented_72;
security_response_map u_security_response_map(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_72),.o_error());
assign o_pending_features[72]=!implemented_72;
wire implemented_73;
aes_core u_aes_core(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_73),.o_error());
assign o_pending_features[73]=!implemented_73;
wire implemented_74;
ghash_core u_ghash_core(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_74),.o_error());
assign o_pending_features[74]=!implemented_74;
wire implemented_75;
gcm_core u_gcm_core(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_75),.o_error());
assign o_pending_features[75]=!implemented_75;
wire implemented_76;
keccak_core u_keccak_core(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_76),.o_error());
assign o_pending_features[76]=!implemented_76;
wire implemented_77;
kmac_core u_kmac_core(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_77),.o_error());
assign o_pending_features[77]=!implemented_77;
wire implemented_78;
pcrc_core u_pcrc_core(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_78),.o_error());
assign o_pending_features[78]=!implemented_78;
wire implemented_79;
security_stream_context u_security_stream_context(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_79),.o_error());
assign o_pending_features[79]=!implemented_79;
wire implemented_80;
security_key_store u_security_key_store(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_80),.o_error());
assign o_pending_features[80]=!implemented_80;
wire implemented_81;
security_key_roll u_security_key_roll(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_81),.o_error());
assign o_pending_features[81]=!implemented_81;
wire implemented_82;
security_counter u_security_counter(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_82),.o_error());
assign o_pending_features[82]=!implemented_82;
wire implemented_83;
security_auth_check u_security_auth_check(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_83),.o_error());
assign o_pending_features[83]=!implemented_83;
wire implemented_84;
security_inc_domain u_security_inc_domain(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_84),.o_error());
assign o_pending_features[84]=!implemented_84;
wire implemented_85;
security_trusted_config u_security_trusted_config(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_85),.o_error());
assign o_pending_features[85]=!implemented_85;
wire implemented_86;
management_csr u_management_csr(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_86),.o_error());
assign o_pending_features[86]=!implemented_86;
wire implemented_87;
csr_decode u_csr_decode(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_87),.o_error());
assign o_pending_features[87]=!implemented_87;
wire implemented_88;
csr_capability u_csr_capability(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_88),.o_error());
assign o_pending_features[88]=!implemented_88;
wire implemented_89;
csr_route_config u_csr_route_config(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_89),.o_error());
assign o_pending_features[89]=!implemented_89;
wire implemented_90;
csr_security_config u_csr_security_config(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_90),.o_error());
assign o_pending_features[90]=!implemented_90;
wire implemented_91;
telemetry_counters u_telemetry_counters(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_91),.o_error());
assign o_pending_features[91]=!implemented_91;
wire implemented_92;
interrupt_controller u_interrupt_controller(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_92),.o_error());
assign o_pending_features[92]=!implemented_92;
wire implemented_93;
error_snapshot u_error_snapshot(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_93),.o_error());
assign o_pending_features[93]=!implemented_93;
wire implemented_94;
management_agent_bridge u_management_agent_bridge(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_94),.o_error());
assign o_pending_features[94]=!implemented_94;
wire implemented_95;
ras_controller u_ras_controller(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_95),.o_error());
assign o_pending_features[95]=!implemented_95;
wire implemented_96;
ras_error_classify u_ras_error_classify(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_96),.o_error());
assign o_pending_features[96]=!implemented_96;
wire implemented_97;
ras_tl_drop u_ras_tl_drop(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_97),.o_error());
assign o_pending_features[97]=!implemented_97;
wire implemented_98;
ras_originator_isolation u_ras_originator_isolation(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_98),.o_error());
assign o_pending_features[98]=!implemented_98;
wire implemented_99;
ras_completion_timeout u_ras_completion_timeout(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_99),.o_error());
assign o_pending_features[99]=!implemented_99;
wire implemented_100;
ras_link_recovery u_ras_link_recovery(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_100),.o_error());
assign o_pending_features[100]=!implemented_100;
wire implemented_101;
ras_cper_bridge u_ras_cper_bridge(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_101),.o_error());
assign o_pending_features[101]=!implemented_101;
wire implemented_102;
clock_reset_manager u_clock_reset_manager(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_102),.o_error());
assign o_pending_features[102]=!implemented_102;
wire implemented_103;
reset_domain_controller u_reset_domain_controller(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_103),.o_error());
assign o_pending_features[103]=!implemented_103;
wire implemented_104;
clock_platform_adapter u_clock_platform_adapter(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_104),.o_error());
assign o_pending_features[104]=!implemented_104;
wire implemented_105;
cdc_event_bridge u_cdc_event_bridge(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_105),.o_error());
assign o_pending_features[105]=!implemented_105;
wire implemented_106;
cdc_data_fifo u_cdc_data_fifo(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_106),.o_error());
assign o_pending_features[106]=!implemented_106;
wire implemented_107;
sram_ecc_adapter u_sram_ecc_adapter(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_107),.o_error());
assign o_pending_features[107]=!implemented_107;
wire implemented_108;
diagnostic_event_mux u_diagnostic_event_mux(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_108),.o_error());
assign o_pending_features[108]=!implemented_108;
assign o_pending_features[0]=1'b0;
assign o_pending_features[2]=1'b0;
assign o_pending_features[3]=1'b0;
assign o_pending_features[4]=1'b0;
assign o_pending_features[5]=1'b0;
assign o_pending_features[6]=1'b0;
assign o_pending_features[8]=1'b0;
assign o_pending_features[9]=1'b0;
assign o_pending_features[10]=1'b0;
assign o_pending_features[11]=1'b0;
assign o_pending_features[12]=1'b0;
assign o_pending_features[109]=1'b0;
assign o_pending_features[110]=1'b0;
assign o_pending_features[111]=1'b0;
assign o_pending_features[112]=1'b0;
assign o_pending_features[113]=1'b0;
assign o_pending_features[114]=1'b0;
assign o_pending_features[115]=1'b0;
assign o_pending_features[116]=1'b0;
assign o_pending_features[117]=1'b0;
assign o_pending_features[118]=1'b0;
assign o_pending_features[119]=1'b0;
assign o_pending_features[120]=1'b0;
assign o_pending_features[121]=1'b0;
assign o_pending_features[122]=1'b0;
assign o_pending_features[123]=1'b0;
assign o_pending_features[124]=1'b0;
assign o_pending_features[125]=1'b0;
assign o_pending_features[126]=1'b0;
assign o_pending_features[127]=1'b0;
endmodule
`default_nettype wire
