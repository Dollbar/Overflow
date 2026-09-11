// Native normal Request/OrigData full-credit admission and per-port TDM control.
// 日期2026-09-08；Common2.0 2.5/2.6/2.7.8子集，payload须在接受前完整就绪。
// Banks debit actual beats; active per-port descriptors reserve unspent data credits.
// 本模块只存控制元数据；不把本地候选握手或has_data编码加入线上协议。
`timescale 1ps/1ps // 所有控制属于单一UPLI上升沿时钟域。
module upli_burst_control #( // 原生正常突发完整信用准入和连续时隙控制模块。
    parameter integer C_NUM_PORTS = 1, // 实际station支持一、二或四port。
    parameter integer C_CREDIT_WIDTH = 4 // 输入实际银行余额的计数位宽，允许三至十六位。
) ( // 本地候选、真实沿前信用和原生发出接口分离。
    input wire i_clk, // 状态统一在UPLI共同上升沿更新。
    input wire i_rstn, // 同步低有效复位终止全部未完成正常burst。
    input wire i_beats_connected, // 双向实际握手已经完成，保持到共同reset。
    input wire i_candidate_valid, // 本地调度器呈现一个完整就绪候选。
    input wire [1:0] i_candidate_port, // 候选对应的物理port，未启用编码不能别名。
    input wire [1:0] i_candidate_vc, // 请求及其所有原数据拍的原VC。
    input wire i_candidate_pool, // 请求拍消耗pool信用而非专用VC时置位。
    input wire i_candidate_has_data, // 本地已解码的带数据属性，不是新增线编码。
    input wire [1:0] i_candidate_num_beats, // 带数据时实际数据拍数减一，零表示一拍。
    input wire [3:0] i_candidate_data_pools, // 低位从首拍起的完整本地pool预约计划。
    input wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] i_req_balances, // 沿前真实请求银行余额，逐port VC0..3/pool。
    input wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] i_data_balances, // 沿前真实原数据银行余额，包含尚未发出的预约。
    input wire [3:0] i_req_init, // 请求银行已完成连续确认的初始化资格。
    input wire [3:0] i_data_init, // 原数据银行已完成连续确认的初始化资格。
    output wire o_candidate_accepted, // 本沿实际请求发出即取得候选控制/payload所有权。
    output wire o_req_valid, // 本沿实际发出的请求有效，不额外插入流水周期。
    output wire [1:0] o_req_port, // 有效请求的原始port，无效时零。
    output wire [1:0] o_req_vc, // 有效请求的原始VC，无效时零。
    output wire o_req_pool, // 本沿请求实际使用的信用类型。
    output wire o_data_valid, // 本沿实际OrigData有效，首拍与请求同拍。
    output wire [1:0] o_data_port, // 本沿OrigData所属原请求port。
    output wire [1:0] o_data_vc, // 本沿OrigData所属原请求VC，不随叠加read改变。
    output wire o_data_pool, // 该数据拍启动前预选的实际信用类型。
    output wire [1:0] o_data_offset, // 原请求中从零递增的数据拍索引。
    output wire o_data_last, // 仅真实末数据拍置位，无效时零。
    output wire [3:0] o_busy, // 每port尚有数据尾部未发出，未启用port恒零。
    output wire o_tdm_known, // 首个请求已实际建立共享Req/OrigData时隙相位。
    output wire [1:0] o_tdm_port // 当前时隙的port，尚未建立或reset后为零。
); // 结束原生正常突发控制接口。
    localparam [31:0] C_PORTS = C_NUM_PORTS; // 非负常量用于固定生成和归约边界。
    localparam [1:0] C_PHASE_MASK = (C_NUM_PORTS == 4) ? 2'b11 : (C_NUM_PORTS == 2) ? 2'b01 : 2'b00; // 一、二、四port的精确模计数掩码。
    reg reg_phase_known; // 只由首个实际接受请求建立的相位有效寄存器。
    reg [1:0] reg_phase; // 当前UPLI周期的共享Req/OrigData TDM值。
    wire [3:0] data_mask; // 二进制长度直接形成温度码有效位，避免枚举case的冗余译码。
    wire [3:0] required_pools; // 仅声明拍数内的pool预约位，忽略无效高位。
    wire [3:0] required_vcs; // 专用VC需求直接由有效非pool拍形成，不串接总数减法。
    wire [3:0] pool_threshold, vc_threshold; // 位零至三分别表示完整需求至少一至四个信用。
    wire [C_NUM_PORTS-1:0] new_request; // 每port独立准入，实际每沿至多一个命中。
    wire [C_NUM_PORTS*9-1:0] port_data; // 各port候选实际数据事件的固定九位编码。
    reg [8:0] selected_data; // 唯一时隙的数据事件按位归约，避免串联优先级。
    integer select_index; // 静态有界port归约索引。
    genvar gen_port; // 编译时生成各port独立描述符状态。
    genvar gen_account; // 编译时并行检查各VC和pool账户，避免宽余额多选后再比较。
    assign data_mask = {(&i_candidate_num_beats), i_candidate_num_beats[1], (|i_candidate_num_beats), 1'b1}; // 一至四拍的掩码依次为0001、0011、0111、1111。
    assign required_pools = i_candidate_data_pools & data_mask; // 未声明拍的任意输入不增加预约信用。
    assign required_vcs = ~i_candidate_data_pools & data_mask; // 有效拍恰好使用pool或原VC之一。
    assign pool_threshold[0] = |required_pools; // 任一有效pool拍就需要至少一个共享信用。
    assign pool_threshold[1] = (&required_pools[1:0]) || (&required_pools[3:2]) || ((|required_pools[1:0]) && (|required_pools[3:2])); // 至少两拍用两半内部成对或跨半成对检测。
    assign pool_threshold[2] = ((&required_pools[1:0]) && (|required_pools[3:2])) || ((|required_pools[1:0]) && (&required_pools[3:2])); // 三拍至少有一半成对，另一半非空。
    assign pool_threshold[3] = &required_pools; // 四拍都使用pool才要求第四个共享信用。
    assign vc_threshold[0] = |required_vcs; // 任一有效非pool拍需要一个原VC信用。
    assign vc_threshold[1] = (&required_vcs[1:0]) || (&required_vcs[3:2]) || ((|required_vcs[1:0]) && (|required_vcs[3:2])); // 原VC至少两拍使用独立并行组合谓词。
    assign vc_threshold[2] = ((&required_vcs[1:0]) && (|required_vcs[3:2])) || ((|required_vcs[1:0]) && (&required_vcs[3:2])); // 原VC第三个信用不能由首拍是否可发代替。
    assign vc_threshold[3] = &required_vcs; // 原VC完整四拍需求单独检验。
    assign o_req_valid = |new_request; // 唯一合格本地候选成为实际原生请求。
    assign o_candidate_accepted = o_req_valid; // 本地所有权转移与原生发出是同一事件。
    assign o_req_port = i_candidate_port & {2{o_req_valid}}; // 无效请求不泄漏当前候选字段。
    assign o_req_vc = i_candidate_vc & {2{o_req_valid}}; // 原请求VC在有效时原样传递。
    assign o_req_pool = i_candidate_pool && o_req_valid; // 请求信用类型只在实际发出时有效。
    assign {o_data_valid, o_data_port, o_data_vc, o_data_pool, o_data_offset, o_data_last} = selected_data; // 全部数据控制字段来自同一真实事件。
    assign o_tdm_known = reg_phase_known; // 相位有效只在共同上升沿改变。
    assign o_tdm_port = reg_phase; // 观察真实时隙寄存器，不根据当前候选重新定义相位。
    always @(*) begin // 唯一TDM slot保证至多一个port贡献数据事件。
        selected_data = 9'd0; // 无有效数据的所有字段确定为零。
        for (select_index = 32'd0; select_index < C_PORTS; select_index = select_index+32'd1) begin // 静态归约已实现port。
            selected_data = selected_data | port_data[select_index*9 +: 9]; // 不把其它port的活动busy当作全station阻塞。
        end // 结束各port真实事件归约。
    end // 结束完整赋值的数据选择组合逻辑。
    always @(posedge i_clk) begin // 独立保存首次实际请求建立的TDM资格。
        if (!i_rstn) reg_phase_known <= 1'b0; // reset忘记前一epoch相位。
        else if (o_req_valid) reg_phase_known <= 1'b1; // 被拒绝的候选绝不能建立相位。
    end // 结束相位有效寄存器。
    always @(posedge i_clk) begin // 每个已建立的周期都前进，包括无任何有效beat的idle。
        if (!i_rstn) reg_phase <= 2'd0; // 新epoch在首个实际请求前无相位且观察值零。
        else if (reg_phase_known) reg_phase <= (reg_phase+2'd1) & C_PHASE_MASK; // 既有相位不能因候选或idle改变步进。
        else if (o_req_valid) reg_phase <= (i_candidate_port+2'd1) & C_PHASE_MASK; // 首请求占当前候选port，沿后进入下一port。
    end // 结束共享TDM时隙寄存器。
    generate // 结构参数与各port独立活动描述符在编译时固定。
        if (((C_NUM_PORTS != 1) && (C_NUM_PORTS != 2) && (C_NUM_PORTS != 4)) || (C_CREDIT_WIDTH < 3) || (C_CREDIT_WIDTH > 16)) begin : gen_invalid // 不静默生成非法端口/计数形状。
            upli_burst_parameters_invalid Invalid_Inst (); // 未定义层次强制非法参数编译失败。
        end // 结束参数保护。
        if (C_NUM_PORTS < 4) begin : gen_unused_init // 原生四位确认形状的未用部分不参与准入。
            wire unused_init_fields; // 明确记录未启用port的有意忽略字段。
            assign unused_init_fields = &{i_req_init[3:C_NUM_PORTS], i_data_init[3:C_NUM_PORTS]}; // 不额外制造信用或虚假硬件负载。
        end // 结束未用确认字段的边界说明。
        for (gen_port = 32'd0; gen_port < 32'd4; gen_port = gen_port+32'd1) begin : gen_ports // 保持四位原生busy观察形状。
            if (gen_port < C_NUM_PORTS) begin : gen_active // 仅有效port生成原描述符存储。
                localparam [1:0] C_PORT = gen_port[1:0]; // 显式截取已限定零至三的编译期port编码。
                reg reg_active; // 此port保留尚未完成的数据尾部及信用预约。
                reg [1:0] reg_vc, reg_last; // 原请求VC及末数据offset，互相独立寄存。
                reg [3:0] reg_pools; // 启动前已完整批准的逐拍pool信用计划。
                reg [1:0] cnt_offset; // 本port下一待发数据offset，活动时为一至三。
                wire [4:0] req_available; // 请求五账户先并行检查是否至少有一个信用。
                wire [19:0] data_capabilities; // 五账户各四位独立表示可提供至少一至四个信用。
                wire [15:0] data_vc_capabilities; // 四个专用VC的固定宽度信用能力，不包含pool。
                wire [3:0] selected_vc_capability, pool_capability; // 先选择信用能力，再与完整需求并行相交。
                wire req_ready, data_ready, data_eligible; // 单比特信用选择与独立数据所有权资格。
                wire correct_slot, new_data, tail_data, data_last; // 本port时隙、首拍、尾部发出及结束条件。
                for (gen_account = 32'd0; gen_account < 32'd5; gen_account = gen_account+32'd1) begin : gen_accounts // 各账户只看本port原始沿前余额。
                    wire [C_CREDIT_WIDTH-1:0] data_balance; // 固定切片，无候选VC控制的宽多选器。
                    wire at_least_four; // 任意高于低二位的位为一就足够最大四拍需求。
                    assign data_balance = i_data_balances[(gen_port*5+gen_account)*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]; // 使用全部计数位，不截断大余额。
                    assign at_least_four = |data_balance[C_CREDIT_WIDTH-1:2]; // 三至十六位宽均精确保留至少四的判断。
                    assign req_available[gen_account] = |i_req_balances[(gen_port*5+gen_account)*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]; // 请求只消耗一个信用，高位非零同样有效。
                    assign data_capabilities[gen_account*4 +: 4] = {at_least_four, (at_least_four || (&data_balance[1:0])), (|data_balance[C_CREDIT_WIDTH-1:1]), (|data_balance)}; // 余额能力独立于当前长度/pool计划计算，所有高位都保留。
                end // 结束五账户并行信用比较。
                assign data_vc_capabilities = data_capabilities[15:0]; // 原VC选择只覆盖四个专用账户。
                assign selected_vc_capability = data_vc_capabilities[i_candidate_vc*4 +: 4]; // 在与需求比较之前完成固定四位能力选择。
                assign pool_capability = data_capabilities[19:16]; // 本port独立共享pool的完整能力。
                assign req_ready = i_candidate_pool ? req_available[4] : req_available[{1'b0, i_candidate_vc}]; // 请求只在单比特条件上选择VC或pool。
                assign data_ready = !(|(vc_threshold & ~selected_vc_capability)) && !(|(pool_threshold & ~pool_capability)); // 只有所有已要求门限都有能力才准入，需求路径不再穿过VC选择器。
                assign data_eligible = !reg_active && i_data_init[gen_port] && data_ready; // 旧末拍当沿仍不能获取新数据所有权。
                assign correct_slot = !reg_phase_known || (reg_phase == C_PORT); // 首请求可选任一有效port，其后只能使用固定相位。
                assign new_request[gen_port] = i_rstn && i_beats_connected && i_candidate_valid && (i_candidate_port == C_PORT) && correct_slot && i_req_init[gen_port] && req_ready && (!i_candidate_has_data || data_eligible); // 整笔信用、原时隙及旧所有权共同限制准入。
                assign new_data = new_request[gen_port] && i_candidate_has_data; // 首数据与对应请求严格同沿。
                assign tail_data = i_rstn && i_beats_connected && reg_phase_known && (reg_phase == C_PORT) && reg_active; // 已启动尾部在本port每个连续slot无条件发出，不等待新余额或候选。
                assign data_last = cnt_offset == reg_last; // 原长度决定真实末拍，不能受新read候选污染。
                assign port_data[gen_port*9 +: 9] = ({9{tail_data}} & {1'b1, C_PORT, reg_vc, reg_pools[cnt_offset], cnt_offset, data_last}) | ({9{new_data}} & {1'b1, C_PORT, i_candidate_vc, required_pools[0], 2'd0, (i_candidate_num_beats == 2'd0)}); // 旧尾部与新首拍由旧busy保证互斥，并行合并不再串接优先选择。
                assign o_busy[gen_port] = reg_active; // 只有未发完尾部持有活动所有权。
                always @(posedge i_clk) begin // 独立管理该port的活动描述符有效性。
                    if (!i_rstn) reg_active <= 1'b0; // reset取消而非继续发出旧数据。
                    else if (new_data) reg_active <= (i_candidate_num_beats != 2'd0); // 布尔比较显式括号，一拍请求不保留尾部预约。
                    else if (tail_data && data_last) reg_active <= 1'b0; // 仅实际末拍发出后释放该port给新写。
                end // 结束该port活动有效寄存器。
                always @(posedge i_clk) begin // 单独保存原请求VC以隔离read叠加。
                    if (!i_rstn) reg_vc <= 2'd0; // 新epoch不保留旧请求字段。
                    else if (new_data) reg_vc <= i_candidate_vc; // 仅新带数据请求获取控制所有权。
                end // 结束原VC保存寄存器。
                always @(posedge i_clk) begin // 单独保存原请求末offset。
                    if (!i_rstn) reg_last <= 2'd0; // reset清除原长度字段。
                    else if (new_data) reg_last <= i_candidate_num_beats; // 末offset恰为NumBeats编码。
                end // 结束原长度保存寄存器。
                always @(posedge i_clk) begin // 单独保存已批准的完整数据pool计划。
                    if (!i_rstn) reg_pools <= 4'd0; // reset取消所有旧预约类型。
                    else if (new_data) reg_pools <= required_pools; // 无效高位明确清除，不记录当前read候选。
                end // 结束逐拍信用类型寄存器。
                always @(posedge i_clk) begin // 只在该port真实数据发出时推进尾部offset。
                    if (!i_rstn) cnt_offset <= 2'd0; // reset取消旧剩余位置。
                    else if (new_data) cnt_offset <= 2'd1; // 首拍零在当前沿发出，下一待发拍为一。
                    else if (tail_data && !data_last) cnt_offset <= cnt_offset+2'd1; // 只增加未结束的真实尾部，避免末拍回绕产生假首拍。
                end // 结束该port数据尾部位置寄存器。
            end else begin : gen_unused // 未启用port没有描述符存储。
                assign o_busy[gen_port] = 1'b0; // 无效port不可能拥有旧数据或信用预约。
            end // 结束已实现与未用port分支。
        end // 结束四port结构展开。
    endgenerate // 结束原生正常突发控制生成结构。
endmodule // 结束upli_burst_control正常请求和OrigData调度模块。
