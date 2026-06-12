`timescale 1ns/1ps // 定义indexed Route SRAM仿真时间单位，不参与综合逻辑。
`default_nettype none // 禁止隐式网络隐藏地址或bank选择错误。
module switch_route_sram #( // 实现DstID直接索引、双bank原子切换和逐包Route锁存。
    parameter integer DST_ID_WIDTH = 12, // 指定线上DstID索引宽度。
    parameter integer DST_COUNT = 4096, // 指定实现的Route entry数量，默认覆盖全部12位DstID。
    parameter integer PORT_WIDTH = 10, // 指定GlobalPortID宽度，最大profile为十位。
    parameter integer POLICY_WIDTH = 8, // 指定Route policy元数据宽度。
    parameter integer EPOCH_WIDTH = 8, // 指定与commit控制器一致的Route epoch宽度。
    parameter integer LOOKUP_PORTS = 1 // 附加无状态只读口数量；默认一口且不改变旧scalar owner语义。
) ( // 查表、管理写和packet Route context共用一个已同步时钟域。
    input wire i_clk, // 在上升沿写shadow、切换active bank及锁存packet Route。
    input wire i_rstn, // 同步低有效复位使两个bank全部entry失效并选择bank0。
    input wire i_shadow_write, // 管理侧写当前非active bank的一个indexed entry。
    input wire [DST_ID_WIDTH-1:0] i_shadow_dst_id, // 直接选择shadow Route entry而不做compare-all。
    input wire i_shadow_valid, // 写入entry有效位，零值用于显式撤销Route。
    input wire [PORT_WIDTH-1:0] i_shadow_global_port, // 写入目标稳定GlobalPortID。
    input wire [POLICY_WIDTH-1:0] i_shadow_policy, // 写入后续调度使用的透明Route policy。
    input wire i_commit, // commit FSM确认quiescent后单拍翻转active bank。
    input wire [EPOCH_WIDTH-1:0] i_route_epoch, // 当前active Route代际由唯一commit FSM提供。
    input wire [DST_ID_WIDTH-1:0] i_lookup_dst_id, // 当前SOP候选DstID直接索引active bank。
    input wire i_packet_sop, // 新packet第一拍声明需要保存Route结果。
    input wire i_packet_eop, // 当前packet最后一拍声明Route ownership可释放。
    input wire i_packet_accept, // 只有真实数据面handshake才能建立或释放Route context。
    output reg o_lookup_valid, // 输出active entry或已锁存packet entry的有效位。
    output reg [PORT_WIDTH-1:0] o_lookup_global_port, // 输出packet生命周期稳定的GlobalPortID。
    output reg [POLICY_WIDTH-1:0] o_lookup_policy, // 输出packet生命周期稳定的Route policy。
    output reg [EPOCH_WIDTH-1:0] o_lookup_epoch, // 输出packet生命周期稳定的Route epoch。
    output wire o_packet_active, // 指示本查表端口正在拥有一个SOP后未结束packet。
    output wire o_active_bank, // 暴露当前active bank用于一致性检查和CSR观测。
    input wire [LOOKUP_PORTS*DST_ID_WIDTH-1:0] i_lookup_dst_id_vec, // 多入口前端并行读取同一active Route image。
    output wire [LOOKUP_PORTS-1:0] o_lookup_valid_vec, // 每个附加口独立报告indexed Route命中。
    output wire [LOOKUP_PORTS*PORT_WIDTH-1:0] o_lookup_global_port_vec, // 每个附加口输出GlobalPortID。
    output wire [LOOKUP_PORTS*POLICY_WIDTH-1:0] o_lookup_policy_vec // 每个附加口输出Route policy；packet冻结由调用者负责。
); // 结束indexed Route SRAM接口定义。
    reg active_bank_q; // 单bit selector使全部entry在一个边沿原子切换。
    reg route_valid_bank0 [0:DST_COUNT-1]; // bank0逐entry有效位独立于未复位SRAM data。
    reg route_valid_bank1 [0:DST_COUNT-1]; // bank1逐entry有效位支持shadow完整镜像。
    reg [PORT_WIDTH-1:0] route_port_bank0 [0:DST_COUNT-1]; // bank0保存DstID到GlobalPortID映射。
    reg [PORT_WIDTH-1:0] route_port_bank1 [0:DST_COUNT-1]; // bank1保存DstID到GlobalPortID映射。
    reg [POLICY_WIDTH-1:0] route_policy_bank0 [0:DST_COUNT-1]; // bank0保存每Route policy。
    reg [POLICY_WIDTH-1:0] route_policy_bank1 [0:DST_COUNT-1]; // bank1保存每Route policy。
    reg packet_active_q; // 保存当前查表端口是否已在SOP建立packet Route ownership。
    reg packet_valid_q; // 保存SOP时active Route有效位。
    reg [PORT_WIDTH-1:0] packet_port_q; // 保存SOP时GlobalPortID避免后续输入或commit改变。
    reg [POLICY_WIDTH-1:0] packet_policy_q; // 保存SOP时Route policy。
    reg [EPOCH_WIDTH-1:0] packet_epoch_q; // 保存SOP时Route epoch。
    localparam [31:0] DST_COUNT_VALUE = DST_COUNT; // 使用无符号32位常量统一参数化深度比较。
    localparam integer DST_INDEX_WIDTH = (DST_COUNT <= 2) ? 1 :
        (DST_COUNT <= 4) ? 2 : (DST_COUNT <= 8) ? 3 :
        (DST_COUNT <= 16) ? 4 : (DST_COUNT <= 32) ? 5 :
        (DST_COUNT <= 64) ? 6 : (DST_COUNT <= 128) ? 7 :
        (DST_COUNT <= 256) ? 8 : (DST_COUNT <= 512) ? 9 :
        (DST_COUNT <= 1024) ? 10 : (DST_COUNT <= 2048) ? 11 : 12;
    wire [31:0] lookup_dst_extended; // 将lookup DstID零扩展后避免有符号或宽度隐式转换。
    wire [31:0] shadow_dst_extended; // 将shadow DstID零扩展后避免有符号或宽度隐式转换。
    integer reset_index; // 静态循环索引用于复位双bank有效位，不清除SRAM data bits。
    genvar lookup_port_index; // 静态展开共享active image的并行组合读口。
    wire lookup_index_valid; // 防止非二次幂配置下越界访问Route数组。
    wire [DST_INDEX_WIDTH-1:0] lookup_index; // 范围检查后用于数组访问的定宽lookup索引。
    wire [DST_INDEX_WIDTH-1:0] shadow_index; // 范围检查后用于数组访问的定宽shadow索引。
    assign lookup_dst_extended = {{(32-DST_ID_WIDTH){1'b0}}, i_lookup_dst_id}; // 形成无符号32位lookup索引。
    assign shadow_dst_extended = {{(32-DST_ID_WIDTH){1'b0}}, i_shadow_dst_id}; // 形成无符号32位shadow索引。
    assign lookup_index_valid = lookup_dst_extended < DST_COUNT_VALUE; // 超范围DstID按无Route失败关闭。
    assign lookup_index = i_lookup_dst_id[DST_INDEX_WIDTH-1:0];
    assign shadow_index = i_shadow_dst_id[DST_INDEX_WIDTH-1:0];
    assign o_packet_active = packet_active_q; // 暴露唯一packet Route context ownership。
    assign o_active_bank = active_bank_q; // 暴露原子bank selector供表一致性检查。
    generate for(lookup_port_index=0;lookup_port_index<LOOKUP_PORTS;lookup_port_index=lookup_port_index+1)begin:g_lookup_vec
        wire [DST_ID_WIDTH-1:0] lookup_id; // 当前并行口的直接SRAM索引。
        wire [DST_INDEX_WIDTH-1:0] lookup_safe_id; // 越界编码先钳位零，禁止任何数组越界求值。
        wire lookup_in_range; // 非二次幂表深度必须显式拒绝尾部编码。
        assign lookup_id=i_lookup_dst_id_vec[lookup_port_index*DST_ID_WIDTH+:DST_ID_WIDTH];
        assign lookup_in_range={{(32-DST_ID_WIDTH){1'b0}},lookup_id}<DST_COUNT_VALUE;
        assign lookup_safe_id=lookup_in_range?lookup_id[DST_INDEX_WIDTH-1:0]:
            {DST_INDEX_WIDTH{1'b0}};
        assign o_lookup_valid_vec[lookup_port_index]=lookup_in_range&&
            ((!active_bank_q&&route_valid_bank0[lookup_safe_id])||(active_bank_q&&route_valid_bank1[lookup_safe_id]));
        assign o_lookup_global_port_vec[lookup_port_index*PORT_WIDTH+:PORT_WIDTH]=
            !o_lookup_valid_vec[lookup_port_index]?{PORT_WIDTH{1'b0}}:
            (!active_bank_q?route_port_bank0[lookup_safe_id]:route_port_bank1[lookup_safe_id]);
        assign o_lookup_policy_vec[lookup_port_index*POLICY_WIDTH+:POLICY_WIDTH]=
            !o_lookup_valid_vec[lookup_port_index]?{POLICY_WIDTH{1'b0}}:
            (!active_bank_q?route_policy_bank0[lookup_safe_id]:route_policy_bank1[lookup_safe_id]);
    end endgenerate
    always @(*) begin // 组合读取active indexed entry或已捕获的packet Route。
        o_lookup_valid = 1'b0; // 默认无效确保未知或越界目标失败关闭。
        o_lookup_global_port = {PORT_WIDTH{1'b0}}; // 无效Route不泄漏未初始化SRAM数据。
        o_lookup_policy = {POLICY_WIDTH{1'b0}}; // 无效Route使用零policy。
        o_lookup_epoch = i_route_epoch; // 空闲查表默认关联当前active代际。
        if (packet_active_q) begin // 已建立packet时完全忽略变化的DstID和active bank。
            o_lookup_valid = packet_valid_q; // 保持SOP时Route合法性。
            o_lookup_global_port = packet_port_q; // 保持SOP时GlobalPortID。
            o_lookup_policy = packet_policy_q; // 保持SOP时policy。
            o_lookup_epoch = packet_epoch_q; // 保持SOP时Route epoch。
        end else if (lookup_index_valid && !active_bank_q && route_valid_bank0[lookup_index]) begin // bank0有效entry直接输出。
            o_lookup_valid = 1'b1; // 声明bank0命中唯一indexed Route。
            o_lookup_global_port = route_port_bank0[lookup_index]; // 输出bank0目标端口。
            o_lookup_policy = route_policy_bank0[lookup_index]; // 输出bank0 policy。
        end else if (lookup_index_valid && active_bank_q && route_valid_bank1[lookup_index]) begin // bank1有效entry直接输出。
            o_lookup_valid = 1'b1; // 声明bank1命中唯一indexed Route。
            o_lookup_global_port = route_port_bank1[lookup_index]; // 输出bank1目标端口。
            o_lookup_policy = route_policy_bank1[lookup_index]; // 输出bank1 policy。
        end else begin // 无效、越界或未配置DstID维持失败关闭默认值。
            o_lookup_valid = 1'b0; // 明确拒绝zero-route目标。
            o_lookup_global_port = {PORT_WIDTH{1'b0}}; // 清零无效目标端口。
            o_lookup_policy = {POLICY_WIDTH{1'b0}}; // 清零无效policy。
        end // 结束active indexed lookup选择。
    end // 结束Route SRAM组合读过程。
    always @(posedge i_clk) begin // 单一时序过程管理bank有效位、shadow写和packet Route context。
        if (!i_rstn) begin // 同步复位仅清除ownership和有效元数据。
            active_bank_q <= 1'b0; // 复位固定选择bank0为active image。
            packet_active_q <= 1'b0; // 复位丢弃旧packet Route ownership。
            packet_valid_q <= 1'b0; // 清除旧捕获Route有效位。
            packet_port_q <= {PORT_WIDTH{1'b0}}; // 清除旧捕获GlobalPortID。
            packet_policy_q <= {POLICY_WIDTH{1'b0}}; // 清除旧捕获policy。
            packet_epoch_q <= {EPOCH_WIDTH{1'b0}}; // 清除旧捕获epoch。
            for (reset_index = 0; reset_index < DST_COUNT; reset_index = reset_index + 1) begin // 清除两bank有效位使未初始化data不可见。
                route_valid_bank0[reset_index] <= 1'b0; // bank0全部Route复位为invalid。
                route_valid_bank1[reset_index] <= 1'b0; // bank1全部Route复位为invalid。
            end // 结束Route valid复位循环。
        end else begin // 正常周期允许shadow写与commit同边沿完成。
            if (i_shadow_write && (shadow_dst_extended < DST_COUNT_VALUE)) begin // 只接受已实现深度内的indexed写。
                if (!active_bank_q) begin // bank0 active时管理侧唯一写bank1。
                    route_valid_bank1[shadow_index] <= i_shadow_valid; // 更新shadow entry有效位。
                    route_port_bank1[shadow_index] <= i_shadow_global_port; // 更新shadow目标端口。
                    route_policy_bank1[shadow_index] <= i_shadow_policy; // 更新shadow policy。
                end else begin // bank1 active时管理侧唯一写bank0。
                    route_valid_bank0[shadow_index] <= i_shadow_valid; // 更新shadow entry有效位。
                    route_port_bank0[shadow_index] <= i_shadow_global_port; // 更新shadow目标端口。
                    route_policy_bank0[shadow_index] <= i_shadow_policy; // 更新shadow policy。
                end // 结束shadow bank选择。
            end // 结束合法indexed shadow写。
            if (i_commit) active_bank_q <= !active_bank_q; // quiescent commit单边沿原子切换完整Route image。
            if (!packet_active_q && i_packet_sop && i_packet_accept) begin // 首拍真实接纳时捕获完整Route和代际。
                packet_valid_q <= o_lookup_valid; // 保存SOP active entry有效性。
                packet_port_q <= o_lookup_global_port; // 保存SOP GlobalPortID。
                packet_policy_q <= o_lookup_policy; // 保存SOP Route policy。
                packet_epoch_q <= o_lookup_epoch; // 保存SOP Route epoch。
                packet_active_q <= !i_packet_eop; // 单beat packet在同一握手直接完成而不残留owner。
            end else if (packet_active_q && i_packet_eop && i_packet_accept) begin // 当前packet EOP真实接纳后释放Route context。
                packet_active_q <= 1'b0; // 下一周期允许新的SOP查表。
            end // 结束packet Route ownership更新。
        end // 结束正常Route SRAM状态更新。
    end // 结束indexed Route SRAM时序过程。
endmodule // 结束indexed Route SRAM实现。
`default_nettype wire // 恢复后续编译单元的默认网络规则。
