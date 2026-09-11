`timescale 1ns/1ps // 声明研发数字packet fabric的仿真时间单位。
`default_nettype none // 禁止隐式网络隐藏端口连接错误。

// 内部目标sideband交叉开关：尚未包含标准TL解析、逐端口TL/DL终止、管理CSR、INC或安全功能。
module ualink_switch_top #( // 提供可综合的参数化研发Switch数据通路顶层。
    parameter PORTS = 4, // 配置输入与输出端口数，至少一个。
    parameter DATA_WIDTH = 544, // 保持Endpoint的完整24位header与520位payload数字字。
    parameter ROUTE_CONFIG_ENABLE = 0, // 默认使用外部静态路由表；置一启用本地原子配置服务。
    parameter ROUTE_INDEX_WIDTH = (PORTS<=2)?1:(PORTS<=4)?2:(PORTS<=8)?3:(PORTS<=16)?4:(PORTS<=32)?5:(PORTS<=64)?6:(PORTS<=128)?7:(PORTS<=256)?8:(PORTS<=512)?9:10 // 管理索引保留非二次幂端口的非法编码。
) ( // 开始同钟ready/valid packet接口。
    input wire clk, // 接收所有端口共用的上升沿时钟。
    input wire rstn, // 接收同步低有效复位并清除包所有权和轮询状态。
    input wire [PORTS*10-1:0] i_route_ids, // 每目的端口提供一个静态10位逻辑目标ID。
    input wire [PORTS-1:0] i_port_enable, // 仅使enabled目的端口参与唯一目标匹配。
    input wire [PORTS-1:0] i_valid, // 每输入声明当前beat有效，反压时必须保持。
    output wire [PORTS-1:0] o_ready, // 每输入仅在唯一目的实际接收时返回ready。
    input wire [PORTS*DATA_WIDTH-1:0] i_data, // 传入全部源的完整逻辑数据字。
    input wire [PORTS*10-1:0] i_dst, // 提供独立目标sideband，整个包保持同一目标。
    input wire [PORTS-1:0] i_last, // 标记各输入当前包的最后一个beat。
    output wire [PORTS-1:0] o_valid, // 指示每输出当前选定源的有效beat。
    input wire [PORTS-1:0] i_ready, // 接收每目的端口独立反压。
    output wire [PORTS*DATA_WIDTH-1:0] o_data, // 以完整字宽送出各目的选定的数据。
    output wire [PORTS-1:0] o_last, // 原样传递选定源的包结束标志。
    output wire [PORTS-1:0] o_route_error, // 有效输入没有唯一enabled目标时置位并拒绝握手。
    output wire [127:0] o_pending_features, // 未实现服务模块的稳定角色位图。
    input wire i_route_write_valid, // 请求修改shadow路由项；仅配置模式生效。
    input wire [ROUTE_INDEX_WIDTH-1:0] i_route_write_index, // 指定真实目的端口编号。
    input wire [9:0] i_route_write_id, // shadow项的完整十位目标ID。
    input wire i_route_write_enable, // shadow项是否参与目标匹配。
    input wire i_route_commit, // 请求在完整空闲边界发布shadow表。
    output wire o_route_write_accepted, // 本沿实际接纳shadow写入。
    output wire o_route_commit_accepted, // 本沿实际原子提交所有路由项。
    output wire o_route_config_pending, // shadow与active表存在差异。
    output wire o_route_config_error, // 非法索引、重复目标、busy或同拍write/commit诊断。
    output wire o_route_quiescent, // 配置模式中无输入valid且无在途包owner时为一。
    output wire o_fabric_error // 非法选择冲突诊断，与目标查表错误分离。
); // 结束研发Switch顶层接口。
    wire [PORTS*10-1:0] active_route_ids; // 实际lookup只读取选定配置来源的完整表。
    wire [PORTS-1:0] active_port_enable; // 与ID表同一配置来源的目的使能。
    wire [PORTS*PORTS-1:0] route_match; // source-major唯一目标矩阵。
    wire [PORTS*PORTS-1:0] selected; // egress-major raw owner矩阵，不能直接当实际grant。
    wire [PORTS-1:0] packet_owned; // 包内气泡和首拍停顿期间仍保持的实际所有权。
    wire [PORTS-1:0] accepted_ready; // fabric允许有效转发时才允许仲裁器退休末拍。
    assign accepted_ready = i_ready & o_valid; // select不依赖ready，因此该反馈不形成组合环。

    generate if (ROUTE_CONFIG_ENABLE != 0) begin: configured_routes // 明确的本地管理接口，不声明规范CSR映射。
        assign o_route_quiescent = rstn && !(|packet_owned) && !(|i_valid); // 无valid不等于无owner，气泡不开放提交。
        switch_route_table #(.PORTS(PORTS), .INDEX_WIDTH(ROUTE_INDEX_WIDTH)) u_route_table (
            .i_clk(clk), .i_rstn(rstn), .i_write_valid(i_route_write_valid),
            .i_write_index(i_route_write_index), .i_write_route_id(i_route_write_id),
            .i_write_enable(i_route_write_enable), .i_commit(i_route_commit), .i_quiescent(o_route_quiescent),
            .o_write_accepted(o_route_write_accepted), .o_commit_accepted(o_route_commit_accepted),
            .o_route_ids(active_route_ids), .o_port_enable(active_port_enable),
            .o_pending(o_route_config_pending), .o_error(o_route_config_error)
        ); // 同沿提交ID与enable，已拒绝命令不改变active表。
    end else begin: static_routes // 默认模式继续使用既有外部静态路由接口。
        assign active_route_ids = i_route_ids;
        assign active_port_enable = i_port_enable;
        assign o_route_write_accepted = 1'b0;
        assign o_route_commit_accepted = 1'b0;
        assign o_route_config_pending = 1'b0;
        assign o_route_config_error = 1'b0;
        assign o_route_quiescent = 1'b0;
    end endgenerate

    switch_route_lookup #(.PORTS(PORTS)) u_route_lookup (
        .i_valid(i_valid), .i_dst(i_dst), .i_route_ids(active_route_ids),
        .i_port_enable(active_port_enable), .o_match(route_match), .o_error(o_route_error)
    ); // 非唯一目标不进入有效转发资格。
    switch_arbiter #(.PORTS(PORTS)) u_arbiter (
        .i_clk(clk), .i_rstn(rstn), .i_valid(i_valid), .i_route_match(route_match),
        .i_last(i_last), .i_ready(accepted_ready),
        .o_select(selected), .o_owned(packet_owned)
    ); // 首拍停顿建立owner，最后一拍实际接纳后才轮换。
    switch_fabric #(.PORTS(PORTS), .DATA_WIDTH(DATA_WIDTH)) u_fabric (
        .i_rstn(rstn), .i_valid(i_valid), .i_data(i_data), .i_last(i_last),
        .i_route_match(route_match), .i_select(selected), .i_ready(i_ready),
        .o_ready(o_ready), .o_valid(o_valid), .o_data(o_data), .o_last(o_last), .o_error(o_fabric_error)
    ); // 原样传递完整数据；选择冲突关闭相关路径并单独诊断。
    ualink_switch_scaffold u_scaffold(.i_clk(clk), .i_rstn(rstn), .o_pending_features(o_pending_features));
endmodule
`default_nettype wire
