module kdlink_global_commit_codec ( // 定义全局提交确认 payload 编码器
    input wire [7:0] source_domain_i, // 接收原事务源域标识
    input wire [7:0] destination_domain_i, // 接收原事务目的域标识
    input wire [4:0] source_node_i, // 接收原事务源节点标识
    input wire [4:0] destination_node_i, // 接收原事务目的节点标识
    input wire [7:0] topology_epoch_i, // 接收确认所属拓扑代次
    input wire [63:0] global_transaction_id_i, // 接收全局事务标识
    input wire [1:0] status_i, // 接收全局提交状态
    output reg [511:0] payload_o // 输出完整全局提交确认 payload
); // 结束全局提交确认编码器端口声明
    always @(*) begin // 组合形成冻结字段布局并清零保留位
        payload_o = 512'd0; // 默认清零全部 payload 位
        payload_o[7:0] = source_domain_i; // 写入原事务源域
        payload_o[15:8] = destination_domain_i; // 写入原事务目的域
        payload_o[20:16] = source_node_i; // 写入原事务源节点
        payload_o[25:21] = destination_node_i; // 写入原事务目的节点
        payload_o[33:26] = topology_epoch_i; // 写入确认拓扑代次
        payload_o[97:34] = global_transaction_id_i; // 写入全局事务标识
        payload_o[99:98] = status_i; // 写入全局提交状态
    end // 结束全局提交确认 payload 编码
endmodule // 结束 kdlink_global_commit_codec

/* verilator lint_off DECLFILENAME */ // 同一冻结字段源文件同时提供配套 decoder design unit
/* verilator lint_off MULTITOP */ // 独立静态检查本源文件时允许编码器和解码器两个根 design unit
module kdlink_global_commit_decoder ( // 定义全局提交确认 payload 解码器
    input wire [511:0] payload_i, // 接收完整全局提交确认 payload
    output wire [7:0] source_domain_o, // 输出原事务源域标识
    output wire [7:0] destination_domain_o, // 输出原事务目的域标识
    output wire [4:0] source_node_o, // 输出原事务源节点标识
    output wire [4:0] destination_node_o, // 输出原事务目的节点标识
    output wire [7:0] topology_epoch_o, // 输出确认所属拓扑代次
    output wire [63:0] global_transaction_id_o, // 输出全局事务标识
    output wire [1:0] status_o, // 输出全局提交状态
    output wire payload_valid_o // 输出保留位为零的合法性结果
); // 结束全局提交确认解码器端口声明
    assign source_domain_o = payload_i[7:0]; // 解码原事务源域
    assign destination_domain_o = payload_i[15:8]; // 解码原事务目的域
    assign source_node_o = payload_i[20:16]; // 解码原事务源节点
    assign destination_node_o = payload_i[25:21]; // 解码原事务目的节点
    assign topology_epoch_o = payload_i[33:26]; // 解码确认拓扑代次
    assign global_transaction_id_o = payload_i[97:34]; // 解码全局事务标识
    assign status_o = payload_i[99:98]; // 解码全局提交状态
    assign payload_valid_o = (payload_i[511:100] == 412'd0) && (payload_i[99:98] != 2'b11); // 要求全部保留位为零且提交状态编码属于冻结集合
endmodule // 结束 kdlink_global_commit_decoder
/* verilator lint_on DECLFILENAME */ // 恢复后续源文件的 design unit 文件名检查
/* verilator lint_on MULTITOP */ // 恢复后续源文件的多根 design unit 检查
