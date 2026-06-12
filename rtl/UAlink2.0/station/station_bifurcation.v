// 一个Station固定占用四个GlobalPort槽，本模块只计算模式、lane与服务单元映射。
`default_nettype none
module station_bifurcation (
    input  wire [1:0]   i_mode,             // 0=x4，1=2x2，2=4x1，3=非法。
    input  wire [3:0]   i_lane_up,          // 四条200G物理lane的当前可用状态。
    output reg  [3:0]   o_port_configured,  // 模式配置的稳定槽集合。
    output reg  [3:0]   o_port_active,      // 对应lane全部up的可服务槽集合。
    output reg  [15:0]  o_lane_masks,       // 每槽四位lane mask，slot0位于最低端。
    output reg  [11:0]  o_service_units,    // 每槽三位200G service-unit数量。
    output wire         o_mode_error,       // 保留模式3必须失败关闭。
    output wire         o_duplicate_lane,   // 两个配置槽不得拥有同一lane。

    // 保留旧scaffold ABI；真实映射不依赖这些数据通路信号。
    input  wire         i_clk,
    input  wire         i_rstn,
    input  wire         i_enable,
    input  wire         i_valid,
    input  wire [511:0] i_data,
    input  wire [127:0] i_meta,
    output wire         o_ready,
    output wire         o_valid,
    output wire [511:0] o_data,
    output wire [127:0] o_meta,
    output wire         o_implemented,
    output wire         o_error
);

wire unused_legacy = ^{i_clk, i_data, i_meta}; // 保留ABI信号不参与映射所有权。

assign o_mode_error = (i_mode == 2'd3);

always @* begin
    o_port_configured = 4'b0000;
    o_lane_masks = 16'h0000;
    o_service_units = 12'h000;

    case (i_mode)
        2'd0: begin // x4：仅稳定slot0活动，占用全部四条lane。
            o_port_configured = 4'b0001;
            o_lane_masks = 16'h000f;
            o_service_units = 12'h004;
        end
        2'd1: begin // 2x2：稳定slot0和slot2分别拥有低、高两条lane。
            o_port_configured = 4'b0101;
            o_lane_masks = 16'h0c03;
            o_service_units = 12'h202;
        end
        2'd2: begin // 4x1：四个稳定槽各自拥有一条lane。
            o_port_configured = 4'b1111;
            o_lane_masks = 16'h8421;
            o_service_units = 12'h249;
        end
        default: begin // 非法模式不发布任何端口或lane所有权。
            o_port_configured = 4'b0000;
            o_lane_masks = 16'h0000;
            o_service_units = 12'h000;
        end
    endcase

    o_port_active = 4'b0000;
    if (o_port_configured[0] && ((i_lane_up & o_lane_masks[3:0]) == o_lane_masks[3:0]))
        o_port_active[0] = 1'b1;
    if (o_port_configured[1] && ((i_lane_up & o_lane_masks[7:4]) == o_lane_masks[7:4]))
        o_port_active[1] = 1'b1;
    if (o_port_configured[2] && ((i_lane_up & o_lane_masks[11:8]) == o_lane_masks[11:8]))
        o_port_active[2] = 1'b1;
    if (o_port_configured[3] && ((i_lane_up & o_lane_masks[15:12]) == o_lane_masks[15:12]))
        o_port_active[3] = 1'b1;
end

wire overlap01 = |(o_lane_masks[3:0] & o_lane_masks[7:4] &
                   {4{o_port_configured[0] & o_port_configured[1]}});
wire overlap02 = |(o_lane_masks[3:0] & o_lane_masks[11:8] &
                   {4{o_port_configured[0] & o_port_configured[2]}});
wire overlap03 = |(o_lane_masks[3:0] & o_lane_masks[15:12] &
                   {4{o_port_configured[0] & o_port_configured[3]}});
wire overlap12 = |(o_lane_masks[7:4] & o_lane_masks[11:8] &
                   {4{o_port_configured[1] & o_port_configured[2]}});
wire overlap13 = |(o_lane_masks[7:4] & o_lane_masks[15:12] &
                   {4{o_port_configured[1] & o_port_configured[3]}});
wire overlap23 = |(o_lane_masks[11:8] & o_lane_masks[15:12] &
                   {4{o_port_configured[2] & o_port_configured[3]}});

assign o_duplicate_lane = overlap01 | overlap02 | overlap03 |
                          overlap12 | overlap13 | overlap23;

// 旧scaffold接口不声称承载有效数据；错误请求仍显式诊断。
assign o_ready = i_rstn && i_enable && !o_mode_error && !o_duplicate_lane;
assign o_valid = 1'b0;
assign o_data = 512'd0;
assign o_meta = 128'd0;
assign o_implemented = 1'b1;
assign o_error = i_rstn && (o_mode_error || o_duplicate_lane || (i_enable && i_valid));

endmodule
`default_nettype wire
