`timescale 1ns/1ps // 本地应用响应按共同事务时钟生成。
`default_nettype none // 生成器不允许身份字段隐式漏连。
module ras_dummy_completion #(parameter integer EPOCH_WIDTH=8)( // 本地CMPTO完成生成模块，保存一个描述符并输出真实应用响应。
    input wire i_clk,i_rstn, // 共同上升沿和同步低有效复位。
    input wire i_request_valid, // 隔离账本提供的真实dummy生成请求。
    output wire o_request_ready, // 空闲且完整描述符合法才能接纳。
    input wire [1:0] i_request_slot,i_request_port, // 原义务槽和原物理端口。
    input wire [EPOCH_WIDTH-1:0] i_request_epoch, // 原始义务epoch不能重新贴标签。
    input wire [10:0] i_request_tag, // 完整原请求Tag。
    input wire i_request_read, // Read生成所有数据Beat，Write只生成无Data完成。
    input wire [2:0] i_request_beats, // Read一至四Beat，Write严格为一。
    input wire [3:0] i_request_status, // 当前本地隔离策略只允许CMPTO八。
    output wire o_response_valid, // 一个完整本地响应Beat待应用接纳。
    input wire i_response_ready, // 应用实际消费该Beat，不能用预留空间代替。
    output wire [1:0] o_response_slot,o_response_port, // 原始义务身份保持整个响应序列。
    output wire [EPOCH_WIDTH-1:0] o_response_epoch, // 每Beat携带原epoch。
    output wire [10:0] o_response_tag, // 完整Tag保持所有十一位。
    output wire o_response_read, // 应用据此区分有Data与无Data完成。
    output wire [1:0] o_response_num,o_response_offset, // 单Beat响应模式Num为零，Offset相对原请求递增。
    output wire o_response_last, // 仅最后实际输出Beat置一。
    output wire [3:0] o_response_status, // 每Beat保留CMPTO状态八。
    output wire [511:0] o_response_data, // Read错误数据确定零，Write没有数据义务。
    output wire o_done_valid, // 只有最后响应实际握手后的独立完成事件。
    input wire i_done_ready, // 账本真实消费完成事件；反压期间保持身份。
    output wire [1:0] o_done_slot, // 完成事件指向原始义务槽。
    output wire [EPOCH_WIDTH-1:0] o_done_epoch, // 完成事件携带原始epoch。
    output wire o_busy,o_error // 忙状态与当前非法描述符诊断，不产生Drop。
); // 结束本地应用完成生成接口。
    localparam [1:0] C_IDLE=2'd0,C_RESPONSE=2'd1,C_DONE=2'd2; // 请求接纳、响应输出、完成确认是三个不同阶段。
    reg [1:0] reg_state,reg_slot,reg_port,reg_offset; // 固定身份与当前响应位置。
    reg [EPOCH_WIDTH-1:0] reg_epoch; // 捕获原epoch直到done消费。
    reg [10:0] reg_tag; // 捕获全部Tag位。
    reg reg_read; // 响应类型独立保存。
    reg [2:0] reg_beats; // 保存完整一至四Beat义务。
    wire flag_legal,flag_last; // 描述符资格与当前最后Beat判断。
    assign flag_legal=(i_request_status==4'd8)&&(i_request_beats>=3'd1)&&(i_request_beats<=3'd4)&&(i_request_read||(i_request_beats==3'd1)); // 不接受会静默截短的描述符。
    assign flag_last=({1'b0,reg_offset}+3'd1)==reg_beats; // 四Beat最后位置三，比较不丢最高位。
    assign o_request_ready=i_rstn&&(reg_state==C_IDLE)&&flag_legal; // 忙期间不覆盖尚未完成的描述符。
    assign o_response_valid=i_rstn&&(reg_state==C_RESPONSE); // 响应阶段和done阶段互斥。
    assign o_done_valid=i_rstn&&(reg_state==C_DONE); // done不能早于最后实际响应握手。
    assign o_busy=i_rstn&&(reg_state!=C_IDLE); // done尚未消费也属于忙。
    assign o_error=i_rstn&&i_request_valid&&!flag_legal; // 非法描述符只诊断，不伪造完成。
    assign o_response_slot=reg_slot&{2{o_response_valid}}; // 空闲完整归零。
    assign o_response_port=reg_port&{2{o_response_valid}}; // 不混用下一候选端口。
    assign o_response_epoch=reg_epoch&{EPOCH_WIDTH{o_response_valid}}; // 每Beat属于捕获的epoch。
    assign o_response_tag=reg_tag&{11{o_response_valid}}; // 全Tag透传到真实应用响应。
    assign o_response_read=reg_read&&o_response_valid; // Write无数据义务。
    assign o_response_num=2'd0; // 本地响应采取每Beat单独完成字段模式。
    assign o_response_offset=reg_offset&{2{o_response_valid&&reg_read}}; // Write的无效Offset归零。
    assign o_response_last=flag_last&&o_response_valid; // Last随实际序列位置保持。
    assign o_response_status=o_response_valid?4'd8:4'd0; // 错误响应也必须输出所有Read Beat。
    assign o_response_data=512'd0; // CMPTO采用明示的零数据策略，不使用X掩盖未生成数据。
    assign o_done_slot=reg_slot&{2{o_done_valid}}; // done反压时原槽保持。
    assign o_done_epoch=reg_epoch&{EPOCH_WIDTH{o_done_valid}}; // done反压时原epoch保持。
    always @(posedge i_clk)begin // 本地应用数据接纳驱动真实生命周期。
        if(!i_rstn)begin reg_state<=C_IDLE;reg_slot<=2'd0;reg_port<=2'd0;reg_offset<=2'd0;reg_epoch<={EPOCH_WIDTH{1'b0}};reg_tag<=11'd0;reg_read<=1'b0;reg_beats<=3'd0;end // 共同reset取消旧生成历史。
        else if(i_request_valid&&o_request_ready)begin // 一个新义务原子进入生成器。
            reg_state<=C_RESPONSE;reg_slot<=i_request_slot;reg_port<=i_request_port;reg_epoch<=i_request_epoch; // 捕获完整原始身份。
            reg_tag<=i_request_tag;reg_read<=i_request_read;reg_beats<=i_request_beats;reg_offset<=2'd0; // 从相对第零Beat开始真实输出。
        end else if(o_response_valid&&i_response_ready)begin // 只有实际应用消费才能推进Beat。
            if(flag_last)reg_state<=C_DONE; // 最后一Beat消费后才允许独立done。
            else reg_offset<=reg_offset+2'd1; // 非末Beat实际握手才前进一次。
        end else if(o_done_valid&&i_done_ready)reg_state<=C_IDLE; // done被账本消费后才能接下一义务。
    end // 结束响应和确认时序。
    generate if((EPOCH_WIDTH<2)||(EPOCH_WIDTH>16))begin:gen_invalid // 明确有限epoch参数范围。
        ras_dummy_completion_parameters_invalid Invalid_Inst(); // 非法配置展开失败。
    end endgenerate // 结束参数保护。
endmodule // 结束真实本地CMPTO完成生成器。
`default_nettype wire // 恢复后续独立源码默认网络类型。
