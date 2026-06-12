`timescale 1ns/1ps
`default_nettype none
// Unified local/remote requester credit stage. The default backend is the
// resource-banked physical-slot ledger; the legacy matrix remains selectable
// only for semantic equivalence and historical regression.
// One shared ledger owns every destination resource; callers must map local and Core
// paths into this single requester vector and must not instantiate a second ledger.
module switch_destination_credit_stage #(
 parameter integer C_USE_BANKED_LEDGER=1,
 parameter integer C_DATA_WIDTH=512,C_META_WIDTH=128,C_REQUESTERS=64,C_SLICES=4,C_TILES=4,C_DST_LOCALS=32,C_CLASSES=4,C_CAPACITY=4,
 parameter integer C_REQUESTER_WIDTH=6,C_OWNER_WIDTH=7,C_SLICE_WIDTH=2,C_TILE_WIDTH=2,C_LOCAL_WIDTH=5,C_CLASS_WIDTH=2,
 parameter integer C_EPOCH_WIDTH=4,C_GENERATION_WIDTH=16,C_SLOT_WIDTH=13,C_BANK_SLOT_WIDTH=2,C_ACCOUNT_WIDTH=17,C_COUNT_WIDTH=3,
 parameter integer C_RESOURCES=C_SLICES*C_TILES*C_DST_LOCALS*C_CLASSES,parameter integer C_ACCOUNTS=C_REQUESTERS*C_RESOURCES,
 parameter integer C_RELEASE_PORTS=C_SLICES*C_TILES*C_DST_LOCALS,parameter integer C_TOKEN_WIDTH=C_EPOCH_WIDTH+C_GENERATION_WIDTH+C_SLOT_WIDTH
)(input wire i_clk,input wire i_rstn,input wire [C_EPOCH_WIDTH-1:0] i_epoch,
 input wire [C_REQUESTERS-1:0] i_valid,output wire [C_REQUESTERS-1:0] o_ready,
 input wire [C_REQUESTERS*C_DATA_WIDTH-1:0] i_data,input wire [C_REQUESTERS*C_META_WIDTH-1:0] i_meta,
 input wire [C_REQUESTERS*C_SLICE_WIDTH-1:0] i_dst_slice,input wire [C_REQUESTERS*C_TILE_WIDTH-1:0] i_dst_tile,
 input wire [C_REQUESTERS*C_LOCAL_WIDTH-1:0] i_dst_local,input wire [C_REQUESTERS*C_CLASS_WIDTH-1:0] i_class,
 input wire [C_REQUESTERS*C_OWNER_WIDTH-1:0] i_owner_id,input wire [C_REQUESTERS-1:0] i_sop,input wire [C_REQUESTERS-1:0] i_eop,
 output wire [C_REQUESTERS-1:0] o_valid,input wire [C_REQUESTERS-1:0] i_ready,
 output wire [C_REQUESTERS*C_DATA_WIDTH-1:0] o_data,output wire [C_REQUESTERS*C_META_WIDTH-1:0] o_meta,
 output wire [C_REQUESTERS*C_SLICE_WIDTH-1:0] o_dst_slice,output wire [C_REQUESTERS*C_TILE_WIDTH-1:0] o_dst_tile,
 output wire [C_REQUESTERS*C_LOCAL_WIDTH-1:0] o_dst_local,output wire [C_REQUESTERS*C_CLASS_WIDTH-1:0] o_class,
 output wire [C_REQUESTERS*C_OWNER_WIDTH-1:0] o_owner_id,output wire [C_REQUESTERS-1:0] o_sop,output wire [C_REQUESTERS-1:0] o_eop,
 output wire [C_REQUESTERS*C_ACCOUNT_WIDTH-1:0] o_account,output wire [C_REQUESTERS*C_TOKEN_WIDTH-1:0] o_token,
 input wire [C_RELEASE_PORTS-1:0] i_release_valid,output wire [C_RELEASE_PORTS-1:0] o_release_ready,
 input wire [C_RELEASE_PORTS*C_TOKEN_WIDTH-1:0] i_release_token,
 output wire [C_RESOURCES*C_COUNT_WIDTH-1:0] o_free,output wire [C_ACCOUNTS*C_COUNT_WIDTH-1:0] o_issued,output wire [C_ACCOUNTS*C_COUNT_WIDTH-1:0] o_occupied,
 output wire o_quiescent,output wire o_error,
 output wire o_return_malformed_event_level,output wire o_return_duplicate_event_level,
 output wire o_return_stale_event_level,output wire o_return_wrong_port_event_level);
 reg [C_REQUESTERS-1:0] valid_q,arrived_q;reg [C_REQUESTERS*C_DATA_WIDTH-1:0] data_q;reg [C_REQUESTERS*C_META_WIDTH-1:0] meta_q;
 reg [C_REQUESTERS*C_SLICE_WIDTH-1:0] slice_q;reg [C_REQUESTERS*C_TILE_WIDTH-1:0] tile_q;reg [C_REQUESTERS*C_LOCAL_WIDTH-1:0] local_q;reg [C_REQUESTERS*C_CLASS_WIDTH-1:0] class_q;
 reg [C_REQUESTERS*C_OWNER_WIDTH-1:0] owner_q;reg [C_REQUESTERS-1:0] sop_q,eop_q;reg [C_REQUESTERS*C_ACCOUNT_WIDTH-1:0] account_q;reg [C_REQUESTERS*C_TOKEN_WIDTH-1:0] token_q;
 // 每个requester使用issued槽和occupied输出槽。issued token只有在ledger确认
 // arrive后才搬到输出槽；输出stall期间不会阻塞上一槽在同拍drain/refill。
 reg [C_REQUESTERS*C_DATA_WIDTH-1:0] output_data_q;reg [C_REQUESTERS*C_META_WIDTH-1:0] output_meta_q;
 reg [C_REQUESTERS*C_SLICE_WIDTH-1:0] output_slice_q;reg [C_REQUESTERS*C_TILE_WIDTH-1:0] output_tile_q;
 reg [C_REQUESTERS*C_LOCAL_WIDTH-1:0] output_local_q;reg [C_REQUESTERS*C_CLASS_WIDTH-1:0] output_class_q;
 reg [C_REQUESTERS*C_OWNER_WIDTH-1:0] output_owner_q;reg [C_REQUESTERS-1:0] output_sop_q,output_eop_q;
 reg [C_REQUESTERS*C_ACCOUNT_WIDTH-1:0] output_account_q;reg [C_REQUESTERS*C_TOKEN_WIDTH-1:0] output_token_q;
 wire [C_REQUESTERS-1:0] ledger_issue_ready,ledger_arrive_ready,arrive_valid,arrival_fire,drain,output_can_take,can_take,issue_valid,issue_fire;
 wire ledger_quiescent,ledger_error,config_error,issue_overflow,arrival_underflow,duplicate_token,stale_epoch,epoch_change_error,generation_exhausted,malformed_token,conservation_error;
 assign drain=arrived_q&i_ready;assign output_can_take=~arrived_q|drain;
 assign arrive_valid=valid_q&output_can_take;assign arrival_fire=arrive_valid&ledger_arrive_ready;
 assign can_take=~valid_q|arrival_fire;assign issue_valid=i_valid&can_take;
 assign o_ready=ledger_issue_ready&can_take;assign issue_fire=i_valid&o_ready;
 assign o_valid=arrived_q;assign o_data=output_data_q;assign o_meta=output_meta_q;assign o_dst_slice=output_slice_q;assign o_dst_tile=output_tile_q;assign o_dst_local=output_local_q;assign o_class=output_class_q;assign o_owner_id=output_owner_q;assign o_sop=output_sop_q;assign o_eop=output_eop_q;
 // valid=0时account/token保持旧ABI的issued观察值，便于状态观测；只有
 // o_valid=1的occupied值具有传输语义，stall期间始终选择输出槽。
 genvar output_index;
 generate for(output_index=0;output_index<C_REQUESTERS;output_index=output_index+1)begin:g_output_identity
  assign o_account[output_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]=arrived_q[output_index]?
   output_account_q[output_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]:account_q[output_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH];
  assign o_token[output_index*C_TOKEN_WIDTH+:C_TOKEN_WIDTH]=arrived_q[output_index]?
   output_token_q[output_index*C_TOKEN_WIDTH+:C_TOKEN_WIDTH]:token_q[output_index*C_TOKEN_WIDTH+:C_TOKEN_WIDTH];
 end endgenerate
 assign o_quiescent=ledger_quiescent&~(|valid_q)&~(|arrived_q);assign o_error=ledger_error|config_error|issue_overflow|arrival_underflow|duplicate_token|stale_epoch|epoch_change_error|generation_exhausted|malformed_token|conservation_error;
 generate if(C_USE_BANKED_LEDGER!=0)begin:g_banked_ledger
  switch_destination_credit_banked_matrix #(.C_PLANES(C_REQUESTERS),.C_SLICES(C_SLICES),.C_TILES(C_TILES),.C_DST_LOCALS(C_DST_LOCALS),.C_CLASSES(C_CLASSES),.C_CAPACITY(C_CAPACITY),.C_PLANE_WIDTH(C_REQUESTER_WIDTH),.C_SLICE_WIDTH(C_SLICE_WIDTH),.C_TILE_WIDTH(C_TILE_WIDTH),.C_LOCAL_WIDTH(C_LOCAL_WIDTH),.C_CLASS_WIDTH(C_CLASS_WIDTH),.C_EPOCH_WIDTH(C_EPOCH_WIDTH),.C_GENERATION_WIDTH(C_GENERATION_WIDTH),.C_SLOT_WIDTH(C_SLOT_WIDTH),.C_BANK_SLOT_WIDTH(C_BANK_SLOT_WIDTH),.C_ACCOUNT_WIDTH(C_ACCOUNT_WIDTH),.C_COUNT_WIDTH(C_COUNT_WIDTH),.C_RESOURCES(C_RESOURCES),.C_ACCOUNTS(C_ACCOUNTS),.C_RELEASE_PORTS(C_RELEASE_PORTS),.C_TOKEN_WIDTH(C_TOKEN_WIDTH))u_ledger(.i_clk(i_clk),.i_rstn(i_rstn),.i_epoch(i_epoch),.i_issue_valid(issue_valid),.o_issue_ready(ledger_issue_ready),.i_issue_dst_slice(i_dst_slice),.i_issue_dst_tile(i_dst_tile),.i_issue_dst_local(i_dst_local),.i_issue_class(i_class),.o_issue_token(token_issue),.o_issue_account(account_issue),.i_arrive_valid(arrive_valid),.o_arrive_ready(ledger_arrive_ready),.i_arrive_token(token_q),.i_release_valid(i_release_valid),.o_release_ready(o_release_ready),.i_release_token(i_release_token),.o_free(o_free),.o_issued(o_issued),.o_occupied(o_occupied),.o_config_error(config_error),.o_issue_overflow(issue_overflow),.o_arrival_underflow(arrival_underflow),.o_duplicate_token(duplicate_token),.o_stale_epoch(stale_epoch),.o_epoch_change_error(epoch_change_error),.o_generation_exhausted(generation_exhausted),.o_malformed_token(malformed_token),.o_quiescent(ledger_quiescent),.o_conservation_error(conservation_error),.o_return_malformed_event_level(o_return_malformed_event_level),.o_return_duplicate_event_level(o_return_duplicate_event_level),.o_return_stale_event_level(o_return_stale_event_level),.o_return_wrong_port_event_level(o_return_wrong_port_event_level),.o_error(ledger_error));
 end else begin:g_legacy_ledger
  assign o_return_malformed_event_level=1'b0;assign o_return_duplicate_event_level=1'b0;
  assign o_return_stale_event_level=1'b0;assign o_return_wrong_port_event_level=1'b0;
  switch_destination_credit_ledger_matrix #(.C_PLANES(C_REQUESTERS),.C_SLICES(C_SLICES),.C_TILES(C_TILES),.C_DST_LOCALS(C_DST_LOCALS),.C_CLASSES(C_CLASSES),.C_CAPACITY(C_CAPACITY),.C_PLANE_WIDTH(C_REQUESTER_WIDTH),.C_SLICE_WIDTH(C_SLICE_WIDTH),.C_TILE_WIDTH(C_TILE_WIDTH),.C_LOCAL_WIDTH(C_LOCAL_WIDTH),.C_CLASS_WIDTH(C_CLASS_WIDTH),.C_EPOCH_WIDTH(C_EPOCH_WIDTH),.C_GENERATION_WIDTH(C_GENERATION_WIDTH),.C_SLOT_WIDTH(C_SLOT_WIDTH),.C_ACCOUNT_WIDTH(C_ACCOUNT_WIDTH),.C_COUNT_WIDTH(C_COUNT_WIDTH))u_ledger(.i_clk(i_clk),.i_rstn(i_rstn),.i_epoch(i_epoch),.i_issue_valid(issue_valid),.o_issue_ready(ledger_issue_ready),.i_issue_dst_slice(i_dst_slice),.i_issue_dst_tile(i_dst_tile),.i_issue_dst_local(i_dst_local),.i_issue_class(i_class),.o_issue_token(token_issue),.o_issue_account(account_issue),.i_arrive_valid(arrive_valid),.o_arrive_ready(ledger_arrive_ready),.i_arrive_token(token_q),.i_release_valid(i_release_valid),.o_release_ready(o_release_ready),.i_release_token(i_release_token),.o_free(o_free),.o_issued(o_issued),.o_occupied(o_occupied),.o_config_error(config_error),.o_issue_overflow(issue_overflow),.o_arrival_underflow(arrival_underflow),.o_duplicate_token(duplicate_token),.o_stale_epoch(stale_epoch),.o_epoch_change_error(epoch_change_error),.o_generation_exhausted(generation_exhausted),.o_malformed_token(malformed_token),.o_quiescent(ledger_quiescent),.o_conservation_error(conservation_error),.o_error(ledger_error));
 end endgenerate
 wire [C_REQUESTERS*C_TOKEN_WIDTH-1:0] token_issue;wire [C_REQUESTERS*C_ACCOUNT_WIDTH-1:0] account_issue;integer q;
 always @(posedge i_clk)begin if(!i_rstn)begin valid_q<=0;arrived_q<=0;end else for(q=0;q<C_REQUESTERS;q=q+1)begin
  if(issue_fire[q])begin valid_q[q]<=1'b1;data_q[q*C_DATA_WIDTH+:C_DATA_WIDTH]<=i_data[q*C_DATA_WIDTH+:C_DATA_WIDTH];meta_q[q*C_META_WIDTH+:C_META_WIDTH]<=i_meta[q*C_META_WIDTH+:C_META_WIDTH];slice_q[q*C_SLICE_WIDTH+:C_SLICE_WIDTH]<=i_dst_slice[q*C_SLICE_WIDTH+:C_SLICE_WIDTH];tile_q[q*C_TILE_WIDTH+:C_TILE_WIDTH]<=i_dst_tile[q*C_TILE_WIDTH+:C_TILE_WIDTH];local_q[q*C_LOCAL_WIDTH+:C_LOCAL_WIDTH]<=i_dst_local[q*C_LOCAL_WIDTH+:C_LOCAL_WIDTH];class_q[q*C_CLASS_WIDTH+:C_CLASS_WIDTH]<=i_class[q*C_CLASS_WIDTH+:C_CLASS_WIDTH];owner_q[q*C_OWNER_WIDTH+:C_OWNER_WIDTH]<=i_owner_id[q*C_OWNER_WIDTH+:C_OWNER_WIDTH];sop_q[q]<=i_sop[q];eop_q[q]<=i_eop[q];account_q[q*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]<=account_issue[q*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH];token_q[q*C_TOKEN_WIDTH+:C_TOKEN_WIDTH]<=token_issue[q*C_TOKEN_WIDTH+:C_TOKEN_WIDTH];end
  else if(arrival_fire[q])valid_q[q]<=1'b0;
  if(arrival_fire[q])begin arrived_q[q]<=1'b1;output_data_q[q*C_DATA_WIDTH+:C_DATA_WIDTH]<=data_q[q*C_DATA_WIDTH+:C_DATA_WIDTH];output_meta_q[q*C_META_WIDTH+:C_META_WIDTH]<=meta_q[q*C_META_WIDTH+:C_META_WIDTH];output_slice_q[q*C_SLICE_WIDTH+:C_SLICE_WIDTH]<=slice_q[q*C_SLICE_WIDTH+:C_SLICE_WIDTH];output_tile_q[q*C_TILE_WIDTH+:C_TILE_WIDTH]<=tile_q[q*C_TILE_WIDTH+:C_TILE_WIDTH];output_local_q[q*C_LOCAL_WIDTH+:C_LOCAL_WIDTH]<=local_q[q*C_LOCAL_WIDTH+:C_LOCAL_WIDTH];output_class_q[q*C_CLASS_WIDTH+:C_CLASS_WIDTH]<=class_q[q*C_CLASS_WIDTH+:C_CLASS_WIDTH];output_owner_q[q*C_OWNER_WIDTH+:C_OWNER_WIDTH]<=owner_q[q*C_OWNER_WIDTH+:C_OWNER_WIDTH];output_sop_q[q]<=sop_q[q];output_eop_q[q]<=eop_q[q];output_account_q[q*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]<=account_q[q*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH];output_token_q[q*C_TOKEN_WIDTH+:C_TOKEN_WIDTH]<=token_q[q*C_TOKEN_WIDTH+:C_TOKEN_WIDTH];end
  else if(drain[q])arrived_q[q]<=1'b0;
 end end
endmodule
`default_nettype wire
