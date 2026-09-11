// UPLI per-account receive storage and initial/normal credit handoff.
// 日期 2026-09-08；Common 2.0 2.6/4.3 子集，不包含 TL 解析、突发调度或线上 RAS。
// Native ingress has no ready; local retirement is atomic with metadata retention.
// 同步复位取消所有权；连接资格在复位前不得撤销，外部 SRAM 内容无需清零。
`timescale 1ps/1ps // 全部模块属于同一 UPLI 时钟域且 RTL 不使用延时。
module upli_receive_channel #( // 接收通道模块为每端口四 VC 和共享池实现真实存储信用闭环。
    parameter integer C_NUM_PORTS = 1, // 原生 station 配置允许一、二或四端口。
    parameter integer C_PAYLOAD_WIDTH = 32, // 透明保存任意正整数位宽的通道 payload。
    parameter integer C_CREDIT_WIDTH = 4, // 每账户逻辑容量计数为三至十六位。
    parameter [C_CREDIT_WIDTH-1:0] C_DEFAULT_CAPACITY = 3, // 未覆盖逐账户容量时使用可适应信用位宽的默认值。
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_CAPACITIES = {C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}, // 低位起依次为各端口 VC0..3 和共享池容量。
    parameter integer C_RETURN_DEPTH = 4, // 每端口正常信用元数据队列深度一至十六。
    parameter integer C_PENDING_WIDTH = (C_RETURN_DEPTH <= 1) ? 1 : (C_RETURN_DEPTH <= 3) ? 2 : (C_RETURN_DEPTH <= 7) ? 3 : (C_RETURN_DEPTH <= 15) ? 4 : 5 // 从返回深度派生的观察位宽，不允许独立改变。
) ( // 原生接收与本地消费接口语义明确分离。
    input wire i_clk, // 存储、初始化器和正常归还共用上升沿时钟。
    input wire i_rstn, // 同步低有效复位优先清除全部可见所有权。
    input wire i_credit_connected, // 对应通道信用返回方向已经建立。
    input wire i_beats_connected, // 双向连接均建立，仍需逐端口初始化资格。
    input wire i_receive_valid, // 原生 UPLI 本沿有一个 beat，不能因本地反压撤销。
    input wire [1:0] i_receive_port, // 入站 beat 的物理 port 字段。
    input wire [1:0] i_receive_vc, // 原始 VC 必须随真实 payload 保存。
    input wire i_receive_pool, // 原始信用类型，池中仍须保留原 VC。
    input wire [C_PAYLOAD_WIDTH-1:0] i_receive_payload, // 本组件不解析不透明通道内容。
    input wire [1:0] i_consumer_port, // 本地调度器选择消费哪个 port。
    input wire [2:0] i_consumer_account, // 账户零至三为 VC、四为 pool、五至七无效。
    input wire i_consumer_ready, // 本地消费者愿意接纳当前可提交的真实头。
    output wire [C_PAYLOAD_WIDTH-1:0] o_head_payload, // 所选账户的真实缓存头数据，无效时为零。
    output wire [1:0] o_head_vc, // 保存并读出的原始 VC，不由当前选择重构。
    output wire o_head_pool, // 保存并读出的原始信用类型。
    output wire o_head_valid, // 所选真实数据头可见，不表示返回队列也有空间。
    output wire o_consume_valid, // 真实头和元数据队列同时有效，配合 ready 才退休。
    output wire o_receive_accepted, // 上一采样沿的实际接收诊断，不是原生 ready。
    output wire [2:0] o_diagnostic, // 上一沿本地输入诊断，定义于接收契约而非协议线上编码。
    output wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_counts, // 每账户占用包括 SRAM、在途读和缓存。
    output wire [4*C_PENDING_WIDTH-1:0] o_pending_count, // 每端口尚未注册发布的退休元数据数量。
    output wire [3:0] o_credit_valid, // 初始与正常互斥发布的四端口有效信号。
    output wire [3:0] o_credit_pool, // 当前有效批次的真实信用类型。
    output wire [7:0] o_credit_vc, // 每端口两位的初始或原始 VC 字段。
    output wire [7:0] o_credit_num, // 每端口实际批次数量减一编码。
    output wire [3:0] o_credit_init_done // 每端口在最后初始批次后置位并保持至复位。
); // 结束接收通道参数与端口声明。
    localparam [31:0] C_SLOTS = C_NUM_PORTS*5; // 非负静态边界，一账户对应一个精确逻辑容量的 FIFO。
    localparam integer C_SAVED_WIDTH = C_PAYLOAD_WIDTH+3; // 实际需保存的 payload、原 VC 和 Pool 位。
    localparam integer C_WORD_WIDTH = ((C_SAVED_WIDTH+7)/8)*8; // 物理字节填充不改变线上格式或信用数。
    localparam [C_PENDING_WIDTH-1:0] C_RETURN_LIMIT = C_RETURN_DEPTH[C_PENDING_WIDTH-1:0]; // 对每端口返回数量使用相同深度及显式匹配位宽的空间比较。
    localparam [3:0] C_PORT_MASK = (C_NUM_PORTS == 4) ? 4'b1111 : (C_NUM_PORTS == 2) ? 4'b0011 : 4'b0001; // 显式枚举原生四位形状中的有效端口掩码。
    wire [C_SLOTS-1:0] receive_select, consumer_select, storage_ready, storage_valid; // 常量账户译码与实际 FIFO 状态。
    wire [C_SLOTS*C_SAVED_WIDTH-1:0] stored_heads; // 每账户实际读头的低有效位，不带物理 padding。
    wire [2:0] receive_account; // 仅用于选择存储账户，不用于信用回放。
    wire [C_WORD_WIDTH-1:0] write_word; // 一份包含原始三位元数据的完整 SRAM 写字。
    wire flag_receive, flag_retire, return_ready; // 沿前接收资格、原子退休及队列容量。
    reg [C_SAVED_WIDTH-1:0] selected_head; // 唯一账户掩码与归约或避免串联优先级数据多路器。
    reg [2:0] diagnostic_next; // 固定优先级的本地拒绝原因。
    reg reg_accepted_o; // 独立寄存上一沿实际存储接纳。
    reg [2:0] reg_diagnostic_o; // 独立寄存上一沿输入诊断。
    wire [3:0] initial_valid, initial_pool, normal_valid, normal_pool; // 两个原生注册发布器的独立输出。
    wire [7:0] initial_vc, initial_num, normal_vc, normal_num; // 两类注册输出的元信息。
    wire [C_NUM_PORTS-1:0] return_enable; // 用旧逐端口 done 预约下一正常返回周期。
    integer mux_index; // 静态有界循环选择唯一账户的真实输出字。
    genvar gen_slot; // 常量展开实际存在和零容量账户。
    assign receive_account = i_receive_pool ? 3'd4 : {1'b0, i_receive_vc}; // 池包含所有 VC，但每端口只有一个池账户。
    assign write_word = {{(C_WORD_WIDTH-C_SAVED_WIDTH){1'b0}}, i_receive_pool, i_receive_vc, i_receive_payload}; // 高位 padding 明确清零并完整保存原始元数据。
    assign flag_receive = i_rstn && i_receive_valid && (diagnostic_next == 3'd0); // 无合法空间的原生 beat 被诊断而非额外发出 ready。
    assign o_head_valid = |(consumer_select & storage_valid); // 未启用、零容量或非法账户不会产生有效头。
    assign {o_head_pool, o_head_vc, o_head_payload} = selected_head; // 所有输出来自真实 SRAM 路径保存字。
    assign o_consume_valid = i_rstn && o_head_valid && return_ready; // 元数据无沿前空间时禁止向消费者承诺退休。
    assign flag_retire = o_consume_valid && i_consumer_ready; // 唯一事件同时释放 payload 并保存信用归还记录。
    assign o_receive_accepted = reg_accepted_o; // 仅作为本地诊断观察实际沿事件。
    assign o_diagnostic = reg_diagnostic_o; // 本地错误不直接映射协议 RAS 编码。
    assign return_enable = o_credit_init_done[C_NUM_PORTS-1:0] & {C_NUM_PORTS{i_credit_connected}}; // 旧 done 只影响新注册预约，不丢弃旧信用承诺。
    assign o_credit_valid = initial_valid | normal_valid; // 逐端口互斥注册输出直接合并，不新增或取消采样周期。
    assign o_credit_pool = initial_pool | normal_pool; // 两源无效字段为零，可保持原始 Pool 位。
    assign o_credit_vc = initial_vc | normal_vc; // 池正常返回不会被初始池 VC 零编码覆盖。
    assign o_credit_num = initial_num | normal_num; // 无效源确定为零，互斥源数量编码无冲突。
    always @(*) begin // 本地拒绝优先级不阻止其他账户正常消费和信用推进。
        diagnostic_next = 3'd0; // 无输入或合法交易没有错误。
        if (i_receive_valid) begin // 只解释有效原生 beat 的控制字段。
            if (!C_PORT_MASK[i_receive_port]) diagnostic_next = 3'd1; // 未启用的物理端口不可别名到已启用账户。
            else if (!i_beats_connected || !i_credit_connected) diagnostic_next = 3'd2; // 双向连接及返回连接均需成立。
            else if (!o_credit_init_done[i_receive_port]) diagnostic_next = 3'd3; // 不能借用本沿刚完成的初始化资格。
            else if (!(|(receive_select & storage_ready))) diagnostic_next = 3'd4; // 零容量或沿前满状态不能借同拍消费空间。
        end // 结束有效输入的优先级诊断。
    end // 结束完整赋值的输入诊断组合逻辑。
    always @(*) begin // 本地消费者选择真实 FIFO 读头，不在此进行跨账户调度。
        selected_head = {C_SAVED_WIDTH{1'b0}}; // 无效或未用账户输出确定零字。
        for (mux_index = 32'd0; mux_index < C_SLOTS; mux_index = mux_index+32'd1) begin // 有界静态账户选择不会访问越界存储。
            selected_head = selected_head | (stored_heads[mux_index*C_SAVED_WIDTH +: C_SAVED_WIDTH] & {C_SAVED_WIDTH{consumer_select[mux_index] && storage_valid[mux_index]}}); // 唯一命中账户按位合并，无效头不贡献数据。
        end // 结束全部真实账户的头选择。
    end // 结束消费者头组合多路器。
    always @(posedge i_clk) begin // 单独记录当前采样沿是否实际存储一个输入字。
        if (!i_rstn) reg_accepted_o <= 1'b0; // 同步复位优先取消所有接纳。
        else reg_accepted_o <= flag_receive; // 注册实际受容量约束的输入事件。
    end // 结束接收事件输出寄存器。
    always @(posedge i_clk) begin // 单独记录本沿诊断而不制造协议恢复状态机。
        if (!i_rstn) reg_diagnostic_o <= 3'd0; // 复位期间不保留旧输入错误。
        else reg_diagnostic_o <= diagnostic_next; // 下一合法沿自动清除诊断。
    end // 结束本地诊断输出寄存器。
    generate // 接收存储和初始化容量在 elaboration 使用同一参数。
        if (C_CAPACITIES == {(C_NUM_PORTS*5*C_CREDIT_WIDTH){1'b0}}) begin : gen_no_storage // 全零容量 profile 有意不使用任何输入字数据。
            wire [C_WORD_WIDTH-1:0] unused_receive_word; // 明确标记仅此配置的无存储输入观察边界。
            assign unused_receive_word = write_word; // 不添加虚假负载、隐藏 FIFO 或全局告警豁免。
        end // 结束零存储配置的有意未用数据声明。
        if ((C_PAYLOAD_WIDTH < 1) || ((C_NUM_PORTS != 1) && (C_NUM_PORTS != 2) && (C_NUM_PORTS != 4)) || (C_CREDIT_WIDTH < 3) || (C_CREDIT_WIDTH > 16)) begin : gen_invalid // 拒绝非法接口域而非默默截断。
            upli_receive_channel_parameters_invalid Invalid_Inst (); // 未定义层次确保非法参数编译失败。
        end // 结束接收通道参数保护。
        for (gen_slot = 32'd0; gen_slot < C_SLOTS; gen_slot = gen_slot+32'd1) begin : gen_accounts // 每个 port 的五账户物理独立。
            localparam integer C_PORT_INDEX = gen_slot/5, C_ACCOUNT_INDEX = gen_slot%5; // 完整整数域仅用于常量账户索引计算。
            localparam [1:0] C_PORT = C_PORT_INDEX[1:0]; // 在已校验的端口范围中显式提取双位索引。
            localparam [2:0] C_ACCOUNT = C_ACCOUNT_INDEX[2:0]; // 四 VC 或共享池的静态本地选择编码。
            localparam integer C_DEPTH = {{(32-C_CREDIT_WIDTH){1'b0}}, C_CAPACITIES[gen_slot*C_CREDIT_WIDTH +: C_CREDIT_WIDTH]}; // 显式零扩展避免最高容量位被当成符号。
            assign receive_select[gen_slot] = (i_receive_port == C_PORT) && (receive_account == C_ACCOUNT); // 原生入站只译码一个物理账户。
            assign consumer_select[gen_slot] = (i_consumer_port == C_PORT) && (i_consumer_account == C_ACCOUNT); // 非法本地账户没有命中分支。
            if (C_DEPTH > 0) begin : gen_storage // 零容量账户不得实例化隐藏 SRAM 或缓存信用。
                localparam integer C_COUNT_WIDTH = (C_DEPTH < 2) ? 1 : (C_DEPTH < 4) ? 2 : (C_DEPTH < 8) ? 3 : (C_DEPTH < 16) ? 4 : (C_DEPTH < 32) ? 5 : (C_DEPTH < 64) ? 6 : (C_DEPTH < 128) ? 7 : (C_DEPTH < 256) ? 8 : (C_DEPTH < 512) ? 9 : (C_DEPTH < 1024) ? 10 : (C_DEPTH < 2048) ? 11 : (C_DEPTH < 4096) ? 12 : (C_DEPTH < 8192) ? 13 : (C_DEPTH < 16384) ? 14 : (C_DEPTH < 32768) ? 15 : 16; // 逻辑总量可精确表示完整深度。
                wire [C_COUNT_WIDTH-1:0] count; // 此账户的最小实际占用计数。
                wire [C_WORD_WIDTH-1:0] storage_word; // 真正 SRAM 返回字含确定无效的高位 padding。
                assign o_counts[gen_slot*C_CREDIT_WIDTH +: C_CREDIT_WIDTH] = {{(C_CREDIT_WIDTH-C_COUNT_WIDTH){1'b0}}, count}; // 统一观察位宽只零扩展而不改变资源容量。
                assign stored_heads[gen_slot*C_SAVED_WIDTH +: C_SAVED_WIDTH] = storage_word[C_SAVED_WIDTH-1:0]; // 真实 payload 和元信息完全保留。
                if (C_WORD_WIDTH > C_SAVED_WIDTH) begin : gen_padding // 只在确实存在物理字节填充时声明废弃字段。
                    wire [C_WORD_WIDTH-C_SAVED_WIDTH-1:0] unused_padding; // 物理零填充不属于输出协议，明确标为有意不用。
                    assign unused_padding = storage_word[C_WORD_WIDTH-1:C_SAVED_WIDTH]; // 精确记录丢弃的是 padding 而不是有效数据。
                end // 结束物理字节填充的观察边界。
                upli_receive_storage #( // 原样复用已验证同步 FIFO 与授权外部 SRAM 映射。
                    .C_DEPTH(C_DEPTH), .C_DATA_WIDTH(C_WORD_WIDTH), .C_COUNT_WIDTH(C_COUNT_WIDTH) // 深度与初始信用发布参数严格相同。
                ) Storage_Inst ( // 每账户一个有实际存储后端的 FIFO。
                    .i_clk(i_clk), .i_rstn(i_rstn), // 同一时钟和同步所有权复位。
                    .i_write_valid(i_rstn && i_receive_valid && i_credit_connected && i_beats_connected && o_credit_init_done[C_PORT_INDEX] && receive_select[gen_slot]), .i_write_data(write_word), .o_write_ready(storage_ready[gen_slot]), // 本账户 FIFO 自身沿前 ready 完成容量检查，避免全局容量归约反馈到每个写使能。
                    .i_read_ready(i_rstn && i_consumer_ready && consumer_select[gen_slot] && (o_pending_count[C_PORT_INDEX*C_PENDING_WIDTH +: C_PENDING_WIDTH] < C_RETURN_LIMIT)), .o_read_valid(storage_valid[gen_slot]), .o_read_data(storage_word), .o_count(count) // 直接检查对应端口真实返回空间，FIFO自身有效位完成同一原子退休而无需全局端口多路反馈。
                ); // 结束此账户实际 SRAM FIFO 实例。
            end else begin : gen_empty // 无容量账户完全不分配存储。
                assign storage_ready[gen_slot] = 1'b0; // 不允许输入借用未声明的空间。
                assign storage_valid[gen_slot] = 1'b0; // 不存在可见读头。
                assign stored_heads[gen_slot*C_SAVED_WIDTH +: C_SAVED_WIDTH] = {C_SAVED_WIDTH{1'b0}}; // 无存储账户数据恒零。
                assign o_counts[gen_slot*C_CREDIT_WIDTH +: C_CREDIT_WIDTH] = {C_CREDIT_WIDTH{1'b0}}; // 无占用也不发布任何信用。
            end // 结束有存储与零容量账户分支。
        end // 结束全部独立账户的生成。
    endgenerate // 结束真实容量驱动的接收存储结构。
    upli_credit_initializer #( // 实际容量直接绑定既有逐端口初始发布器。
        .C_NUM_PORTS(C_NUM_PORTS), .C_CREDIT_WIDTH(C_CREDIT_WIDTH), .C_CAPACITIES(C_CAPACITIES) // 无额外 padding 信用或读缓存信用。
    ) Initializer_Inst ( // 初始信用只在返回方向已连接后发布。
        .i_clk(i_clk), .i_rstn(i_rstn), .i_credit_connected(i_credit_connected), // 返回单方向连接即可初始化。
        .o_credit_valid(initial_valid), .o_credit_pool(initial_pool), .o_credit_vc(initial_vc), .o_credit_num(initial_num), .o_credit_init_done(o_credit_init_done) // 最后初始批次后才能进入正常交接。
    ); // 结束真实容量初始信用发布器实例。
    upli_credit_return_queue #( // 正常归还必须保存实际退休字的原始三位元信息。
        .C_NUM_PORTS(C_NUM_PORTS), .C_DEPTH(C_RETURN_DEPTH), .C_COUNT_WIDTH(C_PENDING_WIDTH) // 返回组件自身拒绝不一致的派生宽度。
    ) Return_Inst ( // 本地元数据入队与 payload 释放使用同一事件。
        .i_clk(i_clk), .i_rstn(i_rstn), .i_return_enable(return_enable), // 旧逐端口完成状态预约沿后的新归还。
        .i_retire_valid(flag_retire), .i_retire_port(i_consumer_port), .i_retire_vc(o_head_vc), .i_retire_pool(o_head_pool), .o_retire_ready(return_ready), // 原 VC 和 Pool 均由保存字回放。
        .o_credit_valid(normal_valid), .o_credit_pool(normal_pool), .o_credit_vc(normal_vc), .o_credit_num(normal_num), .o_pending_count(o_pending_count) // 注册正常批次直接参与互斥合并。
    ); // 结束真实退休元数据归还队列实例。
endmodule // 结束 upli_receive_channel 实际存储与信用交接模块。
