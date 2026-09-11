// Generated structural inventory: every asserted bit is unimplemented.
// Run python3 scripts/materialize_ip_scaffold.py --check; then check_ip_structure.py.
`default_nettype none
module ualink_switch_scaffold(
 input wire i_clk,i_rstn,
 output wire [127:0] o_pending_features
);
wire implemented_0;
upli_station_port u_upli_station_port(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_0),.o_error());
assign o_pending_features[0]=!implemented_0;
wire implemented_5;
upli_tdm_scheduler u_upli_tdm_scheduler(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_5),.o_error());
assign o_pending_features[5]=!implemented_5;
wire implemented_7;
tl_port u_tl_port(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_7),.o_error());
assign o_pending_features[7]=!implemented_7;
wire implemented_8;
tl_transaction_demux u_tl_transaction_demux(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_8),.o_error());
assign o_pending_features[8]=!implemented_8;
wire implemented_9;
tl_vc_scheduler u_tl_vc_scheduler(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_9),.o_error());
assign o_pending_features[9]=!implemented_9;
wire implemented_10;
tl_stream_order u_tl_stream_order(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_10),.o_error());
assign o_pending_features[10]=!implemented_10;
wire implemented_11;
tl_request_compress u_tl_request_compress(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_11),.o_error());
assign o_pending_features[11]=!implemented_11;
wire implemented_12;
tl_request_decompress u_tl_request_decompress(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_12),.o_error());
assign o_pending_features[12]=!implemented_12;
wire implemented_13;
tl_response_compress u_tl_response_compress(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_13),.o_error());
assign o_pending_features[13]=!implemented_13;
wire implemented_14;
tl_response_decompress u_tl_response_decompress(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_14),.o_error());
assign o_pending_features[14]=!implemented_14;
wire implemented_15;
tl_address_cache u_tl_address_cache(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_15),.o_error());
assign o_pending_features[15]=!implemented_15;
wire implemented_16;
tl_message_control u_tl_message_control(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_16),.o_error());
assign o_pending_features[16]=!implemented_16;
wire implemented_17;
tl_poison_control u_tl_poison_control(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_17),.o_error());
assign o_pending_features[17]=!implemented_17;
wire implemented_18;
dl_port u_dl_port(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_18),.o_error());
assign o_pending_features[18]=!implemented_18;
wire implemented_19;
dl_tx_framer u_dl_tx_framer(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_19),.o_error());
assign o_pending_features[19]=!implemented_19;
wire implemented_20;
dl_rx_deframer u_dl_rx_deframer(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_20),.o_error());
assign o_pending_features[20]=!implemented_20;
wire implemented_21;
dl_crc_tx u_dl_crc_tx(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_21),.o_error());
assign o_pending_features[21]=!implemented_21;
wire implemented_22;
dl_crc_rx u_dl_crc_rx(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_22),.o_error());
assign o_pending_features[22]=!implemented_22;
wire implemented_23;
dl_link_state u_dl_link_state(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_23),.o_error());
assign o_pending_features[23]=!implemented_23;
wire implemented_24;
dl_watchdog u_dl_watchdog(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_24),.o_error());
assign o_pending_features[24]=!implemented_24;
wire implemented_25;
dl_resiliency u_dl_resiliency(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_25),.o_error());
assign o_pending_features[25]=!implemented_25;
wire implemented_26;
dl_folding u_dl_folding(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_26),.o_error());
assign o_pending_features[26]=!implemented_26;
wire implemented_27;
dl_uart_firmware_adapter u_dl_uart_firmware_adapter(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_27),.o_error());
assign o_pending_features[27]=!implemented_27;
wire implemented_28;
phy_port u_phy_port(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_28),.o_error());
assign o_pending_features[28]=!implemented_28;
wire implemented_29;
rs_rx_calendar_frame u_rs_rx_calendar_frame(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_29),.o_error());
assign o_pending_features[29]=!implemented_29;
wire implemented_30;
rs_rx_block_parser u_rs_rx_block_parser(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_30),.o_error());
assign o_pending_features[30]=!implemented_30;
wire implemented_31;
phy_pcs_tx u_phy_pcs_tx(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_31),.o_error());
assign o_pending_features[31]=!implemented_31;
wire implemented_32;
phy_pcs_rx u_phy_pcs_rx(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_32),.o_error());
assign o_pending_features[32]=!implemented_32;
wire implemented_33;
phy_fec_encode u_phy_fec_encode(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_33),.o_error());
assign o_pending_features[33]=!implemented_33;
wire implemented_34;
phy_fec_decode u_phy_fec_decode(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_34),.o_error());
assign o_pending_features[34]=!implemented_34;
wire implemented_35;
phy_fec_interleave u_phy_fec_interleave(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_35),.o_error());
assign o_pending_features[35]=!implemented_35;
wire implemented_36;
phy_fec_deinterleave u_phy_fec_deinterleave(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_36),.o_error());
assign o_pending_features[36]=!implemented_36;
wire implemented_37;
phy_scrambler_tx u_phy_scrambler_tx(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_37),.o_error());
assign o_pending_features[37]=!implemented_37;
wire implemented_38;
phy_scrambler_rx u_phy_scrambler_rx(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_38),.o_error());
assign o_pending_features[38]=!implemented_38;
wire implemented_39;
phy_lane_align u_phy_lane_align(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_39),.o_error());
assign o_pending_features[39]=!implemented_39;
wire implemented_40;
phy_deskew u_phy_deskew(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_40),.o_error());
assign o_pending_features[40]=!implemented_40;
wire implemented_41;
phy_rate_match u_phy_rate_match(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_41),.o_error());
assign o_pending_features[41]=!implemented_41;
wire implemented_42;
phy_lane_map u_phy_lane_map(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_42),.o_error());
assign o_pending_features[42]=!implemented_42;
wire implemented_43;
phy_mode_control u_phy_mode_control(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_43),.o_error());
assign o_pending_features[43]=!implemented_43;
wire implemented_44;
phy_serdes_adapter u_phy_serdes_adapter(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_44),.o_error());
assign o_pending_features[44]=!implemented_44;
wire implemented_45;
ualink_station u_ualink_station(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_45),.o_error());
assign o_pending_features[45]=!implemented_45;
wire implemented_46;
station_array u_station_array(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_46),.o_error());
assign o_pending_features[46]=!implemented_46;
wire implemented_47;
station_bifurcation u_station_bifurcation(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_47),.o_error());
assign o_pending_features[47]=!implemented_47;
wire implemented_48;
station_port_identity u_station_port_identity(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_48),.o_error());
assign o_pending_features[48]=!implemented_48;
wire implemented_49;
station_rate_controller u_station_rate_controller(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_49),.o_error());
assign o_pending_features[49]=!implemented_49;
wire implemented_50;
tx_pacing u_tx_pacing(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_50),.o_error());
assign o_pending_features[50]=!implemented_50;
wire implemented_51;
switch_core u_switch_core(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_51),.o_error());
assign o_pending_features[51]=!implemented_51;
wire implemented_52;
switch_ingress u_switch_ingress(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_52),.o_error());
assign o_pending_features[52]=!implemented_52;
wire implemented_55;
switch_egress_vc_queues u_switch_egress_vc_queues(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_55),.o_error());
assign o_pending_features[55]=!implemented_55;
wire implemented_58;
switch_egress_repack u_switch_egress_repack(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_58),.o_error());
assign o_pending_features[58]=!implemented_58;
wire implemented_59;
switch_vpod_filter u_switch_vpod_filter(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_59),.o_error());
assign o_pending_features[59]=!implemented_59;
wire implemented_60;
switch_ordering u_switch_ordering(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_60),.o_error());
assign o_pending_features[60]=!implemented_60;
wire implemented_61;
switch_multicast u_switch_multicast(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_61),.o_error());
assign o_pending_features[61]=!implemented_61;
wire implemented_62;
switch_multiplane u_switch_multiplane(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_62),.o_error());
assign o_pending_features[62]=!implemented_62;
wire implemented_63;
switch_port_state u_switch_port_state(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_63),.o_error());
assign o_pending_features[63]=!implemented_63;
wire implemented_64;
switch_uturn u_switch_uturn(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_64),.o_error());
assign o_pending_features[64]=!implemented_64;
wire implemented_66;
inc_core u_inc_core(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_66),.o_error());
assign o_pending_features[66]=!implemented_66;
wire implemented_67;
inc_request_classifier u_inc_request_classifier(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_67),.o_error());
assign o_pending_features[67]=!implemented_67;
wire implemented_68;
inc_group_table u_inc_group_table(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_68),.o_error());
assign o_pending_features[68]=!implemented_68;
wire implemented_69;
inc_membership_tracker u_inc_membership_tracker(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_69),.o_error());
assign o_pending_features[69]=!implemented_69;
wire implemented_70;
inc_primitive_dispatch u_inc_primitive_dispatch(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_70),.o_error());
assign o_pending_features[70]=!implemented_70;
wire implemented_71;
inc_multicast_engine u_inc_multicast_engine(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_71),.o_error());
assign o_pending_features[71]=!implemented_71;
wire implemented_72;
inc_reduction_context u_inc_reduction_context(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_72),.o_error());
assign o_pending_features[72]=!implemented_72;
wire implemented_73;
inc_response_reduce u_inc_response_reduce(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_73),.o_error());
assign o_pending_features[73]=!implemented_73;
wire implemented_74;
inc_block_control u_inc_block_control(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_74),.o_error());
assign o_pending_features[74]=!implemented_74;
wire implemented_75;
inc_block_queue u_inc_block_queue(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_75),.o_error());
assign o_pending_features[75]=!implemented_75;
wire implemented_76;
inc_block_descriptor u_inc_block_descriptor(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_76),.o_error());
assign o_pending_features[76]=!implemented_76;
wire implemented_77;
inc_block_address u_inc_block_address(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_77),.o_error());
assign o_pending_features[77]=!implemented_77;
wire implemented_78;
inc_block_tag_allocator u_inc_block_tag_allocator(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_78),.o_error());
assign o_pending_features[78]=!implemented_78;
wire implemented_79;
inc_block_status_writer u_inc_block_status_writer(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_79),.o_error());
assign o_pending_features[79]=!implemented_79;
wire implemented_80;
inc_block_drain u_inc_block_drain(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_80),.o_error());
assign o_pending_features[80]=!implemented_80;
wire implemented_81;
inc_numeric_dispatch u_inc_numeric_dispatch(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_81),.o_error());
assign o_pending_features[81]=!implemented_81;
wire implemented_82;
inc_integer_alu u_inc_integer_alu(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_82),.o_error());
assign o_pending_features[82]=!implemented_82;
wire implemented_83;
inc_fp_alu u_inc_fp_alu(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_83),.o_error());
assign o_pending_features[83]=!implemented_83;
wire implemented_84;
inc_rounding u_inc_rounding(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_84),.o_error());
assign o_pending_features[84]=!implemented_84;
wire implemented_85;
inc_widen_convert u_inc_widen_convert(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_85),.o_error());
assign o_pending_features[85]=!implemented_85;
wire implemented_86;
inc_deterministic_reduce u_inc_deterministic_reduce(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_86),.o_error());
assign o_pending_features[86]=!implemented_86;
wire implemented_87;
inc_error_aggregate u_inc_error_aggregate(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_87),.o_error());
assign o_pending_features[87]=!implemented_87;
wire implemented_88;
security_core u_security_core(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_88),.o_error());
assign o_pending_features[88]=!implemented_88;
wire implemented_89;
security_request_map u_security_request_map(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_89),.o_error());
assign o_pending_features[89]=!implemented_89;
wire implemented_90;
security_response_map u_security_response_map(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_90),.o_error());
assign o_pending_features[90]=!implemented_90;
wire implemented_91;
aes_core u_aes_core(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_91),.o_error());
assign o_pending_features[91]=!implemented_91;
wire implemented_92;
ghash_core u_ghash_core(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_92),.o_error());
assign o_pending_features[92]=!implemented_92;
wire implemented_93;
gcm_core u_gcm_core(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_93),.o_error());
assign o_pending_features[93]=!implemented_93;
wire implemented_94;
keccak_core u_keccak_core(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_94),.o_error());
assign o_pending_features[94]=!implemented_94;
wire implemented_95;
kmac_core u_kmac_core(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_95),.o_error());
assign o_pending_features[95]=!implemented_95;
wire implemented_96;
pcrc_core u_pcrc_core(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_96),.o_error());
assign o_pending_features[96]=!implemented_96;
wire implemented_97;
security_stream_context u_security_stream_context(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_97),.o_error());
assign o_pending_features[97]=!implemented_97;
wire implemented_98;
security_key_store u_security_key_store(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_98),.o_error());
assign o_pending_features[98]=!implemented_98;
wire implemented_99;
security_key_roll u_security_key_roll(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_99),.o_error());
assign o_pending_features[99]=!implemented_99;
wire implemented_100;
security_counter u_security_counter(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_100),.o_error());
assign o_pending_features[100]=!implemented_100;
wire implemented_101;
security_auth_check u_security_auth_check(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_101),.o_error());
assign o_pending_features[101]=!implemented_101;
wire implemented_102;
security_inc_domain u_security_inc_domain(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_102),.o_error());
assign o_pending_features[102]=!implemented_102;
wire implemented_103;
security_trusted_config u_security_trusted_config(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_103),.o_error());
assign o_pending_features[103]=!implemented_103;
wire implemented_104;
management_csr u_management_csr(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_104),.o_error());
assign o_pending_features[104]=!implemented_104;
wire implemented_105;
csr_decode u_csr_decode(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_105),.o_error());
assign o_pending_features[105]=!implemented_105;
wire implemented_106;
csr_capability u_csr_capability(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_106),.o_error());
assign o_pending_features[106]=!implemented_106;
wire implemented_107;
csr_route_config u_csr_route_config(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_107),.o_error());
assign o_pending_features[107]=!implemented_107;
wire implemented_108;
csr_security_config u_csr_security_config(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_108),.o_error());
assign o_pending_features[108]=!implemented_108;
wire implemented_109;
telemetry_counters u_telemetry_counters(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_109),.o_error());
assign o_pending_features[109]=!implemented_109;
wire implemented_110;
interrupt_controller u_interrupt_controller(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_110),.o_error());
assign o_pending_features[110]=!implemented_110;
wire implemented_111;
error_snapshot u_error_snapshot(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_111),.o_error());
assign o_pending_features[111]=!implemented_111;
wire implemented_112;
management_agent_bridge u_management_agent_bridge(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_112),.o_error());
assign o_pending_features[112]=!implemented_112;
wire implemented_113;
ras_controller u_ras_controller(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_113),.o_error());
assign o_pending_features[113]=!implemented_113;
wire implemented_114;
ras_error_classify u_ras_error_classify(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_114),.o_error());
assign o_pending_features[114]=!implemented_114;
wire implemented_115;
ras_tl_drop u_ras_tl_drop(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_115),.o_error());
assign o_pending_features[115]=!implemented_115;
wire implemented_116;
ras_originator_isolation u_ras_originator_isolation(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_116),.o_error());
assign o_pending_features[116]=!implemented_116;
wire implemented_117;
ras_completion_timeout u_ras_completion_timeout(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_117),.o_error());
assign o_pending_features[117]=!implemented_117;
wire implemented_118;
ras_link_recovery u_ras_link_recovery(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_118),.o_error());
assign o_pending_features[118]=!implemented_118;
wire implemented_119;
ras_cper_bridge u_ras_cper_bridge(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_119),.o_error());
assign o_pending_features[119]=!implemented_119;
wire implemented_120;
clock_reset_manager u_clock_reset_manager(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_120),.o_error());
assign o_pending_features[120]=!implemented_120;
wire implemented_121;
reset_domain_controller u_reset_domain_controller(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_121),.o_error());
assign o_pending_features[121]=!implemented_121;
wire implemented_122;
clock_platform_adapter u_clock_platform_adapter(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_122),.o_error());
assign o_pending_features[122]=!implemented_122;
wire implemented_123;
cdc_event_bridge u_cdc_event_bridge(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_123),.o_error());
assign o_pending_features[123]=!implemented_123;
wire implemented_124;
cdc_data_fifo u_cdc_data_fifo(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_124),.o_error());
assign o_pending_features[124]=!implemented_124;
wire implemented_125;
sram_ecc_adapter u_sram_ecc_adapter(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_125),.o_error());
assign o_pending_features[125]=!implemented_125;
wire implemented_126;
diagnostic_event_mux u_diagnostic_event_mux(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_enable(1'b0),.i_valid(1'b0),
 .i_data(512'd0),.i_meta(128'd0),
 .o_ready(),.o_valid(),.o_data(),.o_meta(),
 .o_implemented(implemented_126),.o_error());
assign o_pending_features[126]=!implemented_126;
assign o_pending_features[1]=1'b0;
assign o_pending_features[2]=1'b0;
assign o_pending_features[3]=1'b0;
assign o_pending_features[4]=1'b0;
assign o_pending_features[6]=1'b0;
assign o_pending_features[53]=1'b0;
assign o_pending_features[54]=1'b0;
assign o_pending_features[56]=1'b0;
assign o_pending_features[57]=1'b0;
assign o_pending_features[65]=1'b0;
assign o_pending_features[127]=1'b0;
endmodule
`default_nettype wire
