/* verilator lint_off DECLFILENAME */ // 同一冻结消息源文件提供配套 encoder 与 decoder design unit
module kdlink_scale_global_commit_encoder ( // 定义 schema-4 全局提交 payload 编码器
    input wire [14:0] source_domain_i, // 接收十五位原事务源域
    input wire [14:0] destination_domain_i, // 接收十五位原事务目的域
    input wire [4:0] source_node_i, // 接收原事务源节点
    input wire [4:0] destination_node_i, // 接收原事务目的节点
    input wire [15:0] topology_epoch_i, // 接收到达使用的十六位拓扑代次
    input wire [63:0] global_transaction_id_i, // 接收六十四位全局事务标识
    input wire [1:0] status_i, // 接收全局提交状态
    output wire [511:0] payload_o // 输出位级冻结的 schema-4 提交 payload
); // 结束 schema-4 提交编码器端口声明
    assign payload_o[121:0] = {status_i, global_transaction_id_i, topology_epoch_i, destination_node_i, source_node_i, destination_domain_i, source_domain_i}; // 拼接全部 schema-4 提交可变字段
    /* verilator coverage_off */ // 排除协议强制恒零保留字段
    assign payload_o[511:122] = 390'd0; // 永久清零 schema-4 提交保留字段
    /* verilator coverage_on */ // 恢复后续可变逻辑覆盖率
endmodule // 结束 kdlink_scale_global_commit_encoder

module kdlink_scale_global_commit_decoder ( // 定义 schema-4 全局提交 payload 解码器
    input wire [511:0] payload_i, // 接收待检查的提交 payload
    output wire [14:0] source_domain_o, // 输出十五位原事务源域
    output wire [14:0] destination_domain_o, // 输出十五位原事务目的域
    output wire [4:0] source_node_o, // 输出原事务源节点
    output wire [4:0] destination_node_o, // 输出原事务目的节点
    output wire [15:0] topology_epoch_o, // 输出十六位拓扑代次
    output wire [63:0] global_transaction_id_o, // 输出六十四位事务标识
    output wire [1:0] status_o, // 输出全局提交状态
    output wire payload_valid_o // 输出保留位和状态合法性
); // 结束 schema-4 提交解码器端口声明
    assign source_domain_o = payload_i[14:0]; // 提取十五位源域
    assign destination_domain_o = payload_i[29:15]; // 提取十五位目的域
    assign source_node_o = payload_i[34:30]; // 提取源节点
    assign destination_node_o = payload_i[39:35]; // 提取目的节点
    assign topology_epoch_o = payload_i[55:40]; // 提取十六位拓扑代次
    assign global_transaction_id_o = payload_i[119:56]; // 提取六十四位事务标识
    assign status_o = payload_i[121:120]; // 提取两位提交状态
    assign payload_valid_o = (status_o != 2'b11) && (payload_i[511:122] == 390'd0); // 拒绝保留状态和任一非零保留位
endmodule // 结束 kdlink_scale_global_commit_decoder
/* verilator lint_on DECLFILENAME */ // 恢复后续 design-unit 文件名检查
