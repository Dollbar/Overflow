`timescale 1ns/1ps // 隔离账本和本地响应生成共享事务时钟。
`default_nettype none // 禁止跨模块身份和完成事件隐式漏连。
module ras_isolation_completion #(parameter integer PORTS=1,CAPACITY=4,IS_SWITCH=0,EPOCH_WIDTH=8)( // Endpoint或Switch Originator本地应用完成集成模块。
    input wire i_clk,i_rstn, // 上升沿和同步低有效共同reset。
    input wire [PORTS-1:0] i_isolate,i_link_down,i_link_up,i_init_done,i_drop, // 外部可信事件与唯一Drop所有者状态。
    input wire i_quiescent, // 外部共同epoch边界资格。
    input wire i_track_valid, // 实际事务接纳的原子登记事件。
    input wire [1:0] i_track_slot,i_track_port, // 原事务槽和物理端口。
    input wire [EPOCH_WIDTH-1:0] i_track_epoch, // 原始事务epoch。
    input wire [10:0] i_track_tag, // 完整原事务Tag。
    input wire i_track_read, // 原响应是否具有数据义务。
    input wire [2:0] i_track_beats, // 原完整响应Beat数量一至四。
    output wire o_track_ready, // 真实账本空槽接纳，不是请求完成。
    input wire i_complete_valid, // 下游真实正常响应全部消费后的通知。
    input wire [1:0] i_complete_slot, // 正常完成原槽。
    input wire [EPOCH_WIDTH-1:0] i_complete_epoch, // 正常完成原epoch。
    output wire o_complete_ready,o_complete_discard,o_normal_retire, // 迟到事件只丢弃，不冒充可退休完成。
    input wire i_recover_valid, // 外部管理显式新epoch请求。
    input wire [EPOCH_WIDTH-1:0] i_recover_epoch, // 新epoch必须递增且不回绕。
    output wire o_recover_ready,o_recovered, // 资格与真实恢复握手。
    output wire [PORTS-1:0] o_isolated,o_forward_allowed, // 实际隔离与正常转发资格。
    output wire [EPOCH_WIDTH-1:0] o_epoch, // 当前本地义务epoch。
    output wire [7:0] o_count, // 包含已发请求但未实际完成的全部义务。
    output wire [3:0] o_error, // 原账本非法事件诊断，保持唯一账本状态。
    output wire o_response_valid, // 完整本地应用响应Beat有效。
    input wire i_response_ready, // 应用实际消费该Beat的握手。
    output wire [1:0] o_response_slot,o_response_port, // 完整响应原始身份。
    output wire [EPOCH_WIDTH-1:0] o_response_epoch, // 全部响应Beat保持原epoch。
    output wire [10:0] o_response_tag, // 全十一位原Tag。
    output wire o_response_read, // Write无Data，Read每Beat有完整512位。
    output wire [1:0] o_response_num,o_response_offset, // 单Beat响应模式与相对位置。
    output wire o_response_last, // 仅原义务最后Beat置一。
    output wire [3:0] o_response_status, // 每个错误响应CMPTO八。
    output wire [511:0] o_response_data, // 已生成的本地零数据Beat。
    output wire o_dummy_request_accepted,o_dummy_busy, // 真实生成请求接纳与生成器忙状态观察。
    output wire o_dummy_done_valid, // 最后应用响应握手之后的独立done观察。
    output wire [1:0] o_dummy_done_slot, // 完成原始槽观察。
    output wire [EPOCH_WIDTH-1:0] o_dummy_done_epoch, // 完成原始epoch观察。
    output wire o_generator_error // 非法内部生成描述符诊断，不生成Drop。
); // 结束本地应用完成集成接口。
    wire request_valid,request_ready,request_read,done_ready; // 独立请求与完成两次握手。
    wire [1:0] request_slot,request_port; // 原始生成请求身份。
    wire [EPOCH_WIDTH-1:0] request_epoch; // 原义务epoch。
    wire [10:0] request_tag; // 完整原Tag。
    wire [2:0] request_beats; // 完整生成责任。
    wire [3:0] request_status; // 实际CMPTO策略字段。
    assign o_dummy_request_accepted=request_valid&&request_ready; // 接纳只表示已开始生成。
    assign o_normal_retire=i_complete_valid&&o_complete_ready&&!o_complete_discard; // 迟到和未知事件不能传为正常退休。
    ras_originator_isolation #(.PORTS(PORTS),.CAPACITY(CAPACITY),.IS_SWITCH(IS_SWITCH),.EPOCH_WIDTH(EPOCH_WIDTH))u_ledger( // 使用冻结账本，不复制Isolation或epoch所有权。
        .i_clk(i_clk),.i_rstn(i_rstn),.i_isolate(i_isolate),.i_link_down(i_link_down),.i_link_up(i_link_up),.i_init_done(i_init_done),.i_drop(i_drop),.i_quiescent(i_quiescent), // 同一外部管理边界。
        .i_track_valid(i_track_valid),.o_track_ready(o_track_ready),.i_track_slot(i_track_slot),.i_track_port(i_track_port),.i_track_epoch(i_track_epoch),.i_track_tag(i_track_tag),.i_track_read(i_track_read),.i_track_beats(i_track_beats), // 实际事务完整登记。
        .i_complete_valid(i_complete_valid),.i_complete_slot(i_complete_slot),.i_complete_epoch(i_complete_epoch),.o_complete_ready(o_complete_ready),.o_complete_discard(o_complete_discard), // 保留真实完成与迟到丢弃判定。
        .o_dummy_valid(request_valid),.i_dummy_ready(request_ready),.o_dummy_slot(request_slot),.o_dummy_port(request_port),.o_dummy_epoch(request_epoch),.o_dummy_tag(request_tag),.o_dummy_read(request_read),.o_dummy_beats(request_beats),.o_dummy_status(request_status), // 请求接纳不能直接接完成。
        .i_dummy_done_valid(o_dummy_done_valid),.o_dummy_done_ready(done_ready),.i_dummy_done_slot(o_dummy_done_slot),.i_dummy_done_epoch(o_dummy_done_epoch), // 唯一销账来自真实响应生成器done。
        .i_recover_valid(i_recover_valid),.i_recover_epoch(i_recover_epoch),.o_recover_ready(o_recover_ready),.o_recovered(o_recovered),.o_isolated(o_isolated),.o_forward_allowed(o_forward_allowed),.o_epoch(o_epoch),.o_count(o_count),.o_error(o_error) // 所有恢复资格仍由唯一账本判断。
    ); // 结束真实隔离义务账本实例。
    ras_dummy_completion #(.EPOCH_WIDTH(EPOCH_WIDTH))u_generator( // 一个有限在途生成器，不新增第二套义务账本。
        .i_clk(i_clk),.i_rstn(i_rstn),.i_request_valid(request_valid),.o_request_ready(request_ready),.i_request_slot(request_slot),.i_request_port(request_port),.i_request_epoch(request_epoch),.i_request_tag(request_tag),.i_request_read(request_read),.i_request_beats(request_beats),.i_request_status(request_status), // 接纳完整冻结请求字段。
        .o_response_valid(o_response_valid),.i_response_ready(i_response_ready),.o_response_slot(o_response_slot),.o_response_port(o_response_port),.o_response_epoch(o_response_epoch),.o_response_tag(o_response_tag),.o_response_read(o_response_read),.o_response_num(o_response_num),.o_response_offset(o_response_offset),.o_response_last(o_response_last),.o_response_status(o_response_status),.o_response_data(o_response_data), // 真实本地应用响应直接交接，不冒充线上UPLI发送。
        .o_done_valid(o_dummy_done_valid),.i_done_ready(done_ready),.o_done_slot(o_dummy_done_slot),.o_done_epoch(o_dummy_done_epoch),.o_busy(o_dummy_busy),.o_error(o_generator_error) // 全部实际响应消费后才发出独立确认。
    ); // 结束本地应用CMPTO生成器实例。
endmodule // 结束共享Endpoint和Switch隔离完成集成候选。
`default_nettype wire // 恢复后续独立源码默认网络类型。
