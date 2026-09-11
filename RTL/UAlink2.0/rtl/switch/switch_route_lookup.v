`timescale 1ns/1ps // 定义内部组合目标查表的仿真时间单位。
`default_nettype none // 禁止隐式网络隐藏路由端口连接错误。
module switch_route_lookup #( // 为每个输入计算唯一enabled目标，不解析标准TL字段。
    parameter PORTS = 4 // 配置对称源和目的端口数量，至少为一。
) ( // 开始独立组合查表接口。
    input wire [PORTS-1:0] i_valid, // 仅限定各输入错误标志是否有效。
    input wire [PORTS*10-1:0] i_dst, // 以source*10低位起点传入完整10位目标ID。
    input wire [PORTS*10-1:0] i_route_ids, // 以target*10低位起点传入目的端口ID表。
    input wire [PORTS-1:0] i_port_enable, // 只允许enabled目的参与唯一性判断。
    output reg [PORTS*PORTS-1:0] o_match, // source*PORTS+target对应唯一目标onehot位，不受valid门控。
    output reg [PORTS-1:0] o_error // 有效源无匹配或有重复enabled匹配时置位。
); // 结束内部目标查表接口。
    reg [PORTS-1:0] candidate_matches; // 临时保存一个源的全部enabled匹配位。
    integer source, target; // 使用静态有界循环展开各源和目的比较。
    always @(*) begin // 完整组合译码，不保存路由表副本或时序状态。
        o_match = {(PORTS*PORTS){1'b0}}; // 默认所有源都没有可接收的唯一目的。
        o_error = {PORTS{1'b0}}; // 默认无有效错误请求。
        candidate_matches = {PORTS{1'b0}}; // 为所有组合路径初始化临时匹配向量。
        for (source = 0; source < PORTS; source = source + 1) begin // 分别构造每个源的目标onehot行。
            candidate_matches = {PORTS{1'b0}}; // 重新统计当前源，避免不同源之间混用结果。
            for (target = 0; target < PORTS; target = target + 1) begin // 遍历全部目的，包括同编号self-route。
                if (i_port_enable[target] && i_route_ids[target*10 +: 10] == i_dst[source*10 +: 10]) begin // 完整比较所有10位，disabled重复项不计入。
                    candidate_matches[target] = 1'b1; // 标记当前源能够匹配的一个目的。
                end // 结束当前目的ID比较。
            end // 结束当前源全部目的比较。
            if ((candidate_matches != {PORTS{1'b0}}) && ((candidate_matches & (candidate_matches - 1'b1)) == {PORTS{1'b0}})) begin // 非零且仅一位为一才是唯一可转发目标。
                o_match[source*PORTS +: PORTS] = candidate_matches; // 输出source-major唯一目标，不依赖输入valid。
            end else begin // 无匹配或多个enabled匹配都拒绝整行输出。
                o_error[source] = i_valid[source]; // 只有当前存在有效请求才报告路由错误。
            end // 结束唯一匹配与拒绝分支。
        end // 结束全部源的独立查表。
    end // 结束无锁存的组合目标查询。
endmodule // 结束switch_route_lookup真实内部路由模块。
`default_nettype wire // 恢复后续模块的默认网络规则。
