`timescale 1ns/1ps // 声明研发数字packet fabric的仿真时间单位。
`default_nettype none // 禁止隐式网络隐藏端口连接错误。

// 内部目标sideband交叉开关：尚未包含标准TL解析、逐端口TL/DL终止、管理CSR、INC或安全功能。
module ualink_switch_top #( // 提供可综合的参数化研发Switch数据通路顶层。
    parameter PORTS = 4, // 配置输入与输出端口数，至少一个。
    parameter DATA_WIDTH = 544, // 保持Endpoint的完整24位header与520位payload数字字。
    parameter BUFFERED_EGRESS_ENABLE = 0, // 默认保留原逐beat fabric，启用时明确使用整包header预约。
    parameter PACKET_VCS = 4, // 仅buffered模式解释Request/Response类别下的VC。
    parameter PACKET_TOKEN_WIDTH = 8, // header和body传递同一包身份。
    parameter PACKET_UNIT_WIDTH = 4, // 一次整包预约的word数位宽。
    parameter [PACKET_UNIT_WIDTH-1:0] PACKET_DEFAULT_CAPACITY = 4, // 每分区默认容量使用明确units位宽。
    parameter [2*PACKET_VCS*PORTS*PACKET_UNIT_WIDTH-1:0] PACKET_CAPACITIES = {2*PACKET_VCS*PORTS{PACKET_DEFAULT_CAPACITY}}, // 独立资源分区；默认位宽四位。
    parameter RSP_BURST_MAX = 2, // 物理输出连续响应包配额。
    parameter ROUTE_CONFIG_ENABLE = 0, // 默认使用外部静态路由表；置一启用本地原子配置服务。
    parameter ROUTE_INDEX_WIDTH = (PORTS<=2)?1:(PORTS<=4)?2:(PORTS<=8)?3:(PORTS<=16)?4:(PORTS<=32)?5:(PORTS<=64)?6:(PORTS<=128)?7:(PORTS<=256)?8:(PORTS<=512)?9:10 // 管理索引保留非二次幂端口的非法编码。
) ( // 开始同钟ready/valid packet接口。
    input wire [PORTS-1:0] i_packet_header_valid, // 仅buffered模式声明完整包元数据，独立于body有效。
    output wire [PORTS-1:0] o_packet_header_ready, // 真实header接纳脉冲，不是可用容量提示。
    input wire [PORTS*PACKET_UNIT_WIDTH-1:0] i_packet_units, // 总word数必须在第一拍body之前预约。
    input wire [PORTS*PACKET_TOKEN_WIDTH-1:0] i_packet_token, // 本次header保存的完整包身份。
    input wire [PORTS*PACKET_TOKEN_WIDTH-1:0] i_packet_body_token, // body必须匹配已接纳header的保存身份。
    input wire [PORTS*2-1:0] i_packet_vc, // 独立原生本地上下文，不从flit猜VC。
    input wire [PORTS-1:0] i_packet_response, // Request或Response资源类别显式输入。
    output wire [PORTS*24-1:0] o_typed_local_dl_header, // buffered输出保存的本地header24。
    output wire [PORTS*6-1:0] o_typed_record_aux, // buffered输出原始辅助六位。
    output wire [PORTS*2-1:0] o_typed_tl_msg, // buffered输出原始两位TLmsg。
    output wire [PORTS*512-1:0] o_typed_tl_flit, // buffered输出完整已打包flit。
    output wire [PORTS*PACKET_TOKEN_WIDTH-1:0] o_packet_token, // typed record保存的完整包身份。
    output wire [PORTS*2-1:0] o_packet_vc, // typed record保存的实际VC。
    output wire [PORTS-1:0] o_packet_response, // typed record保存的实际类别。
    output wire [2*PACKET_VCS*PORTS-1:0] o_queue_release_valid, // 仅queue到repack末word捕获生成，不能当typed退休。
    output wire [2*PACKET_VCS*PORTS*PACKET_UNIT_WIDTH-1:0] o_queue_release_units, // 原预约整包units只返回一次。
    output wire o_egress_error, // buffered队列或repack真实诊断；不冒充fabric选择错误。
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
    wire [PORTS-1:0] lookup_valid; // header admission只使用此唯一lookup结果。
    wire buffered_busy; // 队列预约和typed holding均属于配置切换的在途状态。
    assign lookup_valid=(BUFFERED_EGRESS_ENABLE!=0)?i_packet_header_valid:i_valid; // 默认原有逐beat查表保持不变。
    wire [PORTS*PORTS-1:0] route_match; // source-major唯一目标矩阵。
    wire [PORTS-1:0] packet_owned; // 包内气泡和首拍停顿期间仍保持的实际所有权。

    generate if (ROUTE_CONFIG_ENABLE != 0) begin: configured_routes // 明确的本地管理接口，不声明规范CSR映射。
        wire [PORTS*10-1:0] unused_static_route_ids; // 配置模式不读取外部静态表。
        wire [PORTS-1:0] unused_static_port_enable; // 配置模式使用active表的enable。
        assign unused_static_route_ids=i_route_ids; // 明确保留兼容输入但不作为当前路由来源。
        assign unused_static_port_enable=i_port_enable; // 明确保留兼容输入但不作为当前路由来源。
        assign o_route_quiescent = rstn && !(|packet_owned) && !(|i_valid) && !buffered_busy && ((BUFFERED_EGRESS_ENABLE==0)||!(|i_packet_header_valid)); // 无valid不等于无owner，气泡不开放提交。
        switch_route_table #(.PORTS(PORTS), .INDEX_WIDTH(ROUTE_INDEX_WIDTH)) u_route_table (
            .i_clk(clk), .i_rstn(rstn), .i_write_valid(i_route_write_valid),
            .i_write_index(i_route_write_index), .i_write_route_id(i_route_write_id),
            .i_write_enable(i_route_write_enable), .i_commit(i_route_commit), .i_quiescent(o_route_quiescent),
            .o_write_accepted(o_route_write_accepted), .o_commit_accepted(o_route_commit_accepted),
            .o_route_ids(active_route_ids), .o_port_enable(active_port_enable),
            .o_pending(o_route_config_pending), .o_error(o_route_config_error)
        ); // 同沿提交ID与enable，已拒绝命令不改变active表。
    end else begin: static_routes // 默认模式继续使用既有外部静态路由接口。
        wire [PORTS:0] unused_quiescent_state; // 静态路由模式没有commit服务，仍保留真实owner观察。
        assign unused_quiescent_state={packet_owned,buffered_busy}; // 不改变原fabric或buffered所有权。
        wire [ROUTE_INDEX_WIDTH+12:0] unused_config_commands; // 静态配置模式不解释管理写入输入。
        assign unused_config_commands={i_route_write_valid,i_route_write_index,i_route_write_id,i_route_write_enable,i_route_commit}; // 默认配置入口明确未激活。
        assign active_route_ids = i_route_ids;
        assign active_port_enable = i_port_enable;
        assign o_route_write_accepted = 1'b0;
        assign o_route_commit_accepted = 1'b0;
        assign o_route_config_pending = 1'b0;
        assign o_route_config_error = 1'b0;
        assign o_route_quiescent = 1'b0;
    end endgenerate

    switch_route_lookup #(.PORTS(PORTS)) u_route_lookup (
        .i_valid(lookup_valid), .i_dst(i_dst), .i_route_ids(active_route_ids),
        .i_port_enable(active_port_enable), .o_match(route_match), .o_error(o_route_error)
    ); // 非唯一目标不进入有效转发资格。
    generate if(BUFFERED_EGRESS_ENABLE!=0)begin:gen_buffered // 显式可选整包上下文入口。
    if(DATA_WIDTH!=544)begin:gen_invalid_record // buffered profile只允许完整本地544位record。
      buffered_switch_requires_544_bits Invalid_Record_Inst(); // 不静默截断已有端口数据。
    end // 结束宽度保护。
    wire [2*PACKET_VCS*PORTS*PACKET_UNIT_WIDTH-1:0] reserved; // 所有分区未释放的真实预约。
    wire [PORTS-1:0] source_busy; // header已接纳但body尚未写全的所有权。
    wire [PORTS-1:0] scheduler_owned; // 包内停顿仍有物理输出锁。
    assign buffered_busy=(|reserved)||(|source_busy)||(|o_valid); // repack捕获末word后reservation可零，holding仍必须阻止commit。
    assign packet_owned=source_busy|scheduler_owned; // 气泡与首拍stall均不能开放配置提交。
    assign o_fabric_error=1'b0; // 真实诊断使用独立egress_error输出。
    wire [2*PACKET_VCS*PORTS-1:0] unused_o_selected; // 未导出的原有观察信号，实际错误已归约至o_egress_error。
    wire [2*PACKET_VCS*PORTS*PACKET_UNIT_WIDTH-1:0] unused_o_available; // 未导出的原有观察信号，实际错误已归约至o_egress_error。
    wire [2*PACKET_VCS*PORTS*PACKET_UNIT_WIDTH-1:0] unused_o_queue_reserved; // 未导出的原有观察信号，实际错误已归约至o_egress_error。
    wire [2*PACKET_VCS*PORTS*PACKET_UNIT_WIDTH-1:0] unused_o_stored; // 未导出的原有观察信号，实际错误已归约至o_egress_error。
    wire [2*PACKET_VCS*PORTS*PACKET_UNIT_WIDTH-1:0] unused_o_completed; // 未导出的原有观察信号，实际错误已归约至o_egress_error。
    wire [PORTS-1:0] unused_o_source_error_sticky; // 未导出的原有观察信号，实际错误已归约至o_egress_error。
    wire [PORTS-1:0] unused_o_header_error; // 未导出的原有观察信号，实际错误已归约至o_egress_error。
    wire [PORTS-1:0] unused_o_body_error; // 未导出的原有观察信号，实际错误已归约至o_egress_error。
    wire [2*PACKET_VCS*PORTS-1:0] unused_o_queue_error_now; // 未导出的原有观察信号，实际错误已归约至o_egress_error。
    wire [2*PACKET_VCS*PORTS-1:0] unused_o_queue_error_sticky; // 未导出的原有观察信号，实际错误已归约至o_egress_error。
    wire [2*PACKET_VCS-1:0] unused_o_reservation_error; // 未导出的原有观察信号，实际错误已归约至o_egress_error。
    wire [PORTS-1:0] unused_o_repack_input_error; // 未导出的原有观察信号，实际错误已归约至o_egress_error。
    switch_egress_typed_pipeline #(.PORTS(PORTS),.VCS(PACKET_VCS),.TOKEN_WIDTH(PACKET_TOKEN_WIDTH),.UNIT_WIDTH(PACKET_UNIT_WIDTH),.DEFAULT_CAPACITY(PACKET_DEFAULT_CAPACITY),.CAPACITIES(PACKET_CAPACITIES),.RSP_BURST_MAX(RSP_BURST_MAX)) u_egress( // 唯一header预约和出队释放路径。
      .i_clk(clk),.i_rstn(rstn),.i_header_valid(i_packet_header_valid),.i_route_match(route_match), // 使用原有唯一lookup，不增加第二路路由解释。
      .i_header_units(i_packet_units),.i_header_token(i_packet_token),.i_header_vc(i_packet_vc),.i_header_response(i_packet_response),.o_header_ready(o_packet_header_ready), // header接纳保存整包上下文。
      .i_body_valid(i_valid),.i_body_data(i_data),.i_body_last(i_last),.i_body_token(i_packet_body_token),.o_body_ready(o_ready), // body资格仅来自已保存owner。
      .i_ready(i_ready),.o_valid(o_valid),.o_data(o_data),.o_last(o_last), // 原始record输出增加typed elastic一级。
      .o_token(o_packet_token),.o_vc(o_packet_vc),.o_response(o_packet_response), // 下游看到保存的同一word上下文。
      .o_local_dl_header(o_typed_local_dl_header),.o_record_aux(o_typed_record_aux),.o_tl_msg(o_typed_tl_msg),.o_tl_flit(o_typed_tl_flit), // 完整位宽明确交接，不重建标准TL源字段。
      .o_release_valid(o_queue_release_valid),.o_release_units(o_queue_release_units),.o_reserved(reserved),.o_source_busy(source_busy),.o_owned(scheduler_owned),.o_error(o_egress_error), // queue release与typed retire分别观察。
      .o_selected(unused_o_selected),.o_available(unused_o_available),.o_queue_reserved(unused_o_queue_reserved),.o_stored(unused_o_stored),.o_completed(unused_o_completed),.o_source_error_sticky(unused_o_source_error_sticky),.o_header_error(unused_o_header_error),.o_body_error(unused_o_body_error),.o_queue_error_now(unused_o_queue_error_now),.o_queue_error_sticky(unused_o_queue_error_sticky),.o_reservation_error(unused_o_reservation_error),.o_repack_input_error(unused_o_repack_input_error)); // 未导出的原诊断仍由o_error归约，其他仅观察。
    end else begin:gen_legacy // 默认行为保持原查表、仲裁、fabric路径。
    wire [2*PACKET_VCS*PORTS*PACKET_UNIT_WIDTH-1:0] unused_packet_capacities; // 默认mode不启用容量分区。
    wire [31:0] unused_rsp_burst_max; // 默认mode沿用旧arbiter，不解释新scheduler配额。
    assign unused_packet_capacities=PACKET_CAPACITIES; // 明确保存参数接口而不实例化额外存储。
    assign unused_rsp_burst_max=RSP_BURST_MAX; // 默认mode参数不影响原路径。
    wire [PORTS*(PACKET_UNIT_WIDTH+2*PACKET_TOKEN_WIDTH+4)-1:0] unused_packet_context; // 默认模式不使用新增整包上下文输入。
    assign unused_packet_context={i_packet_header_valid,i_packet_units,i_packet_token,i_packet_body_token,i_packet_vc,i_packet_response}; // 忽略仅用于可选buffered模式的完整输入。
    wire [PORTS*PORTS-1:0] selected; // 旧模式唯一fabric选择。
    wire [PORTS-1:0] accepted_ready; // 旧模式只退休真实输出握手。
    assign accepted_ready=i_ready&o_valid; // 选择不依赖ready，无组合环。
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
    assign buffered_busy=1'b0; // 默认路径没有额外queue或typed holding。
    assign o_packet_header_ready={PORTS{1'b0}}; // 默认模式不接纳新增header服务。
    assign o_typed_local_dl_header={(PORTS*24){1'b0}}; // 默认模式不宣称typed服务已执行。
    assign o_typed_record_aux={(PORTS*6){1'b0}}; // 默认mode新增观察确定为零。
    assign o_typed_tl_msg={(PORTS*2){1'b0}}; // 默认mode新增观察确定为零。
    assign o_typed_tl_flit={(PORTS*512){1'b0}}; // 默认mode新增观察确定为零。
    assign o_packet_token={(PORTS*PACKET_TOKEN_WIDTH){1'b0}}; // 默认mode无新增身份。
    assign o_packet_vc={(PORTS*2){1'b0}}; // 默认mode无新增VC解释。
    assign o_packet_response={PORTS{1'b0}}; // 默认mode无新增类别解释。
    assign o_queue_release_valid={(2*PACKET_VCS*PORTS){1'b0}}; // 默认mode没有预约，不伪造release。
    assign o_queue_release_units={(2*PACKET_VCS*PORTS*PACKET_UNIT_WIDTH){1'b0}}; // 默认mode没有units账本。
    assign o_egress_error=1'b0; // 默认mode沿用原fabric错误。
    end endgenerate // 结束互斥数据通路，不产生双重预约。
    ualink_switch_scaffold u_scaffold(.i_clk(clk), .i_rstn(rstn), .o_pending_features(o_pending_features));
endmodule
`default_nettype wire
