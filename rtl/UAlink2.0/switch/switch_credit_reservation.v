`timescale 1ns/1ps // 同域本地packet缓冲容量服务，不引入可综合延时。
`default_nettype none // 禁止隐式网络遗漏容量和路由字段。
module switch_credit_reservation #( // 原子packet容量预约模块，各出口独立轮询仲裁。
    parameter integer PORTS = 4, // 此候选支持一、二或四个源与出口。
    parameter integer UNIT_WIDTH = 4, // 容量单位计数位宽支持三至十六位。
    parameter [UNIT_WIDTH-1:0] DEFAULT_CAPACITY = 4, // 默认空出口队列拥有的真实容量。
    parameter [PORTS*UNIT_WIDTH-1:0] CAPACITIES = {PORTS{DEFAULT_CAPACITY}} // 低位为出口零容量，零表示该资源不可预约。
) ( // 本地请求和真实队列释放的独立事件接口。
    input wire i_clk, // 所有状态共用上升沿时钟域。
    input wire i_rstn, // 同步低有效复位，须与对应queue所有权同时取消。
    input wire [PORTS-1:0] i_request_valid, // 各入口提出一个完整packet预约。
    input wire [PORTS*PORTS-1:0] i_route_match, // source-major唯一目标矩阵，非法多匹配拒绝。
    input wire [PORTS*UNIT_WIDTH-1:0] i_request_units, // 每入口整个packet所需真实存储单位，不能截成首拍。
    input wire [PORTS-1:0] i_admit_ready, // 各出口实际描述符接纳资格，与容量比较共同准入。
    input wire [PORTS-1:0] i_release_valid, // 各出口真实退休释放的有效事件。
    input wire [PORTS*UNIT_WIDTH-1:0] i_release_units, // 本次释放之前已预约的单位数。
    output wire [PORTS-1:0] o_request_ready, // 本沿真实接纳该入口packet预约，不是先行提议。
    output wire [PORTS*PORTS-1:0] o_grant, // egress-major实际grant矩阵，每出口至多一个源。
    output wire [PORTS*UNIT_WIDTH-1:0] o_grant_units, // 每出口本沿实际预约的完整单位数。
    output wire [PORTS-1:0] o_release_accepted, // 实际接纳合法释放，非法事件不改变本出口。
    output wire [PORTS*UNIT_WIDTH-1:0] o_available, // 沿前注册可用容量，复位沿后等于配置容量。
    output wire [PORTS*UNIT_WIDTH-1:0] o_reserved, // 已预约未释放总量，不表示数据已经写入。
    output wire [PORTS-1:0] o_request_error, // 有效候选路由或单位永久非法；资源不足不报错。
    output wire [PORTS-1:0] o_release_error, // 释放零或多于沿前reserved的单位时诊断。
    output wire o_error // 组合错误归约，不宣称RAS恢复状态机。
); // 结束完整容量服务接口。
    localparam integer INDEX_WIDTH = (PORTS <= 2) ? 1 : 2; // 至少一位，覆盖所有已授权配置。
    localparam [31:0] C_PORTS = PORTS; // 显式无符号常量循环界限，供生成与静态门禁共同识别。
    genvar gs, ge; // 静态展开入口检查与出口状态。
    assign o_error = (|o_request_error) || (|o_release_error); // 独立诊断集合不隐去非法事件。
    generate // 按配置建立唯一容量所有者，不重复实例协议信用银行。
        if (((PORTS != 1) && (PORTS != 2) && (PORTS != 4)) || (UNIT_WIDTH < 3) || (UNIT_WIDTH > 16)) begin : gen_invalid // 非法规模不能静默截断。
            switch_credit_reservation_parameters_invalid Invalid_Inst (); // 有意未定义层次使静态展开失败。
        end // 结束非法参数保护。
        for (gs = 0; gs < C_PORTS; gs = gs + 1) begin : gen_sources // 每入口只允许命中一个出口。
            wire [PORTS-1:0] route_row, too_large, grant_column; // 原始路由行、容量错误和对应出口grant列。
            assign route_row = i_route_match[gs*PORTS +: PORTS]; // 读取source-major矩阵的一行。
            for (ge = 0; ge < C_PORTS; ge = ge + 1) begin : gen_target_checks // 常量比较目标的真实总容量。
                assign too_large[ge] = route_row[ge] && (i_request_units[gs*UNIT_WIDTH +: UNIT_WIDTH] > CAPACITIES[ge*UNIT_WIDTH +: UNIT_WIDTH]); // 大于总容量是非法请求而非暂时不足。
                assign grant_column[ge] = o_grant[ge*PORTS+gs]; // 只归约实际已经准入的事件。
            end // 结束各出口常量资格检查。
            assign o_request_error[gs] = i_rstn && i_request_valid[gs] && ((route_row == {PORTS{1'b0}}) || ((route_row & (route_row-{{(PORTS-1){1'b0}},1'b1})) != {PORTS{1'b0}}) || (i_request_units[gs*UNIT_WIDTH +: UNIT_WIDTH] == {UNIT_WIDTH{1'b0}}) || (|too_large)); // 空路由、多路由、零单位或永久超容量均拒绝。
            assign o_request_ready[gs] = |grant_column; // 唯一合法路由保证同源不会被多出口接纳。
        end // 结束入口检查。
        for (ge = 0; ge < C_PORTS; ge = ge + 1) begin : gen_egresses // 各出口容量和公平性状态独立。
            localparam [UNIT_WIDTH-1:0] C_CAPACITY = CAPACITIES[ge*UNIT_WIDTH +: UNIT_WIDTH]; // 当前出口静态容量。
            localparam integer C_LAST_VALUE = PORTS-1; // 先在整数域保存真实末源索引。
            localparam [INDEX_WIDTH-1:0] C_LAST = C_LAST_VALUE[INDEX_WIDTH-1:0]; // 轮询显式末源索引。
            reg [UNIT_WIDTH-1:0] reg_available; // 沿前尚未预约的真实容量。
            reg [INDEX_WIDTH-1:0] reg_next; // 下一次仲裁从该源开始。
            wire [UNIT_WIDTH-1:0] released, used; // 当前释放单位与此前已占有单位。
            wire [PORTS-1:0] eligible; // 所有当前可由沿前容量满足的入口。
            reg [PORTS-1:0] selected; // 从轮询次序选择唯一合法源。
            reg [UNIT_WIDTH-1:0] selected_units; // 被选packet完整单位。
            reg [INDEX_WIDTH-1:0] selected_index; // 实际胜者用于推进下一轮。
            reg found; // 完整默认赋值的组合优先选择标志。
            wire accepted; // 实际出口接纳与资源资格共同完成。
            integer scan, index; // 小规模常量有界组合轮询索引。
            assign released = i_release_units[ge*UNIT_WIDTH +: UNIT_WIDTH]; // 不解释无效释放的任意元信息。
            assign used = C_CAPACITY - reg_available; // 正常不变量确保此前占用无下溢。
            assign o_available[ge*UNIT_WIDTH +: UNIT_WIDTH] = reg_available; // 公开注册容量供集成和独立观察。
            assign o_reserved[ge*UNIT_WIDTH +: UNIT_WIDTH] = used; // 已预约总量以唯一状态推导。
            assign o_release_error[ge] = i_rstn && i_release_valid[ge] && ((released == {UNIT_WIDTH{1'b0}}) || (released > used)); // 不允许释放本沿尚未完成的新预约。
            assign o_release_accepted[ge] = i_rstn && i_release_valid[ge] && !o_release_error[ge]; // 同一错误出口不部分更新。
            for (gs = 0; gs < C_PORTS; gs = gs + 1) begin : gen_eligible // 每源独立比较沿前容量。
                assign eligible[gs] = i_request_valid[gs] && i_route_match[gs*PORTS+ge] && !o_request_error[gs] && (i_request_units[gs*UNIT_WIDTH +: UNIT_WIDTH] <= reg_available); // 同沿释放没有资格旁路。
            end // 结束入口资格展开。
            always @(*) begin // 组合按轮询顺序选择，背压时不承诺owner。
                selected = {PORTS{1'b0}}; // 没有合格候选时grant确定为零。
                selected_units = {UNIT_WIDTH{1'b0}}; // 无选择时不预约任何单位。
                selected_index = {INDEX_WIDTH{1'b0}}; // 无选择索引不用于更新状态。
                found = 1'b0; // 初始尚无胜者。
                index = 0; // 组合整数变量完整默认赋值。
                for (scan = 0; scan < C_PORTS; scan = scan + 1) begin // 最多检查全部已配置源一次。
                    index = {{(32-INDEX_WIDTH){1'b0}},reg_next} + scan; // 显式扩展无符号轮询起点。
                    if (index >= PORTS) index = index-PORTS; // 最多跨越一次端口边界。
                    if (!found && eligible[index]) begin // 第一个符合资格的源获得本次选择。
                        selected[index] = 1'b1; // onehot选择不能重叠。
                        selected_units = i_request_units[index*UNIT_WIDTH +: UNIT_WIDTH]; // 保存完整所需单位。
                        selected_index = index[INDEX_WIDTH-1:0]; // 已证明处于真实源范围。
                        found = 1'b1; // 后续源本次不再覆盖胜者。
                    end // 结束首个合格源选择。
                end // 结束组合轮询。
            end // 结束完整默认值的仲裁组合逻辑。
            assign accepted = i_rstn && i_admit_ready[ge] && !o_release_error[ge] && found; // 非法释放只封锁对应出口，不影响其他出口。
            assign o_grant[ge*PORTS +: PORTS] = selected & {PORTS{accepted}}; // 仅实际容量转移才公开grant。
            assign o_grant_units[ge*UNIT_WIDTH +: UNIT_WIDTH] = selected_units & {UNIT_WIDTH{accepted}}; // 实际占用全部packet单位。
            always @(posedge i_clk) begin // 唯一容量寄存器处理同沿收放净值。
                if (!i_rstn) reg_available <= C_CAPACITY; // 与真实empty queue同时复位拥有全部本地容量。
                else if (!o_release_error[ge]) reg_available <= reg_available + (o_release_accepted[ge] ? released : {UNIT_WIDTH{1'b0}}) - (accepted ? selected_units : {UNIT_WIDTH{1'b0}}); // 先验资格保证净结果在零到容量之间。
            end // 结束原子容量更新。
            always @(posedge i_clk) begin // 轮询状态只根据真实grant前进。
                if (!i_rstn) reg_next <= {INDEX_WIDTH{1'b0}}; // 新epoch从source零开始。
                else if (accepted) begin // 不因idle、背压或被拒绝候选前进。
                    if (selected_index == C_LAST) reg_next <= {INDEX_WIDTH{1'b0}}; // 末源之后回到零。
                    else reg_next <= selected_index + {{(INDEX_WIDTH-1){1'b0}},1'b1}; // 下次从胜者下一源开始。
                end // 结束真实grant后的公平性推进。
            end // 结束轮询寄存器。
        end // 结束全部独立出口。
    endgenerate // 结束参数化容量与仲裁结构。
endmodule // 结束本地packet容量预约服务模块。
`default_nettype wire // 恢复后续独立源编译规则。
