`timescale 1ns/1ps
`default_nettype none
// Destination Egress数组：每个Group×Tile独立实例化多Port出口，保持Group/Tile并行且不形成全局ready链。
// opaque token仅在最终Port valid&&ready退休沿产生一次release，release索引与Group×Tile×local Port一致。
module switch_destination_egress_array #(
 parameter integer C_NUM_GROUPS=8,C_TILES=4,C_BANK_LANES=8,C_PORTS_PER_TILE=32,
 parameter integer C_NUM_CLASSES=4,C_NUM_VC=4,C_DATA_WIDTH=256,C_META_WIDTH=128,
 parameter integer C_PORT_WIDTH=5,C_CLASS_WIDTH=2,C_VC_WIDTH=2,C_ACCOUNT_WIDTH=15,C_TOKEN_WIDTH=23,
 parameter integer C_QUEUE_DEPTH=4,C_COUNT_WIDTH=3,C_GLOBAL_PORT_WIDTH=10,
 parameter integer C_LANES_PER_GROUP=C_TILES*C_BANK_LANES,
 parameter integer C_TOTAL_TILES=C_NUM_GROUPS*C_TILES,
 parameter integer C_TOTAL_PORTS=C_TOTAL_TILES*C_PORTS_PER_TILE,
 parameter integer C_RELEASE_PORTS_PER_GROUP=C_TILES*C_PORTS_PER_TILE,
 parameter integer C_PER_PORT_QUEUES=C_NUM_CLASSES*C_NUM_VC,
 parameter integer C_QUEUES_PER_TILE=C_PORTS_PER_TILE*C_PER_PORT_QUEUES
)(
 input wire i_clk,input wire i_rstn,
 input wire [C_NUM_GROUPS*C_LANES_PER_GROUP-1:0] i_valid,
 output wire [C_NUM_GROUPS*C_LANES_PER_GROUP-1:0] o_ready,
 input wire [C_NUM_GROUPS*C_LANES_PER_GROUP*C_DATA_WIDTH-1:0] i_data,
 input wire [C_NUM_GROUPS*C_LANES_PER_GROUP*C_META_WIDTH-1:0] i_meta,
 input wire [C_NUM_GROUPS*C_LANES_PER_GROUP*5-1:0] i_dst_port,
 input wire [C_NUM_GROUPS*C_LANES_PER_GROUP*C_CLASS_WIDTH-1:0] i_class,
 input wire [C_NUM_GROUPS*C_LANES_PER_GROUP*C_VC_WIDTH-1:0] i_original_vc,
 input wire [C_NUM_GROUPS*C_LANES_PER_GROUP-1:0] i_pool,
 input wire [C_NUM_GROUPS*C_LANES_PER_GROUP-1:0] i_sop,input wire [C_NUM_GROUPS*C_LANES_PER_GROUP-1:0] i_eop,
 input wire [C_NUM_GROUPS*C_LANES_PER_GROUP*C_ACCOUNT_WIDTH-1:0] i_account,
 input wire [C_NUM_GROUPS*C_LANES_PER_GROUP*C_TOKEN_WIDTH-1:0] i_token,
 input wire [C_TOTAL_PORTS-1:0] i_port_active,input wire [C_TOTAL_PORTS-1:0] i_upli_credit,
 input wire [C_TOTAL_PORTS-1:0] i_tl_credit,input wire [C_TOTAL_PORTS-1:0] i_link_up,
 output wire [C_TOTAL_PORTS-1:0] o_head_valid,output wire [C_TOTAL_PORTS-1:0] o_valid,input wire [C_TOTAL_PORTS-1:0] i_ready,
 output wire [C_TOTAL_PORTS*C_DATA_WIDTH-1:0] o_data,
 output wire [C_TOTAL_PORTS*C_META_WIDTH-1:0] o_meta,
 output wire [C_TOTAL_PORTS*C_CLASS_WIDTH-1:0] o_class,
 output wire [C_TOTAL_PORTS*C_VC_WIDTH-1:0] o_original_vc,
 output wire [C_TOTAL_PORTS-1:0] o_pool,output wire [C_TOTAL_PORTS-1:0] o_sop,output wire [C_TOTAL_PORTS-1:0] o_eop,
 output wire [C_TOTAL_PORTS*C_GLOBAL_PORT_WIDTH-1:0] o_global_port_id,
 output wire [C_NUM_GROUPS*C_RELEASE_PORTS_PER_GROUP-1:0] o_release_valid,
 input wire [C_NUM_GROUPS*C_RELEASE_PORTS_PER_GROUP-1:0] i_release_ready,
 output wire [C_NUM_GROUPS*C_RELEASE_PORTS_PER_GROUP*C_ACCOUNT_WIDTH-1:0] o_release_account,
 output wire [C_NUM_GROUPS*C_RELEASE_PORTS_PER_GROUP*C_TOKEN_WIDTH-1:0] o_release_token,
 output wire [C_TOTAL_TILES-1:0] o_tile_quiescent,output wire [C_TOTAL_TILES-1:0] o_tile_error,
 output wire o_config_error
);
 // 用逐位常量转换建立10-bit全局PortID，避免依赖SystemVerilog尺寸转换语法。
 function [C_GLOBAL_PORT_WIDTH-1:0] global_port_id_constant;
  input integer value;
  integer bit_index;
  begin
   for(bit_index=0;bit_index<C_GLOBAL_PORT_WIDTH;bit_index=bit_index+1)
    global_port_id_constant[bit_index]=value[bit_index];
  end
 endfunction
 localparam CONFIG_LEGAL=(C_NUM_GROUPS>=1)&&(C_NUM_GROUPS<=8)&&(C_TILES>=1)&&(C_TILES<=4)&&
  (C_BANK_LANES>=1)&&(C_BANK_LANES<=8)&&(C_PORTS_PER_TILE>=1)&&(C_PORTS_PER_TILE<=32)&&
  (C_PORT_WIDTH==5)&&(C_GLOBAL_PORT_WIDTH>=1)&&(C_GLOBAL_PORT_WIDTH<=30)&&
  ((32'd1<<C_GLOBAL_PORT_WIDTH)>=C_TOTAL_PORTS)&&
  (C_TOTAL_PORTS<=1024)&&(C_LANES_PER_GROUP==C_TILES*C_BANK_LANES)&&(C_TOTAL_TILES==C_NUM_GROUPS*C_TILES)&&
  (C_RELEASE_PORTS_PER_GROUP==C_TILES*C_PORTS_PER_TILE);
 assign o_config_error=!CONFIG_LEGAL;
 // 每个最终Port有独立的一项registered release hold；只有下游账本接纳后才释放该项。
 reg [C_TOTAL_PORTS-1:0] release_valid_q;
 reg [C_TOTAL_PORTS*C_ACCOUNT_WIDTH-1:0] release_account_q;
 reg [C_TOTAL_PORTS*C_TOKEN_WIDTH-1:0] release_token_q;
 wire [C_TOTAL_PORTS-1:0] child_release_valid;
 wire [C_TOTAL_PORTS*C_ACCOUNT_WIDTH-1:0] child_release_account;
 wire [C_TOTAL_PORTS*C_TOKEN_WIDTH-1:0] child_release_token;
 wire [C_TOTAL_PORTS-1:0] child_head_valid,child_port_valid;
 // 仅registered hold空闲时允许下一flit成为对外有效传输；不让release ready组合控制valid。
 wire [C_TOTAL_PORTS-1:0] release_capacity=~release_valid_q;
 assign o_valid=child_port_valid&release_capacity;
 assign o_head_valid=child_head_valid&release_capacity;
 assign o_release_valid=release_valid_q;
 assign o_release_account=release_account_q;
 assign o_release_token=release_token_q;
 genvar group_index,tile_index,lane_index,port_index;
 generate for(group_index=0;group_index<C_NUM_GROUPS;group_index=group_index+1)begin:g_group
  for(tile_index=0;tile_index<C_TILES;tile_index=tile_index+1)begin:g_tile
   localparam integer TILE_FLAT=group_index*C_TILES+tile_index;
   localparam integer LANE_BASE=group_index*C_LANES_PER_GROUP+tile_index*C_BANK_LANES;
   localparam integer PORT_BASE=TILE_FLAT*C_PORTS_PER_TILE;
   wire [C_BANK_LANES*C_PORT_WIDTH-1:0] compact_port;
   wire [C_PORTS_PER_TILE*C_PORT_WIDTH-1:0] local_port_unused;
   wire [C_QUEUES_PER_TILE*C_COUNT_WIDTH-1:0] occupancy_unused;
   wire tile_empty_unused,tile_internal_quiescent,tile_illegal,tile_inactive,tile_protocol,tile_config,tile_error;
   for(lane_index=0;lane_index<C_BANK_LANES;lane_index=lane_index+1)begin:g_port_compact
    assign compact_port[lane_index*C_PORT_WIDTH+:C_PORT_WIDTH]=i_dst_port[(LANE_BASE+lane_index)*5+:C_PORT_WIDTH];
   end
   switch_destination_tile_multi_egress #(.C_INGRESS_LANES(C_BANK_LANES),.C_NUM_PORTS(C_PORTS_PER_TILE),
    .C_NUM_CLASSES(C_NUM_CLASSES),.C_NUM_VC(C_NUM_VC),.C_DATA_WIDTH(C_DATA_WIDTH),.C_META_WIDTH(C_META_WIDTH),
    .C_PORT_WIDTH(C_PORT_WIDTH),.C_CLASS_WIDTH(C_CLASS_WIDTH),.C_VC_WIDTH(C_VC_WIDTH),.C_ACCOUNT_WIDTH(C_ACCOUNT_WIDTH),
    .C_TOKEN_WIDTH(C_TOKEN_WIDTH),.C_QUEUE_DEPTH(C_QUEUE_DEPTH),.C_COUNT_WIDTH(C_COUNT_WIDTH),
    .C_PER_PORT_QUEUES(C_PER_PORT_QUEUES),.C_TOTAL_QUEUES(C_QUEUES_PER_TILE))u_egress(
    .i_clk(i_clk),.i_rstn(i_rstn),.i_valid(i_valid[LANE_BASE+:C_BANK_LANES]),.o_ready(o_ready[LANE_BASE+:C_BANK_LANES]),
    .i_data(i_data[LANE_BASE*C_DATA_WIDTH+:C_BANK_LANES*C_DATA_WIDTH]),
    .i_meta(i_meta[LANE_BASE*C_META_WIDTH+:C_BANK_LANES*C_META_WIDTH]),.i_dst_port(compact_port),
    .i_class(i_class[LANE_BASE*C_CLASS_WIDTH+:C_BANK_LANES*C_CLASS_WIDTH]),
    .i_original_vc(i_original_vc[LANE_BASE*C_VC_WIDTH+:C_BANK_LANES*C_VC_WIDTH]),
    .i_pool(i_pool[LANE_BASE+:C_BANK_LANES]),.i_sop(i_sop[LANE_BASE+:C_BANK_LANES]),.i_eop(i_eop[LANE_BASE+:C_BANK_LANES]),
    .i_credit_account(i_account[LANE_BASE*C_ACCOUNT_WIDTH+:C_BANK_LANES*C_ACCOUNT_WIDTH]),
    .i_credit_token(i_token[LANE_BASE*C_TOKEN_WIDTH+:C_BANK_LANES*C_TOKEN_WIDTH]),
    .i_port_active(i_port_active[PORT_BASE+:C_PORTS_PER_TILE]),.i_upli_credit(i_upli_credit[PORT_BASE+:C_PORTS_PER_TILE]),
    .i_tl_credit(i_tl_credit[PORT_BASE+:C_PORTS_PER_TILE]),.i_link_up(i_link_up[PORT_BASE+:C_PORTS_PER_TILE]),
    .o_head_valid(child_head_valid[PORT_BASE+:C_PORTS_PER_TILE]),.o_valid(child_port_valid[PORT_BASE+:C_PORTS_PER_TILE]),
    .i_ready(i_ready[PORT_BASE+:C_PORTS_PER_TILE]&release_capacity[PORT_BASE+:C_PORTS_PER_TILE]),
    .o_data(o_data[PORT_BASE*C_DATA_WIDTH+:C_PORTS_PER_TILE*C_DATA_WIDTH]),
    .o_meta(o_meta[PORT_BASE*C_META_WIDTH+:C_PORTS_PER_TILE*C_META_WIDTH]),.o_dst_port(local_port_unused),
    .o_class(o_class[PORT_BASE*C_CLASS_WIDTH+:C_PORTS_PER_TILE*C_CLASS_WIDTH]),
    .o_original_vc(o_original_vc[PORT_BASE*C_VC_WIDTH+:C_PORTS_PER_TILE*C_VC_WIDTH]),
    .o_pool(o_pool[PORT_BASE+:C_PORTS_PER_TILE]),.o_sop(o_sop[PORT_BASE+:C_PORTS_PER_TILE]),.o_eop(o_eop[PORT_BASE+:C_PORTS_PER_TILE]),
    .o_release_valid(child_release_valid[PORT_BASE+:C_PORTS_PER_TILE]),
    .o_release_account(child_release_account[PORT_BASE*C_ACCOUNT_WIDTH+:C_PORTS_PER_TILE*C_ACCOUNT_WIDTH]),
    .o_release_token(child_release_token[PORT_BASE*C_TOKEN_WIDTH+:C_PORTS_PER_TILE*C_TOKEN_WIDTH]),
    .o_queue_occupancy(occupancy_unused),.o_empty(tile_empty_unused),.o_quiescent(tile_internal_quiescent),
    .o_illegal_input_error(tile_illegal),.o_inactive_dst_error(tile_inactive),.o_protocol_error(tile_protocol),
    .o_config_error(tile_config),.o_error(tile_error));
   wire ignored_status=^{local_port_unused,occupancy_unused,tile_empty_unused,tile_illegal,tile_inactive,tile_protocol,tile_config};
   // Tile内仍有待归还token时禁止全Fabric supervisor观察到quiescent。
   assign o_tile_quiescent[TILE_FLAT]=tile_internal_quiescent&
    !(|release_valid_q[PORT_BASE+:C_PORTS_PER_TILE]);
   assign o_tile_error[TILE_FLAT]=tile_error|o_config_error|(ignored_status&1'b0);
   for(port_index=0;port_index<C_PORTS_PER_TILE;port_index=port_index+1)begin:g_global_id
    localparam [C_GLOBAL_PORT_WIDTH-1:0] GLOBAL_ID=global_port_id_constant(PORT_BASE+port_index);
    assign o_global_port_id[(PORT_BASE+port_index)*C_GLOBAL_PORT_WIDTH+:C_GLOBAL_PORT_WIDTH]=GLOBAL_ID;
   end
  end
 end endgenerate
 // 空hold允许先退休再等待账本；满hold先完成归还，下一周期才允许后续Port退休。
 integer release_index;
 always @(posedge i_clk) begin
  if(!i_rstn) begin
   release_valid_q<={C_TOTAL_PORTS{1'b0}};
   release_account_q<={(C_TOTAL_PORTS*C_ACCOUNT_WIDTH){1'b0}};
   release_token_q<={(C_TOTAL_PORTS*C_TOKEN_WIDTH){1'b0}};
  end else begin
   for(release_index=0;release_index<C_TOTAL_PORTS;release_index=release_index+1) begin
    case({child_release_valid[release_index],release_valid_q[release_index]&i_release_ready[release_index]})
     2'b10:begin
      release_valid_q[release_index]<=1'b1;
      release_account_q[release_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]<=child_release_account[release_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH];
      release_token_q[release_index*C_TOKEN_WIDTH+:C_TOKEN_WIDTH]<=child_release_token[release_index*C_TOKEN_WIDTH+:C_TOKEN_WIDTH];
     end
     2'b01:release_valid_q[release_index]<=1'b0;
     2'b11:begin
      release_valid_q[release_index]<=1'b1;
      release_account_q[release_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH]<=child_release_account[release_index*C_ACCOUNT_WIDTH+:C_ACCOUNT_WIDTH];
      release_token_q[release_index*C_TOKEN_WIDTH+:C_TOKEN_WIDTH]<=child_release_token[release_index*C_TOKEN_WIDTH+:C_TOKEN_WIDTH];
     end
     default:release_valid_q[release_index]<=release_valid_q[release_index];
    endcase
   end
  end
 end
endmodule
`default_nettype wire
