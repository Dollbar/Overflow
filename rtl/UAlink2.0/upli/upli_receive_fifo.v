// Synchronous receive FIFO controller for a one-cycle registered SDP SRAM.
// 日期 2026-09-08；数据缓存和在途读仍计入原始逻辑容量。
// Both SRAM ports use i_clk; SRAM state need not reset, but may never leak stale data.
// 双端口同域，清除控制有效性后禁止使用复位前的 SRAM 结果。
`timescale 1ps/1ps // 控制器使用 UPLI 统一精度且没有可综合延时。
module upli_receive_fifo #( // 同步复位及双读缓存的 SRAM FIFO 控制器模块。
    parameter integer C_DEPTH = 5, // 逻辑容量范围一至六万五千五百三十五。
    parameter integer C_DATA_WIDTH = 32, // 存储字宽必须为正的八位整数倍。
    parameter integer C_COUNT_WIDTH = (C_DEPTH < 2) ? 1 : (C_DEPTH < 4) ? 2 : (C_DEPTH < 8) ? 3 : (C_DEPTH < 16) ? 4 : (C_DEPTH < 32) ? 5 : (C_DEPTH < 64) ? 6 : (C_DEPTH < 128) ? 7 : (C_DEPTH < 256) ? 8 : (C_DEPTH < 512) ? 9 : (C_DEPTH < 1024) ? 10 : (C_DEPTH < 2048) ? 11 : (C_DEPTH < 4096) ? 12 : (C_DEPTH < 8192) ? 13 : (C_DEPTH < 16384) ? 14 : (C_DEPTH < 32768) ? 15 : 16, // 派生位宽必须能表示零至完整容量。
    parameter integer C_ZERO_INVALID = 1 // 默认屏蔽无效字；内部原始可见模式必须由消费者保留有效性门控。
) ( // 内部 ready/valid 接口不是新增原生 UPLI 字段。
    input wire i_clk, // 全部控制、缓存及 SRAM 端口的共同上升沿时钟。
    input wire i_rstn, // 同步低有效复位，不驱动物理 SRAM 内容复位。
    input wire i_write_valid, // 生产者提供一个完整待写存储字。
    input wire [C_DATA_WIDTH-1:0] i_write_data, // 待写字可包括 payload 和原 VC/Pool。
    output wire o_write_ready, // 沿前总占用小于精确容量才允许写入。
    input wire i_read_ready, // 消费者确认接收当前有效缓存字。
    output wire o_read_valid, // 队首已经从 SRAM 捕获且尚未消费。
    output wire [C_DATA_WIDTH-1:0] o_read_data, // 注册缓存队首，默认在无效周期输出零。
    output wire [C_COUNT_WIDTH-1:0] o_count, // 未读、读在途与缓存的完整逻辑占用。
    output wire o_sram_write_cs, // 仅实际接受写握手时写入后端 SRAM。
    output wire [C_COUNT_WIDTH-1:0] o_sram_write_addr, // 使用计数宽度零扩展的循环写地址。
    output wire [C_DATA_WIDTH-1:0] o_sram_write_data, // 原始完整字送给 SRAM 写数据端。
    output wire o_sram_read_cs, // 已预约缓存容量才发出 SRAM 读请求。
    output wire [C_COUNT_WIDTH-1:0] o_sram_read_addr, // 最旧尚未发出读请求的 SRAM 地址。
    input wire [C_DATA_WIDTH-1:0] i_sram_read_data // 前一采样沿发起的注册 SRAM 读结果。
); // 结束同步 SRAM FIFO 控制器接口。
    localparam integer C_DERIVED_WIDTH = (C_DEPTH < 2) ? 1 : (C_DEPTH < 4) ? 2 : (C_DEPTH < 8) ? 3 : (C_DEPTH < 16) ? 4 : (C_DEPTH < 32) ? 5 : (C_DEPTH < 64) ? 6 : (C_DEPTH < 128) ? 7 : (C_DEPTH < 256) ? 8 : (C_DEPTH < 512) ? 9 : (C_DEPTH < 1024) ? 10 : (C_DEPTH < 2048) ? 11 : (C_DEPTH < 4096) ? 12 : (C_DEPTH < 8192) ? 13 : (C_DEPTH < 16384) ? 14 : (C_DEPTH < 32768) ? 15 : 16; // 验证派生宽度未被不一致覆盖。
    localparam [C_COUNT_WIDTH-1:0] C_CAPACITY = C_DEPTH[C_COUNT_WIDTH-1:0]; // 合法参数范围内完整表示逻辑容量。
    localparam integer C_LAST_VALUE = C_DEPTH-1; // 先计算最后地址再显式限制宽度。
    localparam [C_COUNT_WIDTH-1:0] C_LAST = C_LAST_VALUE[C_COUNT_WIDTH-1:0]; // 循环地址到此处明确回零，支持非二次幂。
    localparam [C_COUNT_WIDTH-1:0] C_ONE = {{(C_COUNT_WIDTH-1){1'b0}}, 1'b1}; // 所有容量和地址增减使用匹配宽度。
    reg [C_COUNT_WIDTH-1:0] cnt_total, cnt_unread; // 总容量占用与尚未发出读请求的 SRAM 字数。
    reg [C_COUNT_WIDTH-1:0] reg_write_addr, reg_read_addr; // 各自独立寄存的写与预取循环地址。
    reg [1:0] cnt_cached; // 两个输出缓存的有效字数，范围零至二。
    reg reg_pending; // 前一沿 SRAM 读的结果必须在本沿进入缓存。
    reg [C_DATA_WIDTH-1:0] reg_head, reg_tail; // 独立保存可消费队首和后一缓存字。
    wire flag_write, flag_consume, flag_issue; // 本沿写入、消费及新读预约事件。
    wire [1:0] survivors, cached_next; // 消费后幸存缓存和接收旧读结果后的缓存数量。
    wire [2:0] reserved; // 三位预约计算避免缓存数量加法回绕。
    assign o_write_ready = i_rstn && (cnt_total < C_CAPACITY); // 不借用同拍消费产生的新空间。
    assign o_read_valid = cnt_cached != 2'd0; // 同步缓存有效性不取决于当前读准备信号。
    assign o_read_data = ((C_ZERO_INVALID==0) || o_read_valid) ? reg_head : {C_DATA_WIDTH{1'b0}}; // 默认屏蔽无效字，内部模式仅提供保留字给资格计算。
    assign o_count = cnt_total; // 对外资源数量始终包含缓存与在途读。
    assign flag_write = o_write_ready && i_write_valid; // 仅真实写握手推进地址和计数。
    assign flag_consume = i_rstn && o_read_valid && i_read_ready; // 复位及空缓存不产生消费。
    assign survivors = cnt_cached - {1'b0, flag_consume}; // 消费存在的队首后剩余零至两个字。
    assign reserved = {1'b0, survivors} + {2'b00, reg_pending}; // 为此前已发出的读结果保留一个位置。
    assign flag_issue = i_rstn && (cnt_unread != {C_COUNT_WIDTH{1'b0}}) && (reserved < 3'd2); // 至少剩余一个已预约安全槽才发新读。
    assign cached_next = survivors + {1'b0, reg_pending}; // 旧读结果本沿完成后才成为可消费数据。
    assign o_sram_write_cs = flag_write; // 后端不会收到未接受的写请求。
    assign o_sram_write_addr = reg_write_addr; // 后端地址与真实写握手同沿采样。
    assign o_sram_write_data = i_write_data; // 不重编码或截断保存的 payload 与元数据。
    assign o_sram_read_cs = flag_issue; // 后端只读取确实已存储的旧数据。
    assign o_sram_read_addr = reg_read_addr; // 不旁路本沿新写入的地址。
    generate // 非法参数必须在 elaboration 失败。
        if ((C_DEPTH < 1) || (C_DEPTH > 65535) || (C_DATA_WIDTH < 8) || ((C_DATA_WIDTH % 8) != 0) || (C_COUNT_WIDTH != C_DERIVED_WIDTH) || ((C_ZERO_INVALID != 0) && (C_ZERO_INVALID != 1))) begin : gen_invalid // 拒绝容量截断、非整字节和错误派生宽度。
            upli_receive_parameters_invalid Invalid_Inst (); // 明确未定义的层次标记使非法配置失败。
        end // 结束参数合法性检查。
    endgenerate // 结束同步 SRAM FIFO 参数结构检查。
    always @(posedge i_clk) begin // 独立保存完整逻辑容量计数。
        if (!i_rstn) cnt_total <= {C_COUNT_WIDTH{1'b0}}; // 同步复位丢弃全部旧逻辑所有权。
        else begin // 写入和消费独立发生且都不能透支容量。
            case ({flag_write, flag_consume}) // 只对不平衡事件增减完整占用。
                2'b10: cnt_total <= cnt_total + C_ONE; // 接收一个新的存储字。
                2'b01: cnt_total <= cnt_total - C_ONE; // 最终消费者释放一个逻辑字。
                default: cnt_total <= cnt_total; // 无事件或同拍读写时总占用不变。
            endcase // 结束完整逻辑占用更新选择。
        end // 结束非复位的总占用更新。
    end // 结束总容量计数寄存器。
    always @(posedge i_clk) begin // 独立保存 SRAM 尚未发出读请求的字数。
        if (!i_rstn) cnt_unread <= {C_COUNT_WIDTH{1'b0}}; // 旧 SRAM 内容仍存在但不再具有有效读取资格。
        else begin // 只对实际写入和实际读请求更新未读所有权。
            case ({flag_write, flag_issue}) // 预取不释放完整逻辑容量，只迁移数据所有权。
                2'b10: cnt_unread <= cnt_unread + C_ONE; // 新写字进入 SRAM 待读集合。
                2'b01: cnt_unread <= cnt_unread - C_ONE; // 一个旧字进入读在途阶段。
                default: cnt_unread <= cnt_unread; // 写与预取平衡时未读数量保持。
            endcase // 结束 SRAM 未读数量更新。
        end // 结束非复位的未读所有权更新。
    end // 结束未读计数寄存器。
    always @(posedge i_clk) begin // 只有真实写握手推进循环写指针。
        if (!i_rstn) reg_write_addr <= {C_COUNT_WIDTH{1'b0}}; // 同步复位回到第零个地址。
        else if (flag_write) begin // 不使用无效生产者输入修改地址。
            if (reg_write_addr == C_LAST) reg_write_addr <= {C_COUNT_WIDTH{1'b0}}; // 非二次幂容量也在准确末地址回零。
            else reg_write_addr <= reg_write_addr + C_ONE; // 其余合法地址前进一个字。
        end // 结束写指针推进分支。
    end // 结束循环写地址寄存器。
    always @(posedge i_clk) begin // 只有已预约的新 SRAM 读推进预取地址。
        if (!i_rstn) reg_read_addr <= {C_COUNT_WIDTH{1'b0}}; // 同步复位取消旧地址读取进度。
        else if (flag_issue) begin // 后端真正接收一个旧字的读请求。
            if (reg_read_addr == C_LAST) reg_read_addr <= {C_COUNT_WIDTH{1'b0}}; // 最后合法地址之后准确回零。
            else reg_read_addr <= reg_read_addr + C_ONE; // 按 FIFO 顺序继续预取。
        end // 结束预取读地址推进分支。
    end // 结束循环读地址寄存器。
    always @(posedge i_clk) begin // 记录后端本沿接收的读请求结果将在下一沿消费。
        if (!i_rstn) reg_pending <= 1'b0; // 复位丢弃外部未复位 SRAM 的旧读输出资格。
        else reg_pending <= flag_issue; // 连续读请求可在相邻沿持续占据流水级。
    end // 结束读在途资格寄存器。
    always @(posedge i_clk) begin // 保存双输出缓存的精确有效字数。
        if (!i_rstn) cnt_cached <= 2'd0; // 同步复位不保留任何可见旧数据。
        else cnt_cached <= cached_next; // 消费旧字并接收此前已预约的读结果。
    end // 结束缓存有效数量寄存器。
    always @(posedge i_clk) begin // 独立更新输出队首 payload 寄存器。
        if (!i_rstn) reg_head <= {C_DATA_WIDTH{1'b0}}; // 复位清除真实输出缓存字。
        else if (flag_consume && (cnt_cached == 2'd2)) reg_head <= reg_tail; // 两字缓存消费后由旧第二项成为队首。
        else if (reg_pending && (survivors == 2'd0)) reg_head <= i_sram_read_data; // 无幸存字时由旧 SRAM 读结果填补队首。
        else if (flag_consume) reg_head <= {C_DATA_WIDTH{1'b0}}; // 最后缓存字被消费且无替补时清零。
    end // 结束输出队首寄存器。
    always @(posedge i_clk) begin // 独立更新输出第二缓存字。
        if (!i_rstn) reg_tail <= {C_DATA_WIDTH{1'b0}}; // 同步复位不保留隐藏缓存旧字。
        else if (reg_pending && (survivors == 2'd1)) reg_tail <= i_sram_read_data; // 存在一个幸存字时新结果追加其后。
        else if (flag_consume && (cnt_cached == 2'd2)) reg_tail <= {C_DATA_WIDTH{1'b0}}; // 旧第二项提升后无新结果就清零。
    end // 结束输出尾项寄存器。
endmodule // 结束 upli_receive_fifo 同步 SRAM 控制器。
