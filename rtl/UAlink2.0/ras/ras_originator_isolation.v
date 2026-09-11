`timescale 1ns/1ps // 本地义务账本与事务所有者共享时钟epoch。
`default_nettype none // 隔离与完成事件接口禁止隐式漏接。
module ras_originator_isolation #( // Originator隔离义务模块，不生成Drop或伪完成。
    parameter integer PORTS=1,CAPACITY=4,IS_SWITCH=0,EPOCH_WIDTH=8 // 静态端口、外部槽数、隔离范围和本地epoch宽度。
)( // 槽身份由外部事务所有者分配，本模块不分配Tag。
    input wire i_clk,i_rstn, // 上升沿及同步低有效共同复位。
    input wire [PORTS-1:0] i_isolate,i_link_down, // 可信隔离请求与本地LinkDown事件。
    input wire [PORTS-1:0] i_link_up,i_init_done,i_drop, // 外部连接、初始化及唯一Drop所有者状态。
    input wire i_quiescent, // 外部确认整个epoch边界已经没有未登记流水事件。
    input wire i_track_valid, // 应用真实接纳请求时的原子义务登记。
    input wire [1:0] i_track_slot,i_track_port, // 已分配事务槽及完整物理端口。
    input wire [EPOCH_WIDTH-1:0] i_track_epoch, // 事件在产生时绑定的本地epoch。
    input wire [10:0] i_track_tag, // 原完整Tag只用于dummy描述符，不在本模块重新分配。
    input wire i_track_read, // Read义务需要后级生成声明数量的数据拍。
    input wire [2:0] i_track_beats, // 真实预计响应拍数一至四，Write必须一。
    output wire o_track_ready, // 有效合法空槽才能登记，满槽等待不是完成。
    input wire i_complete_valid, // 后级真实正常完成全部应有响应后的销账事件。
    input wire [1:0] i_complete_slot, // 正常完成所引用的既有事务槽。
    input wire [EPOCH_WIDTH-1:0] i_complete_epoch, // 正常完成原始epoch，不能临时重贴当前epoch。
    output wire o_complete_ready,o_complete_discard, // 错误或隔离后迟到完成可消费诊断但不能销dummy账。
    output reg o_dummy_valid, // 当前未发出的真实CMPTO生成请求。
    input wire i_dummy_ready, // 后级仅接纳此请求，不代表dummy已经生成完成。
    output reg [1:0] o_dummy_slot,o_dummy_port, // 原槽和原端口保持至请求握手。
    output wire [EPOCH_WIDTH-1:0] o_dummy_epoch, // 请求引用当前尚未结清的epoch。
    output reg [10:0] o_dummy_tag, // 原请求完整Tag。
    output reg o_dummy_read, // 后级不能把Read义务变成无Data的WriteResponse。
    output reg [2:0] o_dummy_beats, // 后级必须完成声明的全部响应拍数。
    output wire [3:0] o_dummy_status, // CMPTO状态编码八，只是请求元数据。
    input wire i_dummy_done_valid, // 后级真实完成所有dummy输出后的独立确认。
    input wire [1:0] i_dummy_done_slot, // 完成确认必须引用已经发出的请求。
    input wire [EPOCH_WIDTH-1:0] i_dummy_done_epoch, // dummy完成原始epoch。
    output wire o_dummy_done_ready, // 未知或重复确认消费后诊断且保持有效义务。
    input wire i_recover_valid, // 外部管理显式请求新epoch。
    input wire [EPOCH_WIDTH-1:0] i_recover_epoch, // 只能严格递增一且不允许回绕。
    output wire o_recover_ready,o_recovered, // 资格及实际管理握手，不能代表外部硬件已被本模块复位。
    output wire [PORTS-1:0] o_isolated,o_forward_allowed, // 独立隔离作用域与正常发Req/Data资格。
    output wire [EPOCH_WIDTH-1:0] o_epoch, // 本地事务事件当前epoch。
    output reg [7:0] o_count, // 已登记且未真正正常或dummy完成的义务数。
    output wire [3:0] o_error // 当前track、正常完成、dummy完成、恢复非法事件诊断。
); // 结束有限义务账本接口。
    localparam [31:0] C_SLOTS=CAPACITY; // 所有槽静态展开，容量三不生成未驱动地址行。
    localparam [2:0] C_CAPACITY=CAPACITY[2:0],C_PORTS=PORTS[2:0]; // 输入编号零扩展比较上限。
    localparam [1:0] C_LAST_SLOT=(CAPACITY==4)?2'd3:(CAPACITY==3)?2'd2:(CAPACITY==2)?2'd1:2'd0; // 轮询末槽精确回绕，不依赖二次幂。
    reg [PORTS-1:0] reg_isolated; // 只有本组件拥有Isolation状态，Drop始终属于外部。
    reg [EPOCH_WIDTH-1:0] reg_epoch; // 有限宽epoch严格拒绝最大值后的恢复。
    reg reg_hold; // 已展示且被反压的dummy请求必须保持同一槽。
    reg [1:0] reg_hold_slot; // 保存尚未握手请求的原槽。
    reg [1:0] reg_next; // 下一个dummy请求优先起点。
    wire [PORTS-1:0] trigger_ports,current_isolated; // 当前可信事件在同沿就阻止正常完成和转发。
    wire [CAPACITY-1:0] pending,issued,slot_isolated,complete_hit,normal_done,dummy_done; // 每槽独立合法事件观察。
    wire [CAPACITY*2-1:0] saved_port; // 静态槽原端口。
    wire [CAPACITY*11-1:0] saved_tag; // 静态槽原Tag。
    wire [CAPACITY-1:0] saved_read; // 静态槽Read属性。
    wire [CAPACITY*3-1:0] saved_beats; // 静态槽完整响应义务数量。
    wire track_busy,track_legal,flag_epoch_available; // 准入与恢复资格不依赖未定义槽内容。
    integer scan,index,count_index; // 有界组合选择索引。
    reg found; // 独立轮询只选一个未发出dummy义务。
    genvar s; // 逐实际槽展开全部状态。
    assign trigger_ports=(IS_SWITCH==1)?(i_isolate|i_link_down):{PORTS{|(i_isolate|i_link_down)}}; // Accelerator全角色，Switch按触发port，不由坏payload推断范围。
    assign current_isolated=reg_isolated|trigger_ports; // 当前沿Isolation立即生效。
    assign o_isolated=current_isolated&{PORTS{i_rstn}}; // reset期间禁止虚假隔离动作。
    assign o_forward_allowed=i_link_up&i_init_done&~i_drop&~o_isolated&{PORTS{i_rstn}}; // 不清Drop，不复用Drop状态，不修改信用。
    assign o_epoch=reg_epoch; // 同步寄存epoch按实际复位边界更新。
    assign track_busy=|(pending&({{(CAPACITY-1){1'b0}},1'b1}<<i_track_slot)); // 空槽资格不读取越界数组。
    assign track_legal=({1'b0,i_track_slot}<C_CAPACITY)&&!track_busy&&(i_track_epoch==reg_epoch)&&({1'b0,i_track_port}<C_PORTS)&&(i_track_beats>=3'd1)&&(i_track_beats<=3'd4)&&(i_track_read||(i_track_beats==3'd1)); // 仅接纳完整且可生成的本地义务描述符。
    assign o_track_ready=i_rstn&&track_legal; // 隔离期间新接纳请求也进入真实dummy义务。
    assign o_complete_ready=i_rstn; // 迟到和未知完成必须能被显式丢弃诊断。
    assign o_complete_discard=i_rstn&&i_complete_valid&&!(|normal_done); // 迟到真实Response不取消dummy义务。
    assign o_dummy_done_ready=i_rstn; // 非法done被消费但不能被解释为合法完成。
    assign o_dummy_epoch=reg_epoch&{EPOCH_WIDTH{o_dummy_valid}}; // 无有效请求时字段归零。
    assign o_dummy_status=o_dummy_valid?4'd8:4'd0; // CMPTO仅作为生成请求，不是已发出的Response。
    assign flag_epoch_available=reg_epoch!={EPOCH_WIDTH{1'b1}}; // 不允许epoch回绕别名旧事件。
    assign o_recover_ready=i_rstn&&(|reg_isolated)&&!(|pending)&&i_quiescent&&(&i_link_up)&&(&i_init_done)&&!(|i_drop)&&!(|trigger_ports)&&!i_track_valid&&!i_complete_valid&&!i_dummy_done_valid&&flag_epoch_available&&(i_recover_epoch==(reg_epoch+{{(EPOCH_WIDTH-1){1'b0}},1'b1})); // 义务清空、外部清理及严格新epoch必须同时满足。
    assign o_recovered=i_recover_valid&&o_recover_ready; // 只有明确管理握手才切换epoch。
    assign o_error={i_rstn&&i_recover_valid&&!o_recover_ready,i_rstn&&i_dummy_done_valid&&!(|dummy_done),i_rstn&&i_complete_valid&&!(|complete_hit),i_rstn&&i_track_valid&&!track_legal}; // 错误事件不静默清账。
    always @(*) begin // 计数只由实际登记位求和，不维护第二套易漂移计数器。
        o_count=8'd0; // 每周期完整默认赋值。
        for(count_index=32'd0;count_index<C_SLOTS;count_index=count_index+32'd1)begin // 常量容量内求和。
            o_count=o_count+{7'd0,pending[count_index]}; // issued状态仍保留在计数中。
        end // 结束义务数量归约。
    end // 结束组合义务计数。
    always @(*) begin // 一个稳定的轮询候选保持到真实请求握手。
        found=1'b0;index=0;o_dummy_valid=1'b0;o_dummy_slot=2'd0;o_dummy_port=2'd0;o_dummy_tag=11'd0;o_dummy_read=1'b0;o_dummy_beats=3'd0; // 无候选时输出完整归零。
        for(scan=32'd0;scan<C_SLOTS;scan=scan+32'd1)begin // 遍历每个实际义务槽一次。
            index=({30'd0,reg_next}+scan)%CAPACITY; // 非二次幂容量显式取余。
            if(i_rstn&&!found&&(!reg_hold||(index[1:0]==reg_hold_slot))&&pending[index]&&slot_isolated[index]&&!issued[index])begin // 只选择真实隔离且尚未发送的义务。
                found=1'b1;o_dummy_valid=1'b1;o_dummy_slot=index[1:0]; // 选择一个稳定原始槽。
                o_dummy_port=saved_port[index*2+:2];o_dummy_tag=saved_tag[index*11+:11]; // 身份来自登记值，不读新输入。
                o_dummy_read=saved_read[index];o_dummy_beats=saved_beats[index*3+:3]; // 完整生成责任来自登记描述符。
            end // 结束当前槽选择。
        end // 结束轮询候选生成。
    end // 结束dummy生成请求选择。
    always @(posedge i_clk) begin // Isolation、epoch和请求轮询共享一个管理时序边界。
        if(!i_rstn)begin reg_isolated<={PORTS{1'b0}};reg_epoch<={EPOCH_WIDTH{1'b0}};reg_next<=2'd0;reg_hold<=1'b0;reg_hold_slot<=2'd0;end // reset取消整个外部共同epoch的本地历史。
        else begin // 正常管理沿。
            if(o_dummy_valid)begin reg_hold<=!i_dummy_ready;reg_hold_slot<=o_dummy_slot;end // 首次反压锁定，真实请求握手后释放选择锁。
            reg_isolated<=current_isolated; // 重复隔离事件幂等保持。
            if(o_dummy_valid&&i_dummy_ready)reg_next<=(o_dummy_slot==C_LAST_SLOT)?2'd0:o_dummy_slot+2'd1; // 请求握手只推进选择，不清账。
            if(o_recovered)begin reg_isolated<={PORTS{1'b0}};reg_epoch<=i_recover_epoch;reg_next<=2'd0;reg_hold<=1'b0;reg_hold_slot<=2'd0;end // 外部资格齐全后的新epoch。
        end // 结束管理状态更新。
    end // 结束管理时序。
    generate // 有限实际槽和参数保护。
        if(((PORTS!=1)&&(PORTS!=2)&&(PORTS!=4))||(CAPACITY<1)||(CAPACITY>4)||((IS_SWITCH!=0)&&(IS_SWITCH!=1))||(EPOCH_WIDTH<2)||(EPOCH_WIDTH>16))begin:gen_invalid // 拒绝未声明的配置。
            ras_originator_isolation_parameters_invalid Invalid_Inst(); // 非法参数展开失败。
        end // 结束参数保护。
        for(s=32'd0;s<C_SLOTS;s=s+32'd1)begin:gen_slots // 逐槽真实义务记录，不为容量三保留第四行。
            localparam [1:0] C_SLOT=s[1:0]; // 完整本地槽编号。
            reg reg_pending,reg_issued,reg_read; // 已登记、请求已发、响应类型三个独立事实。
            reg [1:0] reg_port;reg [10:0] reg_tag;reg [2:0] reg_beats; // 原始完整生成元数据。
            wire track,dummy_request; // 本槽真实登记与dummy请求握手。
            assign pending[s]=reg_pending;assign issued[s]=reg_issued; // 实际义务状态参与选择和恢复检查。
            assign saved_port[s*2+:2]=reg_port;assign saved_tag[s*11+:11]=reg_tag;assign saved_read[s]=reg_read;assign saved_beats[s*3+:3]=reg_beats; // 全部描述符字段来自同一登记。
            assign slot_isolated[s]=|(current_isolated&({{(PORTS-1){1'b0}},1'b1}<<reg_port)); // 归属按可信登记port保持，不读迟到事件port。
            assign complete_hit[s]=reg_pending&&(i_complete_slot==C_SLOT)&&(i_complete_epoch==reg_epoch); // 旧epoch和未知槽不能命中当前义务。
            assign normal_done[s]=i_complete_valid&&complete_hit[s]&&!slot_isolated[s]&&!reg_issued; // 一旦隔离即拒绝真实完成对dummy义务销账。
            assign dummy_done[s]=i_dummy_done_valid&&reg_pending&&reg_issued&&slot_isolated[s]&&(i_dummy_done_slot==C_SLOT)&&(i_dummy_done_epoch==reg_epoch); // 只有请求已真实发出后才能确认完成。
            assign track=i_track_valid&&o_track_ready&&(i_track_slot==C_SLOT); // 准入只命中一个空槽。
            assign dummy_request=o_dummy_valid&&i_dummy_ready&&(o_dummy_slot==C_SLOT); // 请求接纳不等价于生成完成。
            always @(posedge i_clk)begin // 每槽义务生命周期独立但共享epoch资格。
                if(!i_rstn)begin reg_pending<=1'b0;reg_issued<=1'b0;reg_read<=1'b0;reg_port<=2'd0;reg_tag<=11'd0;reg_beats<=3'd0;end // 共同reset取消全部旧义务。
                else if(track)begin reg_pending<=1'b1;reg_issued<=1'b0;reg_read<=i_track_read;reg_port<=i_track_port;reg_tag<=i_track_tag;reg_beats<=i_track_beats;end // 接纳时保存完整原始生成责任。
                else if(normal_done[s]||dummy_done[s])begin reg_pending<=1'b0;reg_issued<=1'b0;end // 唯有真实完整完成才能销账。
                else if(dummy_request)reg_issued<=1'b1; // 已发请求仍保持pending直到独立done。
            end // 结束本槽状态更新。
        end // 结束全部实际槽。
    endgenerate // 结束有限义务账本结构。
endmodule // 结束Originator隔离与显式新epoch资格模块。
`default_nettype wire // 恢复后续独立源码默认网络规则。
