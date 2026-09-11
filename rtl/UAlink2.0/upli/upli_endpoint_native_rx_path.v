`timescale 1ns/1ps // 接收保护与既有存储共用同步时钟。
`default_nettype none // 禁止通道接线遗漏形成隐式网络。
module upli_endpoint_native_rx_path #( // 模块将四通道保护存储连接到请求描述符及原始响应头。
parameter integer C_NUM_PORTS=1, // 直接传递既有接收层参数，不创建额外信用。
parameter integer C_CREDIT_WIDTH=4, // 直接传递既有接收层参数，不创建额外信用。
parameter [C_CREDIT_WIDTH-1:0] C_DEFAULT_CAPACITY=4, // 直接传递既有接收层参数，不创建额外信用。
parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_REQ_CAPACITIES={C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}, // 四通道独立容量覆盖各端口五个实际账户。
parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_DATA_CAPACITIES={C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}, // 四通道独立容量覆盖各端口五个实际账户。
parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_RD_CAPACITIES={C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}, // 四通道独立容量覆盖各端口五个实际账户。
parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_WR_CAPACITIES={C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}, // 四通道独立容量覆盖各端口五个实际账户。
parameter integer C_RETURN_DEPTH=4, // 直接传递既有接收层参数，不创建额外信用。
parameter integer C_PENDING_WIDTH=(C_RETURN_DEPTH<=1)?1:(C_RETURN_DEPTH<=3)?2:(C_RETURN_DEPTH<=7)?3:(C_RETURN_DEPTH<=15)?4:5, // 直接传递既有接收层参数，不创建额外信用。
parameter integer C_ORDER_COUNT_WIDTH=C_CREDIT_WIDTH+3 // 直接传递既有接收层参数，不创建额外信用。
)( // 原生入口没有ready，可信head采用本地消费握手。
 input wire  i_clk, // 四通道存储与桥共享同一采样时钟。
 input wire  i_rstn, // 共同同步低有效复位取消整个传输epoch。
 input wire  i_originator_credit_connected, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 input wire  i_originator_beats_connected, // 直接复用外部角色连接资格，不建立第二套状态。
 input wire  i_completer_credit_connected, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 input wire  i_completer_beats_connected, // 直接复用外部角色连接资格，不建立第二套状态。
 input wire  i_originator_drop, // 外部角色所有者禁止响应业务，不改变可信旧信用。
 input wire  i_completer_drop, // 外部角色Drop同时取消本地未提交请求holding。
 input wire  i_auth_enabled, // 仅保护profile资格，不代表认证验证功能。
 input wire [1:0] i_select_port, // 单holding空闲时选择最早请求所在端口。
 input wire  i_req_valid, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire [1:0] i_req_port, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire [1:0] i_req_vc, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire  i_req_pool, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire [183:0] i_req_payload, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire [12:0] i_req_parity, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 output wire [1:0] o_req_consumer_port, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire  o_req_head_taken, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire [183:0] o_req_head_payload, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire [12:0] o_req_head_parity, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire [1:0] o_req_head_vc, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire  o_req_head_pool, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire [2:0] o_req_head_account, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire  o_req_head_valid, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire  o_req_consume_valid, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire [3:0] o_req_credit_valid, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire [3:0] o_req_credit_pool, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire [7:0] o_req_credit_vc, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire [7:0] o_req_credit_num, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire [3:0] o_req_credit_init_done, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire  o_req_credit_valid_parity, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire  o_req_credit_parity, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 input wire  i_data_valid, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire [1:0] i_data_port, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire [1:0] i_data_vc, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire  i_data_pool, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire [579:0] i_data_payload, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire [12:0] i_data_parity, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 output wire [1:0] o_data_consumer_port, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire  o_data_head_taken, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire [579:0] o_data_head_payload, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire [12:0] o_data_head_parity, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire [1:0] o_data_head_vc, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire  o_data_head_pool, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire [2:0] o_data_head_account, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire  o_data_head_valid, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire  o_data_consume_valid, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire [3:0] o_data_credit_valid, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire [3:0] o_data_credit_pool, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire [7:0] o_data_credit_vc, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire [7:0] o_data_credit_num, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire [3:0] o_data_credit_init_done, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire  o_data_credit_valid_parity, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire  o_data_credit_parity, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 input wire  i_rd_valid, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire [1:0] i_rd_port, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire [1:0] i_rd_vc, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire  i_rd_pool, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire [618:0] i_rd_payload, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire [12:0] i_rd_parity, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire [1:0] i_rd_consumer_port, // 可信有序存储头观察；消费资格与真实退休保持一致。
 input wire  i_rd_consumer_ready, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire [618:0] o_rd_head_payload, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire [12:0] o_rd_head_parity, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire [1:0] o_rd_head_vc, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire  o_rd_head_pool, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire [2:0] o_rd_head_account, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire  o_rd_head_valid, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire  o_rd_consume_valid, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire [3:0] o_rd_credit_valid, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire [3:0] o_rd_credit_pool, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire [7:0] o_rd_credit_vc, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire [7:0] o_rd_credit_num, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire [3:0] o_rd_credit_init_done, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire  o_rd_credit_valid_parity, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire  o_rd_credit_parity, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 input wire  i_wr_valid, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire [1:0] i_wr_port, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire [1:0] i_wr_vc, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire  i_wr_pool, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire [100:0] i_wr_payload, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire [12:0] i_wr_parity, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire [1:0] i_wr_consumer_port, // 可信有序存储头观察；消费资格与真实退休保持一致。
 input wire  i_wr_consumer_ready, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire [100:0] o_wr_head_payload, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire [12:0] o_wr_head_parity, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire [1:0] o_wr_head_vc, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire  o_wr_head_pool, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire [2:0] o_wr_head_account, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire  o_wr_head_valid, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire  o_wr_consume_valid, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire [3:0] o_wr_credit_valid, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire [3:0] o_wr_credit_pool, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire [7:0] o_wr_credit_vc, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire [7:0] o_wr_credit_num, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire [3:0] o_wr_credit_init_done, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire  o_wr_credit_valid_parity, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire  o_wr_credit_parity, // 保留所属通道实际信用字段及其完整保护，不增加返回周期。
 output wire [3:0] o_receive_accepted, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 output wire [51:0] o_ingress_errors, // 原始诊断完整导出，交由外部角色恢复所有者处理。
 output wire [51:0] o_head_errors, // 可信有序存储头观察；消费资格与真实退休保持一致。
 output wire [3:0] o_control_error, // 原始诊断完整导出，交由外部角色恢复所有者处理。
 output wire [3:0] o_data_error, // 原始诊断完整导出，交由外部角色恢复所有者处理。
 output wire [3:0] o_auth_error, // 原始诊断完整导出，交由外部角色恢复所有者处理。
 output wire [3:0] o_auth_profile_error, // 原始诊断完整导出，交由外部角色恢复所有者处理。
 output wire [3:0] o_metadata_error, // 原始诊断完整导出，交由外部角色恢复所有者处理。
 output wire [3:0] o_fault_stop_request, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 output wire [11:0] o_storage_diagnostic, // 原始诊断完整导出，交由外部角色恢复所有者处理。
 output wire [4*C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_counts, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 output wire [16*C_PENDING_WIDTH-1:0] o_pending_count, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 output wire [4*C_NUM_PORTS*C_ORDER_COUNT_WIDTH-1:0] o_order_counts, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 output wire [4*C_NUM_PORTS-1:0] o_order_error, // 原始诊断完整导出，交由外部角色恢复所有者处理。
 output wire [4*C_NUM_PORTS-1:0] o_order_error_sticky, // 原始诊断完整导出，交由外部角色恢复所有者处理。
 output wire [3:0] o_tdm_error, // 原始诊断完整导出，交由外部角色恢复所有者处理。
 output wire [3:0] o_tdm_error_sticky, // 原始诊断完整导出，交由外部角色恢复所有者处理。
 output wire [2:0] o_tdm_phase_known, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 output wire [5:0] o_tdm_expected_port, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 input wire  i_request_ready, // 下游取得完整描述符所有权，不产生额外信用返还。
 output wire  o_request_valid, // 单holding中保存的完整请求及逐拍数据上下文。
 output wire [1:0] o_request_port, // 单holding中保存的完整请求及逐拍数据上下文。
 output wire [1:0] o_request_vc, // 单holding中保存的完整请求及逐拍数据上下文。
 output wire  o_request_pool, // 单holding中保存的完整请求及逐拍数据上下文。
 output wire [183:0] o_request_payload, // 单holding中保存的完整请求及逐拍数据上下文。
 output wire [2047:0] o_request_data, // 单holding中保存的完整请求及逐拍数据上下文。
 output wire [255:0] o_request_be, // 单holding中保存的完整请求及逐拍数据上下文。
 output wire [3:0] o_request_poison, // 单holding中保存的完整请求及逐拍数据上下文。
 output wire [3:0] o_request_data_pools, // 单holding中保存的完整请求及逐拍数据上下文。
 output wire  o_bridge_busy, // 完整传递已冻结字段或实际状态，不改变底层所有权。
 output wire  o_bridge_error // 原始诊断完整导出，交由外部角色恢复所有者处理。
); // 结束完整原生接收总装接口。
wire bridge_rstn; // Drop只取消请求holding，四通道信用存储仍运行。
assign bridge_rstn=i_rstn && !i_completer_drop; // 共同reset或角色Drop同步撤销未提交事务。
wire req_ready,data_ready; // 同一ready用于桥复制和底层真实退休。
upli_native_rx_channel #(.CHANNEL_KIND(0),.C_PAYLOAD_WIDTH(184),.C_NUM_PORTS(C_NUM_PORTS), // req独立保护封套和实际SRAM存储。
 .C_CREDIT_WIDTH(C_CREDIT_WIDTH),.C_DEFAULT_CAPACITY(C_DEFAULT_CAPACITY),.C_CAPACITIES(C_REQ_CAPACITIES), // 原账户容量原样下传。
 .C_RETURN_DEPTH(C_RETURN_DEPTH),.C_PENDING_WIDTH(C_PENDING_WIDTH),.C_ORDER_COUNT_WIDTH(C_ORDER_COUNT_WIDTH)) u_req( // 复用唯一信用和顺序journal所有者。
 .i_clk(i_clk), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_rstn(i_rstn), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_credit_connected(i_completer_credit_connected), // 实际原账户返回与保护字段保持同周期。
 .i_beats_connected(i_completer_beats_connected), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_drop(i_completer_drop), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_auth_enabled(i_auth_enabled), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_valid(i_req_valid), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_port(i_req_port), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_vc(i_req_vc), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_pool(i_req_pool), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_payload(i_req_payload), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_received_parity(i_req_parity), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_consumer_port(o_req_consumer_port), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_consumer_ready(req_ready), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_payload(o_req_head_payload), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_parity(o_req_head_parity), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_vc(o_req_head_vc), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_pool(o_req_head_pool), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_account(o_req_head_account), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_valid(o_req_head_valid), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_consume_valid(o_req_consume_valid), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_credit_valid(o_req_credit_valid), // 实际原账户返回与保护字段保持同周期。
 .o_credit_pool(o_req_credit_pool), // 实际原账户返回与保护字段保持同周期。
 .o_credit_vc(o_req_credit_vc), // 实际原账户返回与保护字段保持同周期。
 .o_credit_num(o_req_credit_num), // 实际原账户返回与保护字段保持同周期。
 .o_credit_init_done(o_req_credit_init_done), // 实际原账户返回与保护字段保持同周期。
 .o_credit_valid_parity(o_req_credit_valid_parity), // 实际原账户返回与保护字段保持同周期。
 .o_credit_parity(o_req_credit_parity), // 实际原账户返回与保护字段保持同周期。
 .o_receive_accepted(o_receive_accepted[0]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_ingress_errors(o_ingress_errors[0*(13) +: 13]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_errors(o_head_errors[0*(13) +: 13]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_control_error(o_control_error[0]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_data_error(o_data_error[0]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_auth_error(o_auth_error[0]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_auth_profile_error(o_auth_profile_error[0]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_metadata_error(o_metadata_error[0]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_fault_stop_request(o_fault_stop_request[0]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_storage_diagnostic(o_storage_diagnostic[0*(3) +: 3]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_counts(o_counts[0*(C_NUM_PORTS*5*C_CREDIT_WIDTH) +: C_NUM_PORTS*5*C_CREDIT_WIDTH]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_pending_count(o_pending_count[0*(4*C_PENDING_WIDTH) +: 4*C_PENDING_WIDTH]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_order_counts(o_order_counts[0*(C_NUM_PORTS*C_ORDER_COUNT_WIDTH) +: C_NUM_PORTS*C_ORDER_COUNT_WIDTH]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_order_error(o_order_error[0*(C_NUM_PORTS) +: C_NUM_PORTS]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_order_error_sticky(o_order_error_sticky[0*(C_NUM_PORTS) +: C_NUM_PORTS]) // 完整连接该通道的冻结输入、可信头和诊断。
); // 结束req实际接收实例。
upli_native_rx_channel #(.CHANNEL_KIND(3),.C_PAYLOAD_WIDTH(580),.C_NUM_PORTS(C_NUM_PORTS), // data独立保护封套和实际SRAM存储。
 .C_CREDIT_WIDTH(C_CREDIT_WIDTH),.C_DEFAULT_CAPACITY(C_DEFAULT_CAPACITY),.C_CAPACITIES(C_DATA_CAPACITIES), // 原账户容量原样下传。
 .C_RETURN_DEPTH(C_RETURN_DEPTH),.C_PENDING_WIDTH(C_PENDING_WIDTH),.C_ORDER_COUNT_WIDTH(C_ORDER_COUNT_WIDTH)) u_data( // 复用唯一信用和顺序journal所有者。
 .i_clk(i_clk), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_rstn(i_rstn), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_credit_connected(i_completer_credit_connected), // 实际原账户返回与保护字段保持同周期。
 .i_beats_connected(i_completer_beats_connected), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_drop(i_completer_drop), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_auth_enabled(i_auth_enabled), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_valid(i_data_valid), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_port(i_data_port), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_vc(i_data_vc), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_pool(i_data_pool), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_payload(i_data_payload), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_received_parity(i_data_parity), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_consumer_port(o_data_consumer_port), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_consumer_ready(data_ready), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_payload(o_data_head_payload), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_parity(o_data_head_parity), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_vc(o_data_head_vc), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_pool(o_data_head_pool), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_account(o_data_head_account), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_valid(o_data_head_valid), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_consume_valid(o_data_consume_valid), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_credit_valid(o_data_credit_valid), // 实际原账户返回与保护字段保持同周期。
 .o_credit_pool(o_data_credit_pool), // 实际原账户返回与保护字段保持同周期。
 .o_credit_vc(o_data_credit_vc), // 实际原账户返回与保护字段保持同周期。
 .o_credit_num(o_data_credit_num), // 实际原账户返回与保护字段保持同周期。
 .o_credit_init_done(o_data_credit_init_done), // 实际原账户返回与保护字段保持同周期。
 .o_credit_valid_parity(o_data_credit_valid_parity), // 实际原账户返回与保护字段保持同周期。
 .o_credit_parity(o_data_credit_parity), // 实际原账户返回与保护字段保持同周期。
 .o_receive_accepted(o_receive_accepted[1]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_ingress_errors(o_ingress_errors[1*(13) +: 13]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_errors(o_head_errors[1*(13) +: 13]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_control_error(o_control_error[1]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_data_error(o_data_error[1]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_auth_error(o_auth_error[1]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_auth_profile_error(o_auth_profile_error[1]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_metadata_error(o_metadata_error[1]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_fault_stop_request(o_fault_stop_request[1]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_storage_diagnostic(o_storage_diagnostic[1*(3) +: 3]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_counts(o_counts[1*(C_NUM_PORTS*5*C_CREDIT_WIDTH) +: C_NUM_PORTS*5*C_CREDIT_WIDTH]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_pending_count(o_pending_count[1*(4*C_PENDING_WIDTH) +: 4*C_PENDING_WIDTH]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_order_counts(o_order_counts[1*(C_NUM_PORTS*C_ORDER_COUNT_WIDTH) +: C_NUM_PORTS*C_ORDER_COUNT_WIDTH]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_order_error(o_order_error[1*(C_NUM_PORTS) +: C_NUM_PORTS]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_order_error_sticky(o_order_error_sticky[1*(C_NUM_PORTS) +: C_NUM_PORTS]) // 完整连接该通道的冻结输入、可信头和诊断。
); // 结束data实际接收实例。
upli_native_rx_channel #(.CHANNEL_KIND(1),.C_PAYLOAD_WIDTH(619),.C_NUM_PORTS(C_NUM_PORTS), // rd独立保护封套和实际SRAM存储。
 .C_CREDIT_WIDTH(C_CREDIT_WIDTH),.C_DEFAULT_CAPACITY(C_DEFAULT_CAPACITY),.C_CAPACITIES(C_RD_CAPACITIES), // 原账户容量原样下传。
 .C_RETURN_DEPTH(C_RETURN_DEPTH),.C_PENDING_WIDTH(C_PENDING_WIDTH),.C_ORDER_COUNT_WIDTH(C_ORDER_COUNT_WIDTH)) u_rd( // 复用唯一信用和顺序journal所有者。
 .i_clk(i_clk), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_rstn(i_rstn), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_credit_connected(i_originator_credit_connected), // 实际原账户返回与保护字段保持同周期。
 .i_beats_connected(i_originator_beats_connected), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_drop(i_originator_drop), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_auth_enabled(i_auth_enabled), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_valid(i_rd_valid), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_port(i_rd_port), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_vc(i_rd_vc), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_pool(i_rd_pool), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_payload(i_rd_payload), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_received_parity(i_rd_parity), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_consumer_port(i_rd_consumer_port), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_consumer_ready(i_rd_consumer_ready), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_payload(o_rd_head_payload), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_parity(o_rd_head_parity), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_vc(o_rd_head_vc), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_pool(o_rd_head_pool), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_account(o_rd_head_account), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_valid(o_rd_head_valid), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_consume_valid(o_rd_consume_valid), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_credit_valid(o_rd_credit_valid), // 实际原账户返回与保护字段保持同周期。
 .o_credit_pool(o_rd_credit_pool), // 实际原账户返回与保护字段保持同周期。
 .o_credit_vc(o_rd_credit_vc), // 实际原账户返回与保护字段保持同周期。
 .o_credit_num(o_rd_credit_num), // 实际原账户返回与保护字段保持同周期。
 .o_credit_init_done(o_rd_credit_init_done), // 实际原账户返回与保护字段保持同周期。
 .o_credit_valid_parity(o_rd_credit_valid_parity), // 实际原账户返回与保护字段保持同周期。
 .o_credit_parity(o_rd_credit_parity), // 实际原账户返回与保护字段保持同周期。
 .o_receive_accepted(o_receive_accepted[2]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_ingress_errors(o_ingress_errors[2*(13) +: 13]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_errors(o_head_errors[2*(13) +: 13]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_control_error(o_control_error[2]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_data_error(o_data_error[2]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_auth_error(o_auth_error[2]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_auth_profile_error(o_auth_profile_error[2]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_metadata_error(o_metadata_error[2]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_fault_stop_request(o_fault_stop_request[2]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_storage_diagnostic(o_storage_diagnostic[2*(3) +: 3]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_counts(o_counts[2*(C_NUM_PORTS*5*C_CREDIT_WIDTH) +: C_NUM_PORTS*5*C_CREDIT_WIDTH]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_pending_count(o_pending_count[2*(4*C_PENDING_WIDTH) +: 4*C_PENDING_WIDTH]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_order_counts(o_order_counts[2*(C_NUM_PORTS*C_ORDER_COUNT_WIDTH) +: C_NUM_PORTS*C_ORDER_COUNT_WIDTH]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_order_error(o_order_error[2*(C_NUM_PORTS) +: C_NUM_PORTS]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_order_error_sticky(o_order_error_sticky[2*(C_NUM_PORTS) +: C_NUM_PORTS]) // 完整连接该通道的冻结输入、可信头和诊断。
); // 结束rd实际接收实例。
upli_native_rx_channel #(.CHANNEL_KIND(2),.C_PAYLOAD_WIDTH(101),.C_NUM_PORTS(C_NUM_PORTS), // wr独立保护封套和实际SRAM存储。
 .C_CREDIT_WIDTH(C_CREDIT_WIDTH),.C_DEFAULT_CAPACITY(C_DEFAULT_CAPACITY),.C_CAPACITIES(C_WR_CAPACITIES), // 原账户容量原样下传。
 .C_RETURN_DEPTH(C_RETURN_DEPTH),.C_PENDING_WIDTH(C_PENDING_WIDTH),.C_ORDER_COUNT_WIDTH(C_ORDER_COUNT_WIDTH)) u_wr( // 复用唯一信用和顺序journal所有者。
 .i_clk(i_clk), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_rstn(i_rstn), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_credit_connected(i_originator_credit_connected), // 实际原账户返回与保护字段保持同周期。
 .i_beats_connected(i_originator_beats_connected), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_drop(i_originator_drop), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_auth_enabled(i_auth_enabled), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_valid(i_wr_valid), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_port(i_wr_port), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_vc(i_wr_vc), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_pool(i_wr_pool), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_payload(i_wr_payload), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_received_parity(i_wr_parity), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_consumer_port(i_wr_consumer_port), // 完整连接该通道的冻结输入、可信头和诊断。
 .i_consumer_ready(i_wr_consumer_ready), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_payload(o_wr_head_payload), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_parity(o_wr_head_parity), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_vc(o_wr_head_vc), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_pool(o_wr_head_pool), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_account(o_wr_head_account), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_valid(o_wr_head_valid), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_consume_valid(o_wr_consume_valid), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_credit_valid(o_wr_credit_valid), // 实际原账户返回与保护字段保持同周期。
 .o_credit_pool(o_wr_credit_pool), // 实际原账户返回与保护字段保持同周期。
 .o_credit_vc(o_wr_credit_vc), // 实际原账户返回与保护字段保持同周期。
 .o_credit_num(o_wr_credit_num), // 实际原账户返回与保护字段保持同周期。
 .o_credit_init_done(o_wr_credit_init_done), // 实际原账户返回与保护字段保持同周期。
 .o_credit_valid_parity(o_wr_credit_valid_parity), // 实际原账户返回与保护字段保持同周期。
 .o_credit_parity(o_wr_credit_parity), // 实际原账户返回与保护字段保持同周期。
 .o_receive_accepted(o_receive_accepted[3]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_ingress_errors(o_ingress_errors[3*(13) +: 13]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_head_errors(o_head_errors[3*(13) +: 13]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_control_error(o_control_error[3]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_data_error(o_data_error[3]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_auth_error(o_auth_error[3]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_auth_profile_error(o_auth_profile_error[3]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_metadata_error(o_metadata_error[3]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_fault_stop_request(o_fault_stop_request[3]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_storage_diagnostic(o_storage_diagnostic[3*(3) +: 3]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_counts(o_counts[3*(C_NUM_PORTS*5*C_CREDIT_WIDTH) +: C_NUM_PORTS*5*C_CREDIT_WIDTH]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_pending_count(o_pending_count[3*(4*C_PENDING_WIDTH) +: 4*C_PENDING_WIDTH]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_order_counts(o_order_counts[3*(C_NUM_PORTS*C_ORDER_COUNT_WIDTH) +: C_NUM_PORTS*C_ORDER_COUNT_WIDTH]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_order_error(o_order_error[3*(C_NUM_PORTS) +: C_NUM_PORTS]), // 完整连接该通道的冻结输入、可信头和诊断。
 .o_order_error_sticky(o_order_error_sticky[3*(C_NUM_PORTS) +: C_NUM_PORTS]) // 完整连接该通道的冻结输入、可信头和诊断。
); // 结束wr实际接收实例。
assign o_req_head_taken=req_ready && o_req_consume_valid; // 只有完整Request头复制才退休原账户。
assign o_data_head_taken=data_ready && o_data_consume_valid; // 每个真实数据头只建立一次返回记录。
upli_endpoint_request_bridge #(.C_NUM_PORTS(C_NUM_PORTS)) u_bridge( // 单holding预留完整四拍空间，不再分配Tag。
 .i_clk(i_clk), // 保留头转移与下游请求接纳之间的独立所有权。
 .i_rstn(bridge_rstn), // 保留头转移与下游请求接纳之间的独立所有权。
 .i_select_port(i_select_port), // 保留头转移与下游请求接纳之间的独立所有权。
 .o_req_consumer_port(o_req_consumer_port), // 保留头转移与下游请求接纳之间的独立所有权。
 .i_req_head_valid(o_req_head_valid), // 保留头转移与下游请求接纳之间的独立所有权。
 .i_req_consume_valid(o_req_consume_valid), // 保留头转移与下游请求接纳之间的独立所有权。
 .i_req_payload(o_req_head_payload), // 保留头转移与下游请求接纳之间的独立所有权。
 .i_req_vc(o_req_head_vc), // 保留头转移与下游请求接纳之间的独立所有权。
 .i_req_pool(o_req_head_pool), // 保留头转移与下游请求接纳之间的独立所有权。
 .o_req_consumer_ready(req_ready), // 保留头转移与下游请求接纳之间的独立所有权。
 .o_data_consumer_port(o_data_consumer_port), // 保留头转移与下游请求接纳之间的独立所有权。
 .i_data_head_valid(o_data_head_valid), // 保留头转移与下游请求接纳之间的独立所有权。
 .i_data_consume_valid(o_data_consume_valid), // 保留头转移与下游请求接纳之间的独立所有权。
 .i_data_payload(o_data_head_payload), // 保留头转移与下游请求接纳之间的独立所有权。
 .i_data_vc(o_data_head_vc), // 保留头转移与下游请求接纳之间的独立所有权。
 .i_data_pool(o_data_head_pool), // 保留头转移与下游请求接纳之间的独立所有权。
 .o_data_consumer_ready(data_ready), // 保留头转移与下游请求接纳之间的独立所有权。
 .i_request_ready(i_request_ready), // 保留头转移与下游请求接纳之间的独立所有权。
 .o_request_valid(o_request_valid), // 保留头转移与下游请求接纳之间的独立所有权。
 .o_request_port(o_request_port), // 保留头转移与下游请求接纳之间的独立所有权。
 .o_request_vc(o_request_vc), // 保留头转移与下游请求接纳之间的独立所有权。
 .o_request_pool(o_request_pool), // 保留头转移与下游请求接纳之间的独立所有权。
 .o_request_payload(o_request_payload), // 保留头转移与下游请求接纳之间的独立所有权。
 .o_request_data(o_request_data), // 保留头转移与下游请求接纳之间的独立所有权。
 .o_request_be(o_request_be), // 保留头转移与下游请求接纳之间的独立所有权。
 .o_request_poison(o_request_poison), // 保留头转移与下游请求接纳之间的独立所有权。
 .o_request_data_pools(o_request_data_pools), // 保留头转移与下游请求接纳之间的独立所有权。
 .o_busy(o_bridge_busy), // 保留头转移与下游请求接纳之间的独立所有权。
 .o_error(o_bridge_error) // 保留头转移与下游请求接纳之间的独立所有权。
); // 结束完整普通Read/Write请求组装。
upli_receive_tdm_monitor #(.C_NUM_PORTS(C_NUM_PORTS)) u_tdm( // 原始事件驱动三相位诊断，信用不受TDM过滤。
 .i_clk(i_clk), // Request与OrigData共相位，两个响应各自建立相位。
 .i_rstn(i_rstn), // Request与OrigData共相位，两个响应各自建立相位。
 .i_req_valid(i_req_valid), // Request与OrigData共相位，两个响应各自建立相位。
 .i_req_port(i_req_port), // Request与OrigData共相位，两个响应各自建立相位。
 .i_data_valid(i_data_valid), // Request与OrigData共相位，两个响应各自建立相位。
 .i_data_port(i_data_port), // Request与OrigData共相位，两个响应各自建立相位。
 .i_rd_valid(i_rd_valid), // Request与OrigData共相位，两个响应各自建立相位。
 .i_rd_port(i_rd_port), // Request与OrigData共相位，两个响应各自建立相位。
 .i_wr_valid(i_wr_valid), // Request与OrigData共相位，两个响应各自建立相位。
 .i_wr_port(i_wr_port), // Request与OrigData共相位，两个响应各自建立相位。
 .o_error(o_tdm_error), // Request与OrigData共相位，两个响应各自建立相位。
 .o_error_sticky(o_tdm_error_sticky), // Request与OrigData共相位，两个响应各自建立相位。
 .o_phase_known(o_tdm_phase_known), // Request与OrigData共相位，两个响应各自建立相位。
 .o_expected_port(o_tdm_expected_port) // Request与OrigData共相位，两个响应各自建立相位。
); // 诊断导出给外部角色所有者，不在此私自恢复。
endmodule // 结束受保护原生接收路径总装候选。
`default_nettype wire // 恢复文件外部默认网络类型。
