`timescale 1ns/1ps // 定义候选组合packet交叉连接的仿真时间单位。
`default_nettype none // 禁止隐式网络掩盖矩阵方向或端口拼写错误。
module switch_fabric #( // 仅连接已仲裁的本地packet数据，不包含TL协议或仲裁状态。
    parameter integer PORTS = 4, // 同数量输入与输出端口，要求至少一个。
    parameter integer DATA_WIDTH = 544 // 每个源的完整数据字宽，要求至少一位。
) ( // 选择矩阵为egress-major，路由矩阵为source-major。
    input wire i_rstn, // 低电平组合抑制全部输出；本模块没有需要同步复位的状态。
    input wire [PORTS-1:0] i_valid, // 源valid只决定输出valid，不改变已选择气泡的data和ready。
    input wire [PORTS*DATA_WIDTH-1:0] i_data, // 各源数据按source*DATA_WIDTH从低位起排列。
    input wire [PORTS-1:0] i_last, // 已选源的last逐位原样传递，包括源气泡。
    input wire [PORTS*PORTS-1:0] i_route_match, // source*PORTS+egress表示该源匹配该目的。
    input wire [PORTS*PORTS-1:0] i_select, // egress*PORTS+source表示仲裁器选择该源。
    input wire [PORTS-1:0] i_ready, // 每个目的独立提供下游接纳能力。
    output reg [PORTS-1:0] o_ready, // 每个源最多收到一个无冲突匹配目的的ready。
    output reg [PORTS-1:0] o_valid, // 无选择、不匹配或选择冲突的目的保持无效。
    output reg [PORTS*DATA_WIDTH-1:0] o_data, // 合法已选路径传递全部数据位，不由valid清零。
    output reg [PORTS-1:0] o_last, // 合法已选路径保留原last。
    output reg o_error // 任一选择行多hot或同源多出口时诊断，不因源valid为零而隐藏。
); // 结束纯组合候选接口。
    reg [PORTS-1:0] row_seen, column_seen; // 记录每个出口和源是否已经出现一次选择。
    reg [PORTS-1:0] row_conflict, column_conflict; // 保存非法选择所影响的出口和源。
    integer egress, source; // 固定边界循环在综合时展开，不作为运行时仲裁状态。
    always @(*) begin // 每条路径完整赋值，禁止推断锁存器。
        row_seen = {PORTS{1'b0}}; // 重新统计所有选择行。
        column_seen = {PORTS{1'b0}}; // 重新统计所有选择列。
        row_conflict = {PORTS{1'b0}}; // 默认不存在同一出口选择多个源。
        column_conflict = {PORTS{1'b0}}; // 默认不存在同一源被多个出口选择。
        o_ready = {PORTS{1'b0}}; // 默认禁止任何未确认路径接纳。
        o_valid = {PORTS{1'b0}}; // 默认所有目的无有效数据。
        o_data = {(PORTS*DATA_WIDTH){1'b0}}; // 无连接路径确定为零。
        o_last = {PORTS{1'b0}}; // 无连接路径不提供结束标志。
        o_error = 1'b0; // 复位期间连非法选择诊断也保持零。
        for (egress = 0; egress < PORTS; egress = egress + 1) begin // 先按原始矩阵统计冲突，不用route或valid掩盖错误。
            for (source = 0; source < PORTS; source = source + 1) begin // 每个选择位被准确统计一次。
                if (i_select[egress*PORTS+source]) begin // 当前出口显式选择该源。
                    if (row_seen[egress]) row_conflict[egress] = 1'b1; // 该行第二次选择使整个出口失败关闭。
                    if (column_seen[source]) column_conflict[source] = 1'b1; // 该列第二次选择使此源全部选择路径失败关闭。
                    row_seen[egress] = 1'b1; // 保留首次选择以检测后续重复。
                    column_seen[source] = 1'b1; // 后续其他出口仍能发现重复源。
                end // 结束当前选择统计。
            end // 结束当前出口全部选择位扫描。
        end // 结束完整矩阵冲突检测。
        if (i_rstn) begin // 仅正常工作状态允许转发或报告选择错误。
            o_error = (|row_conflict) || (|column_conflict); // 无关合法路径可以继续工作，但错误必须可观察。
            for (egress = 0; egress < PORTS; egress = egress + 1) begin // 为每个无冲突目的建立已选连接。
                for (source = 0; source < PORTS; source = source + 1) begin // 所有源逐一检查对应source-major路由位。
                    if (i_select[egress*PORTS+source] && i_route_match[source*PORTS+egress] && // 选择与路由必须同时匹配。
                        !row_conflict[egress] && !column_conflict[source]) begin // 冲突相关路径不泄漏data、last或ready。
                        o_valid[egress] = i_valid[source]; // 气泡保留连接，仅valid反映实际源有效性。
                        o_data[egress*DATA_WIDTH +: DATA_WIDTH] = i_data[source*DATA_WIDTH +: DATA_WIDTH]; // 整个数据字不截断、不重排。
                        o_last[egress] = i_last[source]; // last不因valid为零而改写。
                        o_ready[source] = i_ready[egress]; // 源气泡期间仍反馈已选目的ready，保持旧top行为。
                    end // 无匹配路径继续使用确定零输出。
                end // 结束全部源路径选择。
            end // 结束全部出口数据连接。
        end // 结束复位组合门控。
    end // 结束无状态交叉连接。
endmodule // 结束候选switch_fabric，本地开发验证后再由主线接入。
`default_nettype wire // 恢复后续编译单元的默认网络规则。
