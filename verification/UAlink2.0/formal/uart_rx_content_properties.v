`timescale 1ps/1ps // 全部实际存储与独立参考在共同沿推进。
module uart_rx_content_properties #(parameter integer C_DEPTH=128, parameter integer C_CONTENT=0, parameter integer C_PROOF_BIT=-1) ( // UART 接收独立状态和可选实际内容检查模块。
    input wire i_clk, // 原生输入保持独立任意。
    input wire i_rstn, // 原生输入保持独立任意。
    input wire i_stream_reset, // 原生输入保持独立任意。
    input wire i_channel4_enabled, // 原生输入保持独立任意。
    input wire i_word_valid, // 原生输入保持独立任意。
    input wire [31:0] i_word, // 原生输入保持独立任意。
    input wire i_fw_ready, // 原生输入保持独立任意。
    output wire [4:0] o_groups, output wire o_violation // 只输出性质分组与总失败信号。
); // 只输出性质分组与总失败信号。
    wire o_fw_valid; // 完整原输出与独立参考一一比较。
    wire expected_fw_valid; // 完整原输出与独立参考一一比较。
    wire [31:0] o_fw_word; // 完整原输出与独立参考一一比较。
    wire [31:0] expected_fw_word; // 完整原输出与独立参考一一比较。
    wire [11:0] o_rx_fill; // 完整原输出与独立参考一一比较。
    wire [11:0] expected_rx_fill; // 完整原输出与独立参考一一比较。
    wire o_initialized; // 完整原输出与独立参考一一比较。
    wire expected_initialized; // 完整原输出与独立参考一一比较。
    wire [11:0] o_rx_counter; // 完整原输出与独立参考一一比较。
    wire [11:0] expected_rx_counter; // 完整原输出与独立参考一一比较。
    wire o_credit_available; // 完整原输出与独立参考一一比较。
    wire expected_credit_available; // 完整原输出与独立参考一一比较。
    wire [5:0] o_remaining; // 完整原输出与独立参考一一比较。
    wire [5:0] expected_remaining; // 完整原输出与独立参考一一比较。
    wire o_dropping; // 完整原输出与独立参考一一比较。
    wire expected_dropping; // 完整原输出与独立参考一一比较。
    wire o_header; // 完整原输出与独立参考一一比较。
    wire expected_header; // 完整原输出与独立参考一一比较。
    wire o_payload_write; // 完整原输出与独立参考一一比较。
    wire expected_payload_write; // 完整原输出与独立参考一一比较。
    wire o_payload_discard; // 完整原输出与独立参考一一比较。
    wire expected_payload_discard; // 完整原输出与独立参考一一比较。
    wire o_done; // 完整原输出与独立参考一一比较。
    wire expected_done; // 完整原输出与独立参考一一比较。
    wire o_credit_valid; // 完整原输出与独立参考一一比较。
    wire expected_credit_valid; // 完整原输出与独立参考一一比较。
    wire [11:0] o_credit_value; // 完整原输出与独立参考一一比较。
    wire [11:0] expected_credit_value; // 完整原输出与独立参考一一比较。
    wire o_reset_request; // 完整原输出与独立参考一一比较。
    wire expected_reset_request; // 完整原输出与独立参考一一比较。
    wire o_request_all; // 完整原输出与独立参考一一比较。
    wire expected_request_all; // 完整原输出与独立参考一一比较。
    wire o_reset_response; // 完整原输出与独立参考一一比较。
    wire expected_reset_response; // 完整原输出与独立参考一一比较。
    wire o_response_all; // 完整原输出与独立参考一一比较。
    wire expected_response_all; // 完整原输出与独立参考一一比较。
    wire [2:0] o_response_status; // 完整原输出与独立参考一一比较。
    wire [2:0] expected_response_status; // 完整原输出与独立参考一一比较。
    wire o_other_valid; // 完整原输出与独立参考一一比较。
    wire expected_other_valid; // 完整原输出与独立参考一一比较。
    wire [31:0] o_other_word; // 完整原输出与独立参考一一比较。
    wire [31:0] expected_other_word; // 完整原输出与独立参考一一比较。
    wire o_error; // 完整原输出与独立参考一一比较。
    wire expected_error; // 完整原输出与独立参考一一比较。
    wire [19:0] actual_state; // 只读观察保持实际寄存器和存储驱动。
    wire [11:0] actual_count, actual_unread, actual_read_addr, actual_write_addr; // 只读观察保持实际寄存器和存储驱动。
    wire actual_pending; // 只读观察保持实际寄存器和存储驱动。
    wire [1:0] actual_cached; // 只读观察保持实际寄存器和存储驱动。
    wire [31:0] actual_head, actual_tail, actual_read_result; // 只读观察保持实际寄存器和存储驱动。
    wire [C_DEPTH*32-1:0] actual_memory; // 只读观察保持实际寄存器和存储驱动。
    wire actual_storage_reset; // 只读观察保持实际寄存器和存储驱动。
    dl_uart_rx_path Rx_Inst ( // 已由脚本展开原参数与实际存储的产品实例。
        .i_clk(i_clk), .i_rstn(i_rstn), .i_stream_reset(i_stream_reset), // 原始数据路径与只读观察连接。
        .i_channel4_enabled(i_channel4_enabled), .i_word_valid(i_word_valid), .i_word(i_word), // 原始数据路径与只读观察连接。
        .i_fw_ready(i_fw_ready), .o_fw_valid(o_fw_valid), .o_fw_word(o_fw_word), // 原始数据路径与只读观察连接。
        .o_rx_fill(o_rx_fill), .o_initialized(o_initialized), .o_rx_counter(o_rx_counter), // 原始数据路径与只读观察连接。
        .o_credit_available(o_credit_available), .o_remaining(o_remaining), .o_dropping(o_dropping), // 原始数据路径与只读观察连接。
        .o_header(o_header), .o_payload_write(o_payload_write), .o_payload_discard(o_payload_discard), // 原始数据路径与只读观察连接。
        .o_done(o_done), .o_credit_valid(o_credit_valid), .o_credit_value(o_credit_value), // 原始数据路径与只读观察连接。
        .o_reset_request(o_reset_request), .o_request_all(o_request_all), .o_reset_response(o_reset_response), // 原始数据路径与只读观察连接。
        .o_response_all(o_response_all), .o_response_status(o_response_status), .o_other_valid(o_other_valid), // 原始数据路径与只读观察连接。
        .o_other_word(o_other_word), .o_error(o_error), .o_formal_state(actual_state), // 原始数据路径与只读观察连接。
        .o_formal_storage_reset(actual_storage_reset), .o_formal_count(actual_count), .o_formal_unread(actual_unread), // 原始数据路径与只读观察连接。
        .o_formal_read_addr(actual_read_addr), .o_formal_write_addr(actual_write_addr), .o_formal_pending(actual_pending), // 原始数据路径与只读观察连接。
        .o_formal_cached(actual_cached), .o_formal_head(actual_head), .o_formal_tail(actual_tail), // 原始数据路径与只读观察连接。
        .o_formal_read_result(actual_read_result), .o_formal_memory(actual_memory) // 原始数据路径与只读观察连接。
    ); // 结束真实产品连接。
    localparam [13:0] LIMIT=C_DEPTH; // 独立长度加已收数量表示及更宽信用占用算术。
    localparam [15:0] INITIAL=C_DEPTH; // 独立长度加已收数量表示及更宽信用占用算术。
    reg [5:0] announced, received; // 独立长度加已收数量表示及更宽信用占用算术。
    reg rejected, initialized; // 独立长度加已收数量表示及更宽信用占用算术。
    reg [15:0] available_credit; // 独立长度加已收数量表示及更宽信用占用算术。
    reg [13:0] queued; // 独立长度加已收数量表示及更宽信用占用算术。
    wire [6:0] unreceived; // 独立长度加已收数量表示及更宽信用占用算术。
    wire running, boundary, body, stream_zero, uart_class, reset_scope; // 独立长度加已收数量表示及更宽信用占用算术。
    wire transport, credit_message, request_message, response_message; // 独立长度加已收数量表示及更宽信用占用算术。
    wire [5:0] announced_now; // 独立长度加已收数量表示及更宽信用占用算术。
    wire [13:0] need; // 独立长度加已收数量表示及更宽信用占用算术。
    wire full, capacity_error, discard_now, consume; // 独立长度加已收数量表示及更宽信用占用算术。
    wire [13:0] cached_wide, prefetched, distance; // 独立长度加已收数量表示及更宽信用占用算术。
    wire bad_reference, bad_storage, bad_content; // 独立长度加已收数量表示及更宽信用占用算术。
    wire [31:0] shadow_head; // 独立长度加已收数量表示及更宽信用占用算术。
    localparam integer C_PROOF_WIDTH=(C_PROOF_BIT<0)?32:1; // 完整内容或指定数据位平面的独立顺序队列宽度。
    localparam [31:0] C_PROOF_MASK=(C_PROOF_BIT<0)?32'hffffffff:(32'd1<<C_PROOF_BIT); // 位平面模式只声称该位固件数据输出性质。
    wire [C_PROOF_WIDTH-1:0] content_word, content_head, content_tail, content_read_result, content_shadow; // 真实数据路径的常量位选择不切断任何驱动。
    wire [C_DEPTH*C_PROOF_WIDTH-1:0] content_memory; // 每一逻辑行的真实存储位仍参加证明。
    localparam [31:0] C_PROOF_ROWS=C_DEPTH; // 明确使用静态无符号完整逻辑行数。
    genvar gen_content_row; // 全部逻辑行逐一观察其实际数据。
    generate // 数据位选择在展开时确定而不是环境假设。
        if (C_PROOF_BIT<0) begin : gen_full_word // 原完整三十二位检查模式。
            assign content_word=i_word[C_PROOF_WIDTH-1:0]; // 原输入完整字作为独立参考来源。
            assign content_head=actual_head[C_PROOF_WIDTH-1:0]; // 真实队首全部数据位。
            assign content_tail=actual_tail[C_PROOF_WIDTH-1:0]; // 真实第二缓存全部数据位。
            assign content_read_result=actual_read_result[C_PROOF_WIDTH-1:0]; // 真实注册 Q 全部数据位。
            assign shadow_head={{(32-C_PROOF_WIDTH){1'b0}},content_shadow}; // 完整参考队首用于全部固件数据比较。
        end else begin : gen_one_plane // 一个声明数据位的任意长执行证明。
            assign content_word=i_word[C_PROOF_BIT]; // 原线上输入的该位与其余头字段仍共享同一任意输入字。
            assign content_head=actual_head[C_PROOF_BIT]; // 观察实际队首寄存器该位。
            assign content_tail=actual_tail[C_PROOF_BIT]; // 观察实际尾缓存寄存器该位。
            assign content_read_result=actual_read_result[C_PROOF_BIT]; // 观察实际 SRAM 注册 Q 该位。
            assign shadow_head={31'd0,content_shadow[0]}<<C_PROOF_BIT; // 只比较被声明的固件输出位而不外推其它位。
        end // 结束完整字与单个位平面观察选择。
        for (gen_content_row=32'd0;gen_content_row<C_PROOF_ROWS;gen_content_row=gen_content_row+32'd1) begin : gen_memory_plane // 所有实际行均被观察而不抽样地址。
            if (C_PROOF_BIT<0) begin : gen_word // 原完整字观察。
                assign content_memory[gen_content_row*C_PROOF_WIDTH +: C_PROOF_WIDTH]=actual_memory[gen_content_row*32 +: 32]; // 原完整实际 SRAM 行。
            end else begin : gen_bit // 常量选择这一实际行的目标位。
                assign content_memory[gen_content_row]=actual_memory[gen_content_row*32+C_PROOF_BIT]; // 其它位由其各自独立归纳证明。
            end // 结束这一实际行数据选择。
        end // 结束全部实际逻辑行观察。
    endgenerate // 结束真实数据位平面观察生成块。
    assign unreceived={1'b0,announced}-{1'b0,received}; // 依据线上规范字段与独立队列容量解释边界和接受事件。
    assign running=i_rstn && !i_stream_reset && initialized; // 依据线上规范字段与独立队列容量解释边界和接受事件。
    assign boundary=i_rstn && i_word_valid && (announced==6'd0); // 依据线上规范字段与独立队列容量解释边界和接受事件。
    assign body=i_rstn && i_word_valid && (announced!=6'd0); // 依据线上规范字段与独立队列容量解释边界和接受事件。
    assign stream_zero=(i_word[11:9]==3'd0); // 依据线上规范字段与独立队列容量解释边界和接受事件。
    assign uart_class=(i_word[5:2]==4'd1); // 依据线上规范字段与独立队列容量解释边界和接受事件。
    assign reset_scope=stream_zero || i_word[12]; // 依据线上规范字段与独立队列容量解释边界和接受事件。
    assign transport=boundary && uart_class && (i_word[8:6]==3'd0); // 依据线上规范字段与独立队列容量解释边界和接受事件。
    assign credit_message=boundary && uart_class && stream_zero && (i_word[8:6]==3'd1); // 依据线上规范字段与独立队列容量解释边界和接受事件。
    assign request_message=boundary && uart_class && reset_scope && (i_word[8:6]==3'd6); // 依据线上规范字段与独立队列容量解释边界和接受事件。
    assign response_message=boundary && uart_class && reset_scope && (i_word[8:6]==3'd7); // 依据线上规范字段与独立队列容量解释边界和接受事件。
    assign announced_now={1'b0,i_word[31:27]}+6'd1; // 依据线上规范字段与独立队列容量解释边界和接受事件。
    assign need=queued+{8'd0,announced_now}; // 依据线上规范字段与独立队列容量解释边界和接受事件。
    assign full=(queued>=LIMIT); // 依据线上规范字段与独立队列容量解释边界和接受事件。
    assign capacity_error=transport && stream_zero && running && i_channel4_enabled && (need>LIMIT); // 依据线上规范字段与独立队列容量解释边界和接受事件。
    assign discard_now=rejected || !running || !i_channel4_enabled; // 依据线上规范字段与独立队列容量解释边界和接受事件。
    assign consume=running && (actual_cached!=2'd0) && i_fw_ready; // 依据线上规范字段与独立队列容量解释边界和接受事件。
    assign expected_fw_valid=running && (actual_cached!=2'd0); // 独立计算fw_valid的完整沿前含义。
    assign expected_fw_word=expected_fw_valid ? ((C_CONTENT!=0) ? shadow_head : actual_head) : 32'd0; // 独立计算fw_word的完整沿前含义。
    assign expected_rx_fill=running ? queued[11:0] : 12'd0; // 独立计算rx_fill的完整沿前含义。
    assign expected_initialized=running; // 独立计算initialized的完整沿前含义。
    assign expected_rx_counter=running ? available_credit[11:0] : 12'd0; // 独立计算rx_counter的完整沿前含义。
    assign expected_credit_available=running && i_channel4_enabled; // 独立计算credit_available的完整沿前含义。
    assign expected_remaining=i_rstn ? unreceived[5:0] : 6'd0; // 独立计算remaining的完整沿前含义。
    assign expected_dropping=i_rstn && (announced!=6'd0) && discard_now; // 独立计算dropping的完整沿前含义。
    assign expected_header=transport; // 独立计算header的完整沿前含义。
    assign expected_payload_write=body && !discard_now && !full; // 独立计算payload_write的完整沿前含义。
    assign expected_payload_discard=body && !expected_payload_write; // 独立计算payload_discard的完整沿前含义。
    assign expected_done=body && (unreceived==7'd1); // 独立计算done的完整沿前含义。
    assign expected_credit_valid=credit_message && running; // 独立计算credit_valid的完整沿前含义。
    assign expected_credit_value=expected_credit_valid ? i_word[31:20] : 12'd0; // 独立计算credit_value的完整沿前含义。
    assign expected_reset_request=request_message; // 独立计算reset_request的完整沿前含义。
    assign expected_request_all=request_message && i_word[12]; // 独立计算request_all的完整沿前含义。
    assign expected_reset_response=response_message; // 独立计算reset_response的完整沿前含义。
    assign expected_response_all=response_message && i_word[12]; // 独立计算response_all的完整沿前含义。
    assign expected_response_status=response_message ? i_word[15:13] : 3'd0; // 独立计算response_status的完整沿前含义。
    assign expected_other_valid=boundary && !(transport || credit_message || request_message || response_message); // 独立计算other_valid的完整沿前含义。
    assign expected_other_word=expected_other_valid ? i_word : 32'd0; // 独立计算other_word的完整沿前含义。
    assign expected_error=capacity_error || (body && !discard_now && full); // 独立计算error的完整沿前含义。
    always @(posedge i_clk) begin // 独立保存原消息长度直到原末字。
        if (!i_rstn) announced<=6'd0; // 独立保存原消息长度直到原末字。
        else if (transport) announced<=announced_now; // 独立保存原消息长度直到原末字。
        else if (expected_done) announced<=6'd0; // 独立保存原消息长度直到原末字。
    end // 独立保存原消息长度直到原末字。
    always @(posedge i_clk) begin // 只统计有效线上 payload 而非递减 DUT 余数。
        if (!i_rstn || transport || expected_done) received<=6'd0; // 只统计有效线上 payload 而非递减 DUT 余数。
        else if (body) received<=received+6'd1; // 只统计有效线上 payload 而非递减 DUT 余数。
    end // 只统计有效线上 payload 而非递减 DUT 余数。
    always @(posedge i_clk) begin // 独立保留消息失效决定跨越空拍和本地复位。
        if (!i_rstn) rejected<=1'b0; // 独立保留消息失效决定跨越空拍和本地复位。
        else if (transport) rejected<=!running || !i_channel4_enabled || !stream_zero || capacity_error; // 独立保留消息失效决定跨越空拍和本地复位。
        else if (expected_done) rejected<=1'b0; // 独立保留消息失效决定跨越空拍和本地复位。
        else if ((announced!=6'd0) && (discard_now || (body && full))) rejected<=1'b1; // 独立保留消息失效决定跨越空拍和本地复位。
    end // 独立保留消息失效决定跨越空拍和本地复位。
    always @(posedge i_clk) begin // 独立初始化资格只在释放沿建立。
        if (!i_rstn || i_stream_reset) initialized<=1'b0; // 独立初始化资格只在释放沿建立。
        else initialized<=1'b1; // 独立初始化资格只在释放沿建立。
    end // 独立初始化资格只在释放沿建立。
    always @(posedge i_clk) begin // 较宽信用参考仅由真正固件消费递增并比较低十二位。
        if (!i_rstn || i_stream_reset) available_credit<=16'd0; // 较宽信用参考仅由真正固件消费递增并比较低十二位。
        else if (!initialized) available_credit<=INITIAL; // 较宽信用参考仅由真正固件消费递增并比较低十二位。
        else if (consume) available_credit<=available_credit+16'd1; // 较宽信用参考仅由真正固件消费递增并比较低十二位。
    end // 较宽信用参考仅由真正固件消费递增并比较低十二位。
    always @(posedge i_clk) begin // 独立占用由原消息准入和实际固件握手维护。
        if (!running) queued<=14'd0; // 独立占用由原消息准入和实际固件握手维护。
        else queued<=queued+{13'd0,expected_payload_write}-{13'd0,consume}; // 独立占用由原消息准入和实际固件握手维护。
    end // 独立占用由原消息准入和实际固件握手维护。
    assign cached_wide={12'd0,actual_cached}; // 全部归纳辅助数量与地址关系也必须被证明而非假设。
    assign prefetched=cached_wide+{13'd0,actual_pending}; // 全部归纳辅助数量与地址关系也必须被证明而非假设。
    assign distance=(actual_write_addr>=actual_read_addr) ? {2'd0,actual_write_addr}-{2'd0,actual_read_addr} : {2'd0,actual_write_addr}+LIMIT-{2'd0,actual_read_addr}; // 全部归纳辅助数量与地址关系也必须被证明而非假设。
    assign bad_reference=(announced>6'd32) || ((announced==6'd0) ? (received!=6'd0) : (received>=announced)) || (queued>LIMIT); // 全部归纳辅助数量与地址关系也必须被证明而非假设。
    assign bad_storage=({2'd0,actual_count}!=queued) || ({2'd0,actual_unread}>LIMIT) || (queued!={2'd0,actual_unread}+prefetched) || (prefetched>14'd2) || ({2'd0,actual_read_addr}>=LIMIT) || ({2'd0,actual_write_addr}>=LIMIT) || (({2'd0,actual_unread}==LIMIT) ? (distance!=14'd0) : (distance!={2'd0,actual_unread})) || (consume && (queued==14'd0)); // 全部归纳辅助数量与地址关系也必须被证明而非假设。
    generate // 内容模式检查实际 SRAM 行和注册 Q 与原输入顺序队列而无数据假设。
        if (C_CONTENT!=0) begin : gen_content // 内容模式检查实际 SRAM 行和注册 Q 与原输入顺序队列而无数据假设。
            uart_rx_word_invariant #(.C_DEPTH(C_DEPTH),.C_WORD_WIDTH(C_PROOF_WIDTH),.C_COUNT_WIDTH(12)) Content_Inst ( // 内容模式检查实际 SRAM 行和注册 Q 与原输入顺序队列而无数据假设。
                .i_clk(i_clk),.i_rstn(running),.i_push(expected_payload_write),.i_pop(consume),.i_word(content_word), // 内容模式检查实际 SRAM 行和注册 Q 与原输入顺序队列而无数据假设。
                .i_count(actual_count),.i_unread(actual_unread),.i_read_addr(actual_read_addr),.i_write_addr(actual_write_addr), // 内容模式检查实际 SRAM 行和注册 Q 与原输入顺序队列而无数据假设。
                .i_pending(actual_pending),.i_cached(actual_cached),.i_head(content_head),.i_tail(content_tail), // 内容模式检查实际 SRAM 行和注册 Q 与原输入顺序队列而无数据假设。
                .i_read_result(content_read_result),.i_memory(content_memory),.o_shadow_head(content_shadow),.o_violation(bad_content) // 内容模式检查实际 SRAM 行和注册 Q 与原输入顺序队列而无数据假设。
            ); // 内容模式检查实际 SRAM 行和注册 Q 与原输入顺序队列而无数据假设。
        end else begin : gen_control // 内容模式检查实际 SRAM 行和注册 Q 与原输入顺序队列而无数据假设。
            assign content_shadow={C_PROOF_WIDTH{1'b0}}; // 内容模式检查实际 SRAM 行和注册 Q 与原输入顺序队列而无数据假设。
            assign bad_content=1'b0; // 内容模式检查实际 SRAM 行和注册 Q 与原输入顺序队列而无数据假设。
        end // 内容模式检查实际 SRAM 行和注册 Q 与原输入顺序队列而无数据假设。
    endgenerate // 结束实际内容性质的条件生成块。
    assign o_groups[0]=(o_fw_valid!=expected_fw_valid) || ((o_fw_word&C_PROOF_MASK)!=(expected_fw_word&C_PROOF_MASK)) || (o_rx_fill!=expected_rx_fill) || (o_initialized!=expected_initialized) || (o_rx_counter!=expected_rx_counter) || (o_credit_available!=expected_credit_available) || (o_remaining!=expected_remaining) || (o_dropping!=expected_dropping) || (o_header!=expected_header) || (o_payload_write!=expected_payload_write) || (o_payload_discard!=expected_payload_discard) || (o_done!=expected_done) || (o_credit_valid!=expected_credit_valid) || (o_credit_value!=expected_credit_value) || (o_reset_request!=expected_reset_request) || (o_request_all!=expected_request_all) || (o_reset_response!=expected_reset_response) || (o_response_all!=expected_response_all) || (o_response_status!=expected_response_status) || (o_other_valid!=expected_other_valid) || (o_other_word!=expected_other_word) || (o_error!=expected_error); // 全部二十二组一百二十四位输出逐项参与。
    assign o_groups[1]=(actual_state[5:0]!=unreceived) || (actual_state[6]!=rejected) || (actual_state[7]!=initialized) || (actual_state[19:8]!=available_credit[11:0]) || (actual_storage_reset!=running); // 实际状态与全部辅助关系构成完整归纳性质模块。
    assign o_groups[2]=bad_reference; // 实际状态与全部辅助关系构成完整归纳性质模块。
    assign o_groups[3]=bad_storage; // 实际状态与全部辅助关系构成完整归纳性质模块。
    assign o_groups[4]=bad_content; // 实际状态与全部辅助关系构成完整归纳性质模块。
    assign o_violation=|o_groups; // 实际状态与全部辅助关系构成完整归纳性质模块。
endmodule // 结束 UART 接收状态与内容性质模块。
