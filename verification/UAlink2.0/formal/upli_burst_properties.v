// Independent normal-burst specification: countdown plus shifted pool queue.
// 只用于数字控制形式验证；银行快照任意，连接固定有效，不含实际FSM或payload。
`timescale 1ps/1ps // 时间单位与原生UPLI控制一致，SAT不模拟模拟时钟。
module upli_burst_properties #( // 独立检查整笔信用准入、TDM和尾部顺序的形式性质模块。
    parameter integer C_NUM_PORTS = 1, // 一、二或四port的有限形式配置。
    parameter integer C_CREDIT_WIDTH = 4 // 三至十六位余额全二进制取值均为符号输入。
) ( // 除连接资格固定有效外，其余候选、信用及reset完全自由。
    input wire i_clk, // 唯一同步UPLI时钟。
    input wire i_rstn, // 共同同步reset，允许重复出现。
    input wire i_candidate_valid, // 任意本地完整候选有效性。
    input wire [1:0] i_candidate_port, // 包含未启用编码的自由port输入。
    input wire [1:0] i_candidate_vc, // 四种原VC均独立符号化。
    input wire i_candidate_pool, // 请求使用共享或专用信用。
    input wire i_candidate_has_data, // 本地已解码数据属性。
    input wire [1:0] i_candidate_num_beats, // 声明一至四拍的长度减一。
    input wire [3:0] i_candidate_data_pools, // 包含未声明高位的完整自由pool计划。
    input wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] i_req_balances, // 全位宽请求账户快照，不固定为仿真的小余额。
    input wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] i_data_balances, // 全位宽原数据账户快照，包括高位非零。
    input wire [3:0] i_req_init, // 银行已经过滤的初始化资格。
    input wire [3:0] i_data_init, // 原数据银行独立初始化资格。
    output wire o_violation // 任一参考事件或状态不符就使证明失败。
); // 结束独立正常突发形式接口。
    localparam [31:0] C_PORTS = C_NUM_PORTS; // 明确无符号静态port归约边界。
    localparam [1:0] C_LAST_PORT = (C_NUM_PORTS == 4) ? 2'd3 : (C_NUM_PORTS == 2) ? 2'd1 : 2'd0; // 参考相位用末port回零，不复用DUT模掩码。
    wire actual_accept, actual_req, actual_req_pool, actual_data, actual_data_pool, actual_last; // 真实DUT所有原生事件标志。
    wire [1:0] actual_req_port, actual_req_vc, actual_data_port, actual_data_vc, actual_offset; // 真实DUT全部事件元数据。
    wire [3:0] actual_busy, expected_busy; // 实际活动位与独立剩余数量派生的活动位。
    wire actual_known; // 真实相位建立资格。
    wire [1:0] actual_phase; // 真实当前TDM port。
    wire [C_NUM_PORTS-1:0] requests; // 独立逐port完整准入事件。
    wire [C_NUM_PORTS*9-1:0] data_events; // 独立倒数模型产生的全部原数据字段。
    wire expected_req; // 参考实际请求事件，不直接使用DUT接受信号。
    reg [8:0] expected_data; // 独立port事件的唯一slot归约结果。
    reg reg_known; // 参考首次实际接受建立的相位有效位。
    reg [1:0] reg_phase; // 参考每个周期包含idle的相位。
    reg [31:0] pool_count; // 用简单逐拍整数循环求完整pool需求，独立于DUT阈值网络。
    wire [31:0] vc_count; // 参考专用VC完整需求为总拍数减pool数量。
    integer beat_index, port_index; // 静态有界独立计数与事件归约索引。
    genvar gen_port; // 独立逐port剩余队列生成索引。
    upli_burst_control #( .C_NUM_PORTS(C_NUM_PORTS), .C_CREDIT_WIDTH(C_CREDIT_WIDTH) ) Control_Inst ( // 实例化真实产品控制RTL，不用自由寄存器替代。
        .i_clk(i_clk), .i_rstn(i_rstn), .i_beats_connected(1'b1), // 固定正常已建连资格；真正四信号握手留待集成。
        .i_candidate_valid(i_candidate_valid), .i_candidate_port(i_candidate_port), .i_candidate_vc(i_candidate_vc), .i_candidate_pool(i_candidate_pool), // 任意请求候选进入实际DUT。
        .i_candidate_has_data(i_candidate_has_data), .i_candidate_num_beats(i_candidate_num_beats), .i_candidate_data_pools(i_candidate_data_pools), // 任意合法长度和pool编码。
        .i_req_balances(i_req_balances), .i_data_balances(i_data_balances), .i_req_init(i_req_init), .i_data_init(i_data_init), // 真实比较逻辑读取全位宽自由快照。
        .o_candidate_accepted(actual_accept), .o_req_valid(actual_req), .o_req_port(actual_req_port), .o_req_vc(actual_req_vc), .o_req_pool(actual_req_pool), // 请求事件全部观察。
        .o_data_valid(actual_data), .o_data_port(actual_data_port), .o_data_vc(actual_data_vc), .o_data_pool(actual_data_pool), .o_data_offset(actual_offset), .o_data_last(actual_last), // 原数据内容控制全部观察。
        .o_busy(actual_busy), .o_tdm_known(actual_known), .o_tdm_port(actual_phase) // 只读实际状态，不建立任何切点。
    ); // 结束真实控制模块实例。
    assign expected_req = |requests; // 已启用port中至多一个候选匹配。
    assign vc_count = {30'd0, i_candidate_num_beats}+32'd1-pool_count; // 总长度减逐拍pool计数构成独立算术规格。
    assign o_violation = (actual_accept != expected_req) || (actual_req != expected_req) || (actual_req_port != (i_candidate_port & {2{expected_req}})) || (actual_req_vc != (i_candidate_vc & {2{expected_req}})) || (actual_req_pool != (i_candidate_pool && expected_req)) || ({actual_data, actual_data_port, actual_data_vc, actual_data_pool, actual_offset, actual_last} != expected_data) || (actual_busy != expected_busy) || (actual_known != reg_known) || (actual_phase != reg_phase); // 同时比较全部可见事件、元数据和所有权，不仅比较是否有流量。
    always @(*) begin // 逐拍循环求pool完整数量，未声明高位不参与。
        pool_count = 32'd0; // 完整组合赋值，最多四个。
        for (beat_index = 32'd0; beat_index < 32'd4; beat_index = beat_index+32'd1) begin // 常量四次展开参考循环。
            if ((beat_index < ({30'd0, i_candidate_num_beats}+32'd1)) && i_candidate_data_pools[beat_index]) pool_count = pool_count+32'd1; // 使用明确小于总长度的组合比较，只统计声明内pool拍。
        end // 结束独立需求数量统计。
    end // 结束完整pool计数组合参考。
    always @(*) begin // 独立归约参考TDM发出事件。
        expected_data = 9'd0; // 没有发出则所有字段均零。
        for (port_index = 32'd0; port_index < C_PORTS; port_index = port_index+32'd1) begin // 只包含声明port。
            expected_data = expected_data | data_events[port_index*9 +: 9]; // 同一参考slot只有一个port贡献事件。
        end // 结束参考数据事件归约。
    end // 结束完整赋值的参考数据输出。
    always @(posedge i_clk) begin // 参考相位资格只由独立准入建立。
        if (!i_rstn) reg_known <= 1'b0; // reset取消旧epoch相位。
        else if (expected_req) reg_known <= 1'b1; // 被阻塞候选绝不能建相位。
    end // 结束参考相位有效寄存器。
    always @(posedge i_clk) begin // 参考phase用显式末port回零推进。
        if (!i_rstn) reg_phase <= 2'd0; // 新epoch无相位时观察零。
        else if (reg_known) reg_phase <= (reg_phase == C_LAST_PORT) ? 2'd0 : reg_phase+2'd1; // idle也进入下一时隙。
        else if (expected_req) reg_phase <= (i_candidate_port == C_LAST_PORT) ? 2'd0 : i_candidate_port+2'd1; // 首个实际请求port后接连续时隙。
    end // 结束参考相位寄存器。
    generate // 独立模型以剩余数量和右移信用类型队列表示尾部。
        for (gen_port = 32'd0; gen_port < 32'd4; gen_port = gen_port+32'd1) begin : gen_ports // 保持四位busy观察形状。
            if (gen_port < C_NUM_PORTS) begin : gen_active // 仅有效port拥有参考尾部队列。
                localparam [1:0] C_PORT = gen_port[1:0]; // 明确固定port双位编码。
                reg [1:0] cnt_remaining; // 剩余一至三拍，零表示无活动尾部。
                reg [1:0] reg_vc, cnt_next; // 原VC和下一offset分别独立保存。
                reg [3:0] reg_pool_queue; // 后续逐拍pool从低位移出，独立于DUT按offset索引。
                wire [4*C_CREDIT_WIDTH-1:0] request_vcs, data_vcs; // 原始快照中的四专用账户。
                wire [C_CREDIT_WIDTH-1:0] request_balance, vc_balance, pool_balance; // 参考先选择完整计数再作整数比较。
                wire start_data, tail_data, slot; // 参考实际首数据、连续尾数据和时隙资格。
                assign request_vcs = i_req_balances[gen_port*5*C_CREDIT_WIDTH +: 4*C_CREDIT_WIDTH]; // 原请求四VC快照。
                assign data_vcs = i_data_balances[gen_port*5*C_CREDIT_WIDTH +: 4*C_CREDIT_WIDTH]; // 原数据四VC快照。
                assign request_balance = i_candidate_pool ? i_req_balances[(gen_port*5+4)*C_CREDIT_WIDTH +: C_CREDIT_WIDTH] : request_vcs[i_candidate_vc*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]; // 参考完整账户选择。
                assign vc_balance = data_vcs[i_candidate_vc*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]; // 参考原VC全位宽计数。
                assign pool_balance = i_data_balances[(gen_port*5+4)*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]; // 参考本port共享pool余额。
                assign slot = !reg_known || (reg_phase == C_PORT); // 首请求之前任一有效port可作为相位起点。
                assign requests[gen_port] = i_rstn && i_candidate_valid && (i_candidate_port == C_PORT) && slot && i_req_init[gen_port] && (request_balance != {C_CREDIT_WIDTH{1'b0}}) && (!i_candidate_has_data || ((cnt_remaining == 2'd0) && i_data_init[gen_port] && ({{(32-C_CREDIT_WIDTH){1'b0}}, vc_balance} >= vc_count) && ({{(32-C_CREDIT_WIDTH){1'b0}}, pool_balance} >= pool_count))); // 独立整数整笔比较，不复用阈值化准入。
                assign start_data = requests[gen_port] && i_candidate_has_data; // 首数据与独立参考请求同步。
                assign tail_data = i_rstn && reg_known && (reg_phase == C_PORT) && (cnt_remaining != 2'd0); // 每个自己的slot必须送出下一剩余拍。
                assign data_events[gen_port*9 +: 9] = tail_data ? {1'b1, C_PORT, reg_vc, reg_pool_queue[0], cnt_next, (cnt_remaining == 2'd1)} : start_data ? {1'b1, C_PORT, i_candidate_vc, i_candidate_data_pools[0], 2'd0, (i_candidate_num_beats == 2'd0)} : 9'd0; // 末拍由剩余数量等于一决定，不比较原末offset。
                assign expected_busy[gen_port] = cnt_remaining != 2'd0; // 独立剩余队列定义活动所有权。
                always @(posedge i_clk) begin // 参考剩余数量按每个实际slot倒数。
                    if (!i_rstn) cnt_remaining <= 2'd0; // reset丢弃旧尾部。
                    else if (start_data) cnt_remaining <= i_candidate_num_beats; // 首拍已经发出，剩余恰为长度减一。
                    else if (tail_data) cnt_remaining <= cnt_remaining-2'd1; // 不依赖DUT是否真的送出才推进参考。
                end // 结束独立剩余计数寄存器。
                always @(posedge i_clk) begin // 保存原VC，read叠加不能改写。
                    if (!i_rstn) reg_vc <= 2'd0; // 参考epoch字段清零。
                    else if (start_data) reg_vc <= i_candidate_vc; // 只有新带数据请求获取原VC。
                end // 结束参考原VC寄存器。
                always @(posedge i_clk) begin // 参考下一offset逐有效slot递增。
                    if (!i_rstn) cnt_next <= 2'd0; // reset取消旧offset。
                    else if (start_data) cnt_next <= 2'd1; // 首拍零同沿发出，后续起于一。
                    else if (tail_data) cnt_next <= cnt_next+2'd1; // 末拍后可回绕，非活动期间不作为有效字段使用。
                end // 结束参考下一位置寄存器。
                always @(posedge i_clk) begin // 参考pool队列按发送顺序右移。
                    if (!i_rstn) reg_pool_queue <= 4'd0; // reset清除旧信用类型队列。
                    else if (start_data) reg_pool_queue <= {1'b0, i_candidate_data_pools[3:1]}; // 首拍pool已使用，只保留后续候选位。
                    else if (tail_data) reg_pool_queue <= {1'b0, reg_pool_queue[3:1]}; // 每个slot丢弃当前低位进入下一拍。
                end // 结束参考右移信用类型队列。
            end else begin : gen_unused // 未启用port不产生任何参考所有权。
                assign expected_busy[gen_port] = 1'b0; // 未用busy位恒零。
            end // 结束独立参考有效port分支。
        end // 结束四位观察形状的参考生成。
    endgenerate // 结束独立倒数及移位形式模型。
endmodule // 结束真实控制RTL与独立规格的事件/状态比较顶层。
