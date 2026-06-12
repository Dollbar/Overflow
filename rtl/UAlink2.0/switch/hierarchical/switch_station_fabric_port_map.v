`timescale 1ns/1ps
`default_nettype none
// Station四个stable slot到分层Fabric端口的纯组合身份映射。
// 本模块不拥有route table，也不把link-up当成信用；只生成稳定GlobalPort和active资格。
module switch_station_fabric_port_map #(
 parameter integer C_NUM_STATIONS=256,
 parameter integer C_NUM_GROUPS=8,
 parameter integer C_TILES_PER_GROUP=4,
 parameter integer C_PORTS_PER_TILE=32,
 parameter integer C_PORTS=C_NUM_STATIONS*4
)(
 input wire [C_NUM_STATIONS*2-1:0] i_station_active_mode,
 input wire [C_PORTS-1:0] i_station_active_mask,
 input wire [C_PORTS-1:0] i_link_up,
 output wire [C_PORTS-1:0] o_port_active,
 output wire [C_PORTS*10-1:0] o_global_port_id,
 output wire [C_PORTS*3-1:0] o_group_id,
 output wire [C_PORTS*2-1:0] o_tile_id,
 output wire [C_PORTS*5-1:0] o_local_port,
 output wire [C_PORTS*8-1:0] o_station_id,
 output wire [C_PORTS*4-1:0] o_lane_mask,
 output wire [C_PORTS*3-1:0] o_service_units,
 output wire o_config_error,
 output wire o_identity_error
);
 localparam CONFIG_LEGAL=(C_NUM_STATIONS>=1)&&(C_NUM_STATIONS<=256)&&
  (C_NUM_GROUPS>=1)&&(C_NUM_GROUPS<=8)&&
  (C_TILES_PER_GROUP>=1)&&(C_TILES_PER_GROUP<=4)&&
  (C_PORTS_PER_TILE>=1)&&(C_PORTS_PER_TILE<=32)&&
  (C_PORTS==C_NUM_STATIONS*4)&&
  (C_PORTS==C_NUM_GROUPS*C_TILES_PER_GROUP*C_PORTS_PER_TILE);
 wire [C_NUM_STATIONS-1:0] station_identity_error;
 assign o_config_error=!CONFIG_LEGAL;
 assign o_identity_error=!CONFIG_LEGAL||(|station_identity_error);

 genvar station_index;
 genvar slot_index;
 generate
  if(!CONFIG_LEGAL)begin:g_invalid_configuration
   switch_station_fabric_port_map_parameters_invalid Invalid_Inst();
  end
  for(station_index=0;station_index<C_NUM_STATIONS;station_index=station_index+1)begin:g_station
   wire [1:0] station_mode=i_station_active_mode[station_index*2+:2];
   wire mode_legal=(station_mode!=2'd3);
   wire [3:0] expected_active_mask=(station_mode==2'd0)?4'b0001:
    (station_mode==2'd1)?4'b0101:(station_mode==2'd2)?4'b1111:4'b0000;
   assign station_identity_error[station_index]=!mode_legal||
    (i_station_active_mask[station_index*4+:4]!=expected_active_mask);
   for(slot_index=0;slot_index<4;slot_index=slot_index+1)begin:g_slot
    localparam integer PORT_INDEX=station_index*4+slot_index;
    localparam integer PORTS_PER_GROUP=C_TILES_PER_GROUP*C_PORTS_PER_TILE;
    localparam integer GROUP_VALUE=PORT_INDEX/PORTS_PER_GROUP;
    localparam integer TILE_VALUE=(PORT_INDEX/C_PORTS_PER_TILE)%C_TILES_PER_GROUP;
    localparam integer LOCAL_VALUE=PORT_INDEX%C_PORTS_PER_TILE;
    wire slot_expected_active=expected_active_mask[slot_index];
    wire [3:0] slot_lane_mask=(station_mode==2'd0)?
     ((slot_index==0)?4'b1111:4'b0000):
     (station_mode==2'd1)?
     ((slot_index==0)?4'b0011:((slot_index==2)?4'b1100:4'b0000)):
     (station_mode==2'd2)?(4'b0001<<slot_index):4'b0000;
    wire [2:0] slot_service_units=(station_mode==2'd0)?
     ((slot_index==0)?3'd4:3'd0):
     (station_mode==2'd1)?
     (((slot_index==0)||(slot_index==2))?3'd2:3'd0):
     (station_mode==2'd2)?3'd1:3'd0;
    assign o_port_active[PORT_INDEX]=CONFIG_LEGAL&&mode_legal&&slot_expected_active&&
     i_station_active_mask[PORT_INDEX]&&i_link_up[PORT_INDEX];
    assign o_group_id[PORT_INDEX*3+:3]=GROUP_VALUE[2:0];
    assign o_tile_id[PORT_INDEX*2+:2]=TILE_VALUE[1:0];
    assign o_local_port[PORT_INDEX*5+:5]=LOCAL_VALUE[4:0];
    assign o_global_port_id[PORT_INDEX*10+:10]={GROUP_VALUE[2:0],TILE_VALUE[1:0],LOCAL_VALUE[4:0]};
    assign o_station_id[PORT_INDEX*8+:8]=station_index[7:0];
    assign o_lane_mask[PORT_INDEX*4+:4]=slot_lane_mask;
    assign o_service_units[PORT_INDEX*3+:3]=slot_service_units;
   end
  end
 endgenerate
endmodule
`default_nettype wire
