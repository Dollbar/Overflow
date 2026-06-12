`timescale 1ns/1ps
`default_nettype none
// Switch Fabric窗口CSR：小型配置由本模块拥有，大型Queue/Credit/RAS状态通过单项query接口读取。
module switch_fabric_csr_window #(
 parameter integer C_NUM_STATIONS=256,C_MAX_PORTS=1024,C_PHYSICAL_PORTS=C_MAX_PORTS,C_NUM_TILES=32,C_NUM_GROUPS=8,C_NUM_PLANES=32,
 parameter integer C_ACTIVE_SERVICE_UNITS=1024,C_ROUTE_ENTRIES=1024,C_RESOURCES=4096,C_ACCOUNTS=262144,C_RAS_COUNTERS=32,
 parameter integer C_STATION_INDEX_WIDTH=8,C_PORT_INDEX_WIDTH=10,C_PLANE_INDEX_WIDTH=5,C_ROUTE_INDEX_WIDTH=10,
 parameter integer C_RESOURCE_INDEX_WIDTH=12,C_ACCOUNT_INDEX_WIDTH=18,C_RAS_INDEX_WIDTH=5,
 parameter integer C_RELEASE_PORTS=1024,C_RELEASE_INDEX_WIDTH=10,
 parameter integer C_RELEASE_TIMEOUT_CYCLES=1024,C_RELEASE_TIMER_WIDTH=16
)(
 input wire i_clk,input wire i_rstn,
 input wire i_req_valid,output wire o_req_ready,input wire i_req_write,input wire [15:0] i_req_addr,input wire [31:0] i_req_wdata,
 output reg o_rsp_valid,input wire i_rsp_ready,output reg [31:0] o_rsp_rdata,output reg o_rsp_error,output reg o_rsp_unsupported,
 input wire [1:0] i_station_active_mode,input wire [31:0] i_station_status,input wire [31:0] i_port_status,
 input wire [31:0] i_route_shadow_data,input wire [31:0] i_route_active_data,input wire i_route_pending,
 input wire [31:0] i_identity_shadow_data,input wire [31:0] i_identity_active_data,input wire [31:0] i_plane_status,
 input wire [C_RELEASE_PORTS-1:0] i_release_valid,input wire [C_RELEASE_PORTS-1:0] i_release_ready,
 input wire i_fabric_timeout_error,
 output reg o_station_mode_write,output reg [C_STATION_INDEX_WIDTH-1:0] o_station_index,output reg [1:0] o_station_mode,
 output reg o_port_enable_write,output reg [C_PORT_INDEX_WIDTH-1:0] o_port_index,output reg o_port_enable,
 output reg o_plane_enable_write,output reg [C_PLANE_INDEX_WIDTH-1:0] o_plane_index,output reg o_plane_enable,
 output reg o_route_shadow_write,output reg [C_ROUTE_INDEX_WIDTH-1:0] o_route_index,output reg [31:0] o_route_shadow_wdata,
 output reg o_identity_shadow_write,output reg [C_PORT_INDEX_WIDTH-1:0] o_identity_index,output reg [31:0] o_identity_shadow_wdata,
 output reg o_atomic_commit,
 output wire o_query_valid,input wire i_query_ready,output reg [2:0] o_query_kind,output reg [31:0] o_query_index,input wire [31:0] i_query_data,
 output wire o_release_stall_active,output wire o_release_timeout_sticky,
 output wire [31:0] o_release_stall_cycles,output wire [31:0] o_release_timeout_count,
 output wire [C_RELEASE_INDEX_WIDTH-1:0] o_release_first_port,
 output reg o_release_timeout_w1c,output reg o_release_counter_w1c,
 output reg o_error_sticky,output reg o_unsupported_security
);
 localparam [2:0] Q_RESOURCE_FREE=3'd0,Q_QUEUE_OCCUPANCY=3'd1,Q_ACCOUNT_ISSUED=3'd2,Q_ACCOUNT_OCCUPIED=3'd3,Q_RAS=3'd4;
 reg [1:0] station_mode_mem[0:C_NUM_STATIONS-1];
 reg port_enable_mem[0:C_MAX_PORTS-1];
 reg plane_enable_mem[0:C_NUM_PLANES-1];
 reg query_pending_q;
 reg [C_RESOURCE_INDEX_WIDTH-1:0] resource_index_q;
 reg [C_ACCOUNT_INDEX_WIDTH-1:0] account_index_q;
 reg [C_RAS_INDEX_WIDTH-1:0] ras_index_q;
 reg [31:0] immediate_rdata;
 reg request_legal,request_unsupported,request_is_query;
 reg [2:0] request_query_kind;
 reg [31:0] request_query_index;
 wire release_watchdog_config_error;
 integer reset_index;
 assign o_req_ready=i_rstn&&!query_pending_q&&!o_rsp_valid;
 assign o_query_valid=query_pending_q;

 // 解码先验证索引及权限；未知或Security窗口只产生错误响应，不触发任何命令。
 always @(*) begin
  immediate_rdata=32'd0;request_legal=1'b1;request_unsupported=1'b0;request_is_query=1'b0;
  request_query_kind=3'd0;request_query_index=32'd0;
  case(i_req_addr)
   16'h0000:immediate_rdata=C_NUM_STATIONS;
   16'h0004:immediate_rdata=C_MAX_PORTS;
   16'h0008:immediate_rdata=C_ACTIVE_SERVICE_UNITS;
   16'h000c:immediate_rdata=C_NUM_TILES;
   16'h0010:immediate_rdata=C_NUM_GROUPS;
   16'h0014:immediate_rdata=C_NUM_PLANES;
   16'h1000:immediate_rdata={{(32-C_STATION_INDEX_WIDTH){1'b0}},o_station_index};
   16'h1004:begin immediate_rdata={{30{1'b0}},station_mode_mem[o_station_index]};if(i_req_write&&i_req_wdata[1:0]==2'b11)request_legal=1'b0;end
   16'h1008:immediate_rdata={{30{1'b0}},i_station_active_mode};
   16'h100c:immediate_rdata=i_station_status;
   16'h1100:immediate_rdata={{(32-C_PORT_INDEX_WIDTH){1'b0}},o_port_index};
   16'h1104:immediate_rdata={{31{1'b0}},port_enable_mem[o_port_index]};
   16'h1108:immediate_rdata=i_port_status;
   16'h1200:immediate_rdata={{(32-C_ROUTE_INDEX_WIDTH){1'b0}},o_route_index};
   16'h1204:immediate_rdata=i_route_shadow_data;
   16'h1208:immediate_rdata=i_route_active_data;
   16'h120c:immediate_rdata=32'd0;
   16'h1210:immediate_rdata={{31{1'b0}},i_route_pending};
   16'h1300:immediate_rdata={{(32-C_PORT_INDEX_WIDTH){1'b0}},o_identity_index};
   16'h1304:immediate_rdata=i_identity_shadow_data;
   16'h1308:immediate_rdata=i_identity_active_data;
   16'h1400:immediate_rdata={{(32-C_PLANE_INDEX_WIDTH){1'b0}},o_plane_index};
   16'h1404:immediate_rdata={{31{1'b0}},plane_enable_mem[o_plane_index]};
   16'h1408:immediate_rdata=i_plane_status;
   16'h1500:immediate_rdata={{(32-C_RESOURCE_INDEX_WIDTH){1'b0}},resource_index_q};
   16'h1504:begin request_is_query=!i_req_write;request_query_kind=Q_RESOURCE_FREE;request_query_index={{(32-C_RESOURCE_INDEX_WIDTH){1'b0}},resource_index_q};end
   16'h1508:begin request_is_query=!i_req_write;request_query_kind=Q_QUEUE_OCCUPANCY;request_query_index={{(32-C_RESOURCE_INDEX_WIDTH){1'b0}},resource_index_q};end
   16'h1510:immediate_rdata={{(32-C_ACCOUNT_INDEX_WIDTH){1'b0}},account_index_q};
   16'h1514:begin request_is_query=!i_req_write;request_query_kind=Q_ACCOUNT_ISSUED;request_query_index={{(32-C_ACCOUNT_INDEX_WIDTH){1'b0}},account_index_q};end
   16'h1518:begin request_is_query=!i_req_write;request_query_kind=Q_ACCOUNT_OCCUPIED;request_query_index={{(32-C_ACCOUNT_INDEX_WIDTH){1'b0}},account_index_q};end
   16'h1600:immediate_rdata={{(32-C_RAS_INDEX_WIDTH){1'b0}},ras_index_q};
   16'h1604:begin request_is_query=!i_req_write;request_query_kind=Q_RAS;request_query_index={{(32-C_RAS_INDEX_WIDTH){1'b0}},ras_index_q};end
   // RELEASE_STATUS: bit4配置错、bit3 Fabric timeout、bit2 release timeout、bit1当前stall、bit0 route pending。
   16'h1610:immediate_rdata={27'd0,release_watchdog_config_error,i_fabric_timeout_error,o_release_timeout_sticky,o_release_stall_active,i_route_pending};
   16'h1614:immediate_rdata=o_release_stall_cycles;
   16'h1618:immediate_rdata=o_release_timeout_count;
   16'h161c:immediate_rdata={{(32-C_RELEASE_INDEX_WIDTH){1'b0}},o_release_first_port};
   // RELEASE_RAS_W1C: bit0清恢复后的timeout sticky，bit1清恢复后的stall/timeout计数。
   16'h1620:immediate_rdata=32'd0;
   default:begin request_legal=1'b0;if(i_req_addr[15:12]==4'h8)request_unsupported=1'b1;end
  endcase
  if(i_req_write)begin
   case(i_req_addr)
    16'h1000:if(i_req_wdata>=C_NUM_STATIONS)request_legal=1'b0;
    16'h1004:begin end
    16'h1100:if(i_req_wdata>=C_PHYSICAL_PORTS)request_legal=1'b0;
    16'h1104:begin end
    16'h1200:if(i_req_wdata>=C_ROUTE_ENTRIES)request_legal=1'b0;
    16'h1204:begin end
    16'h120c:begin end
    16'h1300:if(i_req_wdata>=C_MAX_PORTS)request_legal=1'b0;
    16'h1304:begin end
    16'h1400:if(i_req_wdata>=C_NUM_PLANES)request_legal=1'b0;
    16'h1404:begin end
    16'h1500:if(i_req_wdata>=C_RESOURCES)request_legal=1'b0;
    16'h1510:if(i_req_wdata>=C_ACCOUNTS)request_legal=1'b0;
    16'h1600:if(i_req_wdata>=C_RAS_COUNTERS)request_legal=1'b0;
    16'h1620:begin end
    default:request_legal=1'b0;
   endcase
  end
 end

 // 响应与query都保持到各自ready；所有配置及commit命令只在合法请求接受沿产生一次。
 always @(posedge i_clk) begin
  if(!i_rstn)begin
   o_rsp_valid<=0;o_rsp_rdata<=0;o_rsp_error<=0;o_rsp_unsupported<=0;query_pending_q<=0;o_query_kind<=0;o_query_index<=0;
   o_station_mode_write<=0;o_station_index<=0;o_station_mode<=0;o_port_enable_write<=0;o_port_index<=0;o_port_enable<=0;
   o_plane_enable_write<=0;o_plane_index<=0;o_plane_enable<=0;o_route_shadow_write<=0;o_route_index<=0;o_route_shadow_wdata<=0;
   o_identity_shadow_write<=0;o_identity_index<=0;o_identity_shadow_wdata<=0;o_atomic_commit<=0;
   resource_index_q<=0;account_index_q<=0;ras_index_q<=0;o_release_timeout_w1c<=0;o_release_counter_w1c<=0;
   o_error_sticky<=0;o_unsupported_security<=0;
   for(reset_index=0;reset_index<C_NUM_STATIONS;reset_index=reset_index+1)station_mode_mem[reset_index]<=0;
   for(reset_index=0;reset_index<C_MAX_PORTS;reset_index=reset_index+1)port_enable_mem[reset_index]<=0;
   for(reset_index=0;reset_index<C_NUM_PLANES;reset_index=reset_index+1)plane_enable_mem[reset_index]<=0;
  end else begin
   o_station_mode_write<=0;o_port_enable_write<=0;o_plane_enable_write<=0;o_route_shadow_write<=0;o_identity_shadow_write<=0;o_atomic_commit<=0;
   o_release_timeout_w1c<=0;o_release_counter_w1c<=0;
   if(o_rsp_valid&&i_rsp_ready)o_rsp_valid<=0;
   if(query_pending_q&&i_query_ready)begin query_pending_q<=0;o_rsp_valid<=1;o_rsp_rdata<=i_query_data;o_rsp_error<=0;o_rsp_unsupported<=0;end
   if(release_watchdog_config_error)o_error_sticky<=1;
   if(i_req_valid&&o_req_ready)begin
    if(request_is_query&&request_legal)begin query_pending_q<=1;o_query_kind<=request_query_kind;o_query_index<=request_query_index;end
    else begin o_rsp_valid<=1;o_rsp_rdata<=request_legal?immediate_rdata:32'd0;o_rsp_error<=!request_legal;o_rsp_unsupported<=request_unsupported;end
    if(!request_legal)o_error_sticky<=1;
    if(request_unsupported)o_unsupported_security<=1;
    if(i_req_write&&request_legal)begin
     case(i_req_addr)
      16'h1000:o_station_index<=i_req_wdata[C_STATION_INDEX_WIDTH-1:0];
      16'h1004:begin station_mode_mem[o_station_index]<=i_req_wdata[1:0];o_station_mode<=i_req_wdata[1:0];o_station_mode_write<=1;end
      16'h1100:o_port_index<=i_req_wdata[C_PORT_INDEX_WIDTH-1:0];
      16'h1104:begin port_enable_mem[o_port_index]<=i_req_wdata[0];o_port_enable<=i_req_wdata[0];o_port_enable_write<=1;end
      16'h1200:o_route_index<=i_req_wdata[C_ROUTE_INDEX_WIDTH-1:0];
      16'h1204:begin o_route_shadow_wdata<=i_req_wdata;o_route_shadow_write<=1;end
      16'h120c:o_atomic_commit<=i_req_wdata[0];
      16'h1300:o_identity_index<=i_req_wdata[C_PORT_INDEX_WIDTH-1:0];
      16'h1304:begin o_identity_shadow_wdata<=i_req_wdata;o_identity_shadow_write<=1;end
      16'h1400:o_plane_index<=i_req_wdata[C_PLANE_INDEX_WIDTH-1:0];
      16'h1404:begin plane_enable_mem[o_plane_index]<=i_req_wdata[0];o_plane_enable<=i_req_wdata[0];o_plane_enable_write<=1;end
      16'h1500:resource_index_q<=i_req_wdata[C_RESOURCE_INDEX_WIDTH-1:0];
      16'h1510:account_index_q<=i_req_wdata[C_ACCOUNT_INDEX_WIDTH-1:0];
      16'h1600:ras_index_q<=i_req_wdata[C_RAS_INDEX_WIDTH-1:0];
      16'h1620:begin o_release_timeout_w1c<=i_req_wdata[0];o_release_counter_w1c<=i_req_wdata[1];end
      default:begin end
     endcase
    end
   end
  end
 end

 switch_release_path_watchdog #(
  .C_RELEASE_PORTS(C_RELEASE_PORTS),.C_RELEASE_INDEX_WIDTH(C_RELEASE_INDEX_WIDTH),
  .C_TIMEOUT_CYCLES(C_RELEASE_TIMEOUT_CYCLES),.C_TIMER_WIDTH(C_RELEASE_TIMER_WIDTH)) u_release_watchdog(
  .i_clk(i_clk),.i_rstn(i_rstn),.i_release_valid(i_release_valid),.i_release_ready(i_release_ready),
  .i_timeout_w1c(o_release_timeout_w1c),.i_counter_w1c(o_release_counter_w1c),
  .o_stall_active(o_release_stall_active),.o_timeout_sticky(o_release_timeout_sticky),
  .o_stall_cycles(o_release_stall_cycles),.o_timeout_count(o_release_timeout_count),
  .o_first_stalled_port(o_release_first_port),.o_config_error(release_watchdog_config_error));
endmodule
`default_nettype wire
