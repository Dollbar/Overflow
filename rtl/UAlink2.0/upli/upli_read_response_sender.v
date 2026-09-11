`timescale 1ns/1ps // 同域同步发送状态，不引入可综合延时。
`default_nettype none // 禁止隐式接线遗漏。
module upli_read_response_sender #( // 完整分阶段Read Response发送管理模块，非接收或Tag收集器。
    parameter integer C_NUM_PORTS = 1, // 配置一、二或四个物理端口。
    parameter integer C_CREDIT_WIDTH = 4, // 信用银行计数位宽。
    parameter [C_CREDIT_WIDTH-1:0] C_DEFAULT_CAPACITY = 4, // 每账户默认可用容量。
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_CAPACITIES = {C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}, // 各端口VC0至VC3和共享池容量。
    parameter integer C_INIT_COUNT_WIDTH = 4, // 初始化稳定计数宽度。
    parameter integer C_INIT_CYCLES = 2 // 初始化确认至少连续两拍。
) ( // 原生字段与信用管理接口。
    input wire i_clk, // i_clk完整接口信号。
    input wire i_rstn, // i_rstn完整接口信号。
    input wire i_credit_connected, // i_credit_connected完整接口信号。
    input wire i_beats_connected, // i_beats_connected完整接口信号。
    input wire i_candidate_valid, // i_candidate_valid完整接口信号。
    input wire [1:0] i_candidate_port, // i_candidate_port完整接口信号。
    input wire [1:0] i_candidate_vc, // i_candidate_vc完整接口信号。
    input wire [3:0] i_candidate_pools, // i_candidate_pools完整接口信号。
    input wire [2475:0] i_candidate_payload, // i_candidate_payload完整接口信号。
    input wire [3:0] i_credit_valid, // i_credit_valid完整接口信号。
    input wire [3:0] i_credit_pool, // i_credit_pool完整接口信号。
    input wire [7:0] i_credit_vc, // i_credit_vc完整接口信号。
    input wire [7:0] i_credit_num, // i_credit_num完整接口信号。
    input wire [3:0] i_credit_init_done, // i_credit_init_done完整接口信号。
    output wire o_candidate_accepted, // o_candidate_accepted完整接口信号。
    output wire o_candidate_error, // o_candidate_error完整接口信号。
    output wire o_valid, // o_valid完整接口信号。
    output wire [1:0] o_port, // o_port完整接口信号。
    output wire [63:0] o_auth_tag, // o_auth_tag完整接口信号。
    output wire [9:0] o_src, // o_src完整接口信号。
    output wire [9:0] o_dst, // o_dst完整接口信号。
    output wire [10:0] o_tag, // o_tag完整接口信号。
    output wire [1:0] o_num_beats, // o_num_beats完整接口信号。
    output wire [511:0] o_data, // o_data完整接口信号。
    output wire [3:0] o_status, // o_status完整接口信号。
    output wire [1:0] o_offset, // o_offset完整接口信号。
    output wire o_last, // o_last完整接口信号。
    output wire o_data_error, // o_data_error完整接口信号。
    output wire [1:0] o_type_info, // o_type_info完整接口信号。
    output wire [1:0] o_vc, // o_vc完整接口信号。
    output wire o_pool, // o_pool完整接口信号。
    output wire o_valid_parity, // o_valid_parity完整接口信号。
    output wire o_auth_tag_parity, // o_auth_tag_parity完整接口信号。
    output wire [7:0] o_data_parity, // o_data_parity完整接口信号。
    output wire o_control_parity, // o_control_parity完整接口信号。
    output wire [618:0] o_payload, // o_payload完整接口信号。
    output wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_balances, // o_balances完整接口信号。
    output wire [3:0] o_init_confirmed, // o_init_confirmed完整接口信号。
    output wire o_credit_error, // o_credit_error完整接口信号。
    output wire o_credit_error_sticky, // o_credit_error_sticky完整接口信号。
    output wire [3:0] o_busy, // o_busy完整接口信号。
    output wire o_tdm_known, // o_tdm_known完整接口信号。
    output wire [1:0] o_tdm_port // o_tdm_port完整接口信号。
 ); // 结束完整接口定义。
    localparam [1:0] C_PHASE_MASK = (C_NUM_PORTS == 4) ? 2'd3 : (C_NUM_PORTS == 2) ? 2'd1 : 2'd0; // 配置端口的相位循环掩码。
    localparam [3:0] C_PORT_MASK = (C_NUM_PORTS == 4) ? 4'b1111 : (C_NUM_PORTS == 2) ? 4'b0011 : 4'b0001; // 原生四位端口中的有效集合。
    reg reg_tdm_known; // 第一次真实发送之后建立通道独立相位。
    reg [1:0] reg_tdm_port; // 相位建立后每个时钟推进，包括空闲周期。
    reg reg_credit_error_sticky; // 账本错误后阻止继续发送，必须统一复位恢复。
    wire flag_active; // 沿前连接与本地健康资格。
    wire [3:0] flag_geometry; // 只检查实际声明的多拍几何。
    wire [1:0] candidate_num; // NumBeats编码零表示独立单拍。
    wire [3:0] beat_mask, pool_mask, vc_mask; // 仅声明的拍参与整笔预约。
    wire [2:0] need_pool, need_vc; // 完整一至四拍的独立池与VC数量。
    wire [3:0] flag_start; // 每端口首拍实际发送事件。
    wire [2499:0] port_packets; // 四份有效、端口、VC、池及619位原生负载。
    wire [624:0] selected_packet; // 唯一当前槽的完整发送内容。
    wire raw_valid, raw_pool; // 送入公共typed叶的真实事件字段。
    wire [1:0] raw_port, raw_vc; // 已选端口与VC。
    wire [618:0] raw_payload; // 已预约首拍或已保存尾拍。
    genvar gp, gb; // 常量展开端口状态及三份尾拍。
    assign candidate_num = i_candidate_payload[523:522]; // 619位固定布局中的首拍长度。
    assign beat_mask = {(&candidate_num), candidate_num[1], (|candidate_num), 1'b1}; // 长度一至四的低位连续掩码。
    assign pool_mask = i_candidate_pools & beat_mask; // 每拍池选择均保留，不要求全笔一致。
    assign vc_mask = ~i_candidate_pools & beat_mask; // 非池拍消耗同一候选VC账户。
    assign need_pool = {2'd0,pool_mask[0]} + {2'd0,pool_mask[1]} + {2'd0,pool_mask[2]} + {2'd0,pool_mask[3]}; // 三位相加表示最大四拍。
    assign need_vc = {2'd0,vc_mask[0]} + {2'd0,vc_mask[1]} + {2'd0,vc_mask[2]} + {2'd0,vc_mask[3]}; // 专用账户需求独立统计。
    assign o_candidate_error = i_rstn && i_candidate_valid && (!(C_PORT_MASK[i_candidate_port]) || !( &flag_geometry)); // 仅错误端口或几何为候选诊断。
    assign o_candidate_accepted = |flag_start; // 没有ready伪预约，接纳即首拍真实发送。
    assign o_credit_error_sticky = reg_credit_error_sticky || o_credit_error; // 当前注册账本错误立即封锁新发送。
    assign flag_active = i_rstn && i_credit_connected && i_beats_connected && !o_credit_error_sticky; // 三方共享同一复位和实际连接状态。
    assign o_tdm_known = reg_tdm_known; // 原样暴露注册相位状态。
    assign o_tdm_port = reg_tdm_port; // 复位沿后未知相位端口为零。
    always @(posedge i_clk) begin // 粘滞诊断与信用银行同域更新。
        if (!i_rstn) reg_credit_error_sticky <= 1'b0; // 同步复位清空失败历史。
        else if (o_credit_error) reg_credit_error_sticky <= 1'b1; // 不把非法归还当可自动恢复的协议事件。
    end // 结束诊断寄存器。
    always @(posedge i_clk) begin // 通道独立相位无空闲停顿。
        if (!i_rstn) begin // 同步复位撤销所有旧相位。
            reg_tdm_known <= 1'b0; // 首次发送前不限定端口槽。
            reg_tdm_port <= 2'd0; // 确定无效相位值。
        end else if (reg_tdm_known) begin // 已知相位每沿推进。
            reg_tdm_port <= (reg_tdm_port + 2'd1) & C_PHASE_MASK; // 空闲也不可冻结相位。
        end else if (o_candidate_accepted) begin // 首次真实接纳决定下一拍所属端口。
            reg_tdm_known <= 1'b1; // 信用或候选阻塞不能建立相位。
            reg_tdm_port <= (i_candidate_port + 2'd1) & C_PHASE_MASK; // 下一槽为首端口之后的配置端口。
        end // 结束相位建立或推进。
    end // 结束TDM状态更新。
    generate // 独立常量字段比较避免推断可变格式。
        for (gb = 0; gb < 4; gb = gb + 1) begin : gen_geometry // 比较所有实际声明的拍。
            localparam [1:0] C_BEAT = gb[1:0]; // 两位拍索引。
            wire unused_geometry_fields; // Src、授权、数据及错误保留到实际输出，几何不检查。
            wire flag_declared; // 拍零总声明，其他拍才比较长度。
            wire [618:0] word_fields; // 当前完整原生拍内容。
            assign word_fields = i_candidate_payload[gb*619 +: 619]; // 低619位为Beat零。
            assign unused_geometry_fields = ^{word_fields[618:545],word_fields[521:10],word_fields[2]}; // 显式标记不作几何比较的完整原生字段。
            if (gb == 0) begin : gen_first // 首拍几何固定存在。
                assign flag_declared = 1'b1; // 首拍始终存在。
            end else begin : gen_later // 其余拍由首长度声明。
                assign flag_declared = C_BEAT <= candidate_num; // 仅尾拍按长度声明。
            end // 结束常量拍分类。
            assign flag_geometry[gb] = (candidate_num == 2'd0) || !flag_declared || ((word_fields[523:522] == candidate_num) && (word_fields[534:524] == i_candidate_payload[534:524]) && (word_fields[544:535] == i_candidate_payload[544:535]) && (word_fields[9:6] == i_candidate_payload[9:6]) && (word_fields[1:0] == i_candidate_payload[1:0]) && (word_fields[5:4] == C_BEAT) && (word_fields[3] == (C_BEAT == candidate_num))); // Src是可选debug，不参与功能准入；single的Offset与Last完全透明。
        end // 结束多拍几何检查。
        for (gp = 0; gp < 4; gp = gp + 1) begin : gen_ports // 四位原生端口中只实现配置状态。
            localparam [1:0] C_PORT = gp[1:0]; // 当前端口常量。
            if (gp < C_NUM_PORTS) begin : gen_used // 已配置端口拥有独立尾拍存储。
                reg reg_busy; // 首拍之后尚有连续本端口槽的尾拍。
                reg [1:0] reg_index, reg_last, reg_vc; // 当前尾拍编号、最后拍编号和冻结VC。
                reg [3:0] reg_pools; // 完整每拍池选择，避免候选变化污染尾拍。
                wire [1856:0] saved_tail; // 三个619位尾拍，最多完整四拍响应。
                wire [618:0] tail_word; // 当前索引的已保存负载。
                wire [C_CREDIT_WIDTH-1:0] vc_balance, pool_balance; // 沿前真实账户余额，不旁路同沿返回。
                wire flag_slot, flag_tail, flag_enough; // 槽、尾拍和整笔信用资格。
                assign vc_balance = o_balances[(gp*5)*C_CREDIT_WIDTH + (i_candidate_vc*C_CREDIT_WIDTH) +: C_CREDIT_WIDTH]; // 专用账户按候选VC选择。
                assign pool_balance = o_balances[(gp*5+4)*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]; // 单共享池独立预约。
                assign flag_enough = (vc_balance >= {{(C_CREDIT_WIDTH-3){1'b0}},need_vc}) && (pool_balance >= {{(C_CREDIT_WIDTH-3){1'b0}},need_pool}); // 首拍前必须拥有全部尾拍信用。
                assign flag_slot = !reg_tdm_known || (reg_tdm_port == C_PORT); // 相位未建立时可由任一合格端口启动。
                assign flag_start[gp] = flag_active && i_candidate_valid && (i_candidate_port == C_PORT) && !reg_busy && flag_slot && (&flag_geometry) && o_init_confirmed[gp] && flag_enough; // 首拍接纳与实际发送是同一事件。
                assign flag_tail = flag_active && reg_tdm_known && (reg_tdm_port == C_PORT) && reg_busy; // 预约后的尾拍不再依赖候选或其他端口。
                assign tail_word = (saved_tail[0 +: 619] & {619{reg_index == 2'd1}}) | (saved_tail[619 +: 619] & {619{reg_index == 2'd2}}) | (saved_tail[1238 +: 619] & {619{reg_index == 2'd3}}); // 常量拍片选择完整数据和所有控制字段。
                assign port_packets[gp*625 +: 625] = ({1'b1,C_PORT,i_candidate_vc,i_candidate_pools[0],i_candidate_payload[618:0]} & {625{flag_start[gp]}}) | ({1'b1,C_PORT,reg_vc,reg_pools[reg_index],tail_word} & {625{flag_tail}}); // 末尾拍当槽保守不接同端口新首拍。
                assign o_busy[gp] = reg_busy; // 只反映仍保存的尾拍所有权。
                always @(posedge i_clk) begin // 本端口尾拍元信息原子保存。
                    if (!i_rstn) begin // 复位取消未发尾拍，与银行统一清零。
                        reg_busy <= 1'b0; // 不得泄漏旧响应。
                        reg_index <= 2'd0; // 确定复位索引。
                        reg_last <= 2'd0; // 确定复位长度。
                        reg_vc <= 2'd0; // 确定复位账户。
                        reg_pools <= 4'd0; // 确定复位池元信息。
                    end else if (flag_start[gp]) begin // 首拍已发才保存完整尾部。
                        reg_busy <= (candidate_num != 2'd0); // single即使Last零也不持有后续槽。
                        reg_index <= 2'd1; // 下一次本端口槽发送Beat一。
                        reg_last <= candidate_num; // 编码也等于最后拍索引。
                        reg_vc <= i_candidate_vc; // 冻结本笔专用VC。
                        reg_pools <= i_candidate_pools; // 保存逐拍池计划。
                    end else if (flag_tail) begin // 每次本端口实际发送推进一拍。
                        if (reg_index == reg_last) reg_busy <= 1'b0; // 完整尾部结束后释放端口。
                        else reg_index <= reg_index + 2'd1; // 非末拍继续下一个本端口槽。
                    end // 结束尾拍元信息更新。
                end // 结束本端口元信息寄存器。
                for (gb = 1; gb < 4; gb = gb + 1) begin : gen_tail // 只保存可能发送的三个尾拍。
                    localparam [1:0] C_BEAT = gb[1:0]; // 当前尾拍编号常量。
                    reg [618:0] reg_word; // 原生完整字段与数据不可丢弃。
                    assign saved_tail[(gb-1)*619 +: 619] = reg_word; // 常量布局保存原始序列。
                    always @(posedge i_clk) begin // 保存候选后允许上游立即变化。
                        if (!i_rstn) reg_word <= 619'd0; // 同步清除旧所有权中的负载。
                        else if (flag_start[gp] && (candidate_num >= C_BEAT)) reg_word <= i_candidate_payload[gb*619 +: 619]; // 未声明的尾拍不写入也不发送。
                    end // 结束完整尾拍寄存器。
                end // 结束尾拍存储展开。
            end else begin : gen_unused // 未配置端口没有信用或发送状态。
                assign flag_start[gp] = 1'b0; // 无效端口不能接纳。
                assign o_busy[gp] = 1'b0; // 未配置端口确定空闲。
                assign port_packets[gp*625 +: 625] = 625'd0; // 未配置端口不污染输出选择。
            end // 结束端口配置条件。
        end // 结束端口展开。
    endgenerate // 结束几何与状态常量生成。
    assign selected_packet = port_packets[0 +: 625] | port_packets[625 +: 625] | port_packets[1250 +: 625] | port_packets[1875 +: 625]; // TDM保证至多一个端口驱动。
    assign {raw_valid,raw_port,raw_vc,raw_pool,raw_payload} = selected_packet; // 一次选路携带完整原生事件。
    upli_credit_bank #( // 只实例一次真实Read Response信用银行。
        .C_NUM_PORTS(C_NUM_PORTS), .C_CREDIT_WIDTH(C_CREDIT_WIDTH), .C_DEFAULT_CAPACITY(C_DEFAULT_CAPACITY), .C_CAPACITIES(C_CAPACITIES), // 透传每账户容量。
        .C_INIT_COUNT_WIDTH(C_INIT_COUNT_WIDTH), .C_INIT_CYCLES(C_INIT_CYCLES) // 保持真实初始化过滤参数。
    ) u_credit ( // 每拍扣账来自实际typed输出，不来自候选预约。
        .i_clk(i_clk), .i_rstn(i_rstn), .i_credit_connected(i_credit_connected), .i_beats_connected(i_beats_connected), // 同域连接与复位。
        .i_credit_valid(i_credit_valid), .i_credit_pool(i_credit_pool), .i_credit_vc(i_credit_vc), .i_credit_num(i_credit_num), .i_credit_init_done(i_credit_init_done), // 完整反向信用事件。
        .i_send_valid(o_valid), .i_send_port(o_port), .i_send_vc(o_vc), .i_send_pool(o_pool), // 实际每拍只消耗一个对应账户信用。
        .o_balances(o_balances), .o_init_confirmed(o_init_confirmed), .o_error(o_credit_error) // 真实银行状态与错误。
    ); // 结束唯一信用银行实例。
    upli_read_response_channel u_channel ( // 复用完整原生typed与公共parity叶。
        .i_rstn(i_rstn), .i_valid(raw_valid), .i_port(raw_port), .i_vc(raw_vc), .i_pool(raw_pool), // 与真实扣账事件一致。
        .i_auth_tag(raw_payload[618:555]), .o_auth_tag(o_auth_tag), // 完整auth_tag字段经实际typed叶输出。
        .i_src(raw_payload[554:545]), .o_src(o_src), // 完整src字段经实际typed叶输出。
        .i_dst(raw_payload[544:535]), .o_dst(o_dst), // 完整dst字段经实际typed叶输出。
        .i_tag(raw_payload[534:524]), .o_tag(o_tag), // 完整tag字段经实际typed叶输出。
        .i_num_beats(raw_payload[523:522]), .o_num_beats(o_num_beats), // 完整num_beats字段经实际typed叶输出。
        .i_data(raw_payload[521:10]), .o_data(o_data), // 完整data字段经实际typed叶输出。
        .i_status(raw_payload[9:6]), .o_status(o_status), // 完整status字段经实际typed叶输出。
        .i_offset(raw_payload[5:4]), .o_offset(o_offset), // 完整offset字段经实际typed叶输出。
        .i_last(raw_payload[3:3]), .o_last(o_last), // 完整last字段经实际typed叶输出。
        .i_data_error(raw_payload[2:2]), .o_data_error(o_data_error), // 完整data_error字段经实际typed叶输出。
        .i_type_info(raw_payload[1:0]), .o_type_info(o_type_info), // 完整type_info字段经实际typed叶输出。
        .o_valid(o_valid), .o_port(o_port), .o_vc(o_vc), .o_pool(o_pool), // 发送事件输出不得绕过typed叶。
        .o_valid_parity(o_valid_parity), .o_auth_tag_parity(o_auth_tag_parity), .o_data_parity(o_data_parity), .o_control_parity(o_control_parity) // 校验由公共原语计算真实原生输出。
    ); // 结束原生Read Response发送叶。
    assign o_payload = {o_auth_tag,o_src,o_dst,o_tag,o_num_beats,o_data,o_status,o_offset,o_last,o_data_error,o_type_info}; // debug负载从真正输出重构，不能形成旁路自证。
endmodule // 结束完整分阶段Read Response发送器候选。
`default_nettype wire // 恢复后续独立编译单元的默认规则。
