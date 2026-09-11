`timescale 1ns/1ps // 原生保护和实际接收存储使用同一采样时钟。
`default_nettype none // 禁止完整保护封套的元数据漏接。
module upli_native_rx_channel #( // 原生接收模块，复用唯一有序存储和信用所有者。
    parameter integer CHANNEL_KIND = 0, // Request、Read、Write、OrigData四种原生封套。
    parameter integer C_PAYLOAD_WIDTH = (CHANNEL_KIND==0)?184:(CHANNEL_KIND==1)?619:(CHANNEL_KIND==2)?101:580, // 全宽字段布局固定。
    parameter integer C_NUM_PORTS = 1, // 一、二或四物理端口。
    parameter integer C_CREDIT_WIDTH = 4, // 真实账户容量计数宽度。
    parameter [C_CREDIT_WIDTH-1:0] C_DEFAULT_CAPACITY = 3, // 每账户默认三个实际存储项。
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_CAPACITIES = {C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}, // 逐端口VC零至三及pool容量。
    parameter integer C_RETURN_DEPTH = 4, // 直接复用已有归还队列深度。
    parameter integer C_PENDING_WIDTH = (C_RETURN_DEPTH<=1)?1:(C_RETURN_DEPTH<=3)?2:(C_RETURN_DEPTH<=7)?3:(C_RETURN_DEPTH<=15)?4:5, // 与实际返回队列相同观察宽度。
    parameter integer C_ORDER_COUNT_WIDTH = C_CREDIT_WIDTH+3 // 五账户顺序项总量的既有宽度。
)( // 本地消费ready不扩展为原生入站ready。
    input wire i_clk, i_rstn, // 同域时钟和同步低有效共同reset。
    input wire i_credit_connected, i_beats_connected, i_drop, // 外部真实连接状态及唯一角色Drop所有者。
    input wire i_auth_enabled, // 授权profile配置在仍有存储所有权时必须稳定。
    input wire i_valid, // 实际原生有效事件，校验前不能假定其可靠。
    input wire [1:0] i_port, i_vc, // 原生字段全宽参与保护。
    input wire i_pool, // 原始信用账户类型。
    input wire [C_PAYLOAD_WIDTH-1:0] i_payload, // 完整原生负载。
    input wire [12:0] i_received_parity, // 原始收到保护码，不能先重算。
    input wire [1:0] i_consumer_port, // 仅选择物理端口，账户由实际顺序journal确定。
    input wire i_consumer_ready, // 业务消费者真实接纳资格。
    output wire [C_PAYLOAD_WIDTH-1:0] o_head_payload, // 真实SRAM头检查和poison归一化之后的负载。
    output wire [12:0] o_head_parity, o_ingress_errors, o_head_errors, // 新保护与两个原始检查边界分别公开。
    output wire o_control_error, o_data_error, o_auth_error, o_auth_profile_error, o_metadata_error, // 错误分类不混淆。
    output wire o_fault_stop_request, // 请求唯一角色所有者停止业务，不能冒称自动恢复。
    output wire [1:0] o_head_vc, // 实际存储原始VC。
    output wire o_head_pool, // 实际存储原始pool。
    output wire [2:0] o_head_account, // 最早接纳项的账户，非重新仲裁。
    output wire o_head_valid, o_consume_valid, o_receive_accepted, // 真实头资格及上一沿实际SRAM写入观察。
    output wire [2:0] o_storage_diagnostic, // 既有存储输入诊断保持原语义。
    output wire [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] o_counts, // 唯一账户存储的真实占用。
    output wire [4*C_PENDING_WIDTH-1:0] o_pending_count, // 唯一归还队列待发布量。
    output wire [C_NUM_PORTS*C_ORDER_COUNT_WIDTH-1:0] o_order_counts, // 每端口顺序journal占用。
    output wire [C_NUM_PORTS-1:0] o_order_error, o_order_error_sticky, // 既有顺序一致性诊断。
    output wire [3:0] o_credit_valid, o_credit_pool, o_credit_init_done, // 直接保护真实已登记信用输出。
    output wire [7:0] o_credit_vc, o_credit_num, // 归还保存的原始账户，不按当前输入猜测。
    output wire o_credit_valid_parity, o_credit_parity // 实际完整返回组保护码。
); // 结束四类原生接收接口。
    localparam integer C_ENVELOPE_WIDTH = C_PAYLOAD_WIDTH+18; // 保存port二位、VC二位、pool一位、parity十三位和完整负载。
    wire [C_PAYLOAD_WIDTH-1:0] normalized_payload; // 入站data/BE错误只置本拍poison。
    wire [12:0] normalized_parity; // 新保护覆盖归一化后的完整负载与元数据。
    wire [C_ENVELOPE_WIDTH-1:0] saved_envelope; // 唯一真实SRAM所返回的保护封套。
    wire [1:0] saved_port, saved_vc; // 受原生控制保护的存储元数据副本。
    wire saved_pool; // 与接收FIFO原pool及选择账户交叉检查。
    wire ingress_control, ingress_data, ingress_auth, ingress_profile; // 入口原始错误独立于是否成功接纳。
    wire head_control, head_data, head_auth, head_profile; // 实际读头保护检查结果。
    wire raw_head_valid, raw_consume_valid, flag_operate; // 业务gate不能改变底层已登记信用。
    wire [3:0] raw_credit_valid, raw_credit_pool, raw_credit_done; // 唯一归还/初始化组件输出。
    wire [7:0] raw_credit_vc, raw_credit_num; // 不增加第二套返回记录或批次。
    assign {saved_port,saved_vc,saved_pool} = saved_envelope[C_ENVELOPE_WIDTH-1:C_PAYLOAD_WIDTH+13]; // 元数据来自真实封套，不借用输入字段。
    assign o_control_error = ingress_control || head_control; // 规范控制错误独立保留。
    assign o_data_error = ingress_data || head_data; // 新检测data/BE错误不从Status推断。
    assign o_auth_error = ingress_auth || head_auth; // 授权保护错误不是认证验证结果。
    assign o_auth_profile_error = ingress_profile || head_profile; // 当前Auth inactive资格单独公开。
    assign o_metadata_error = i_rstn && raw_head_valid && ((saved_port != i_consumer_port) || (saved_vc != o_head_vc) || (saved_pool != o_head_pool) || (o_head_account != (saved_pool ? 3'd4 : {1'b0,saved_vc}))); // 封套选择身份和唯一存储账户必须一致。
    assign o_fault_stop_request = i_rstn && (o_control_error || o_auth_error || o_auth_profile_error || o_metadata_error || (|o_order_error) || (|o_order_error_sticky) || (|o_storage_diagnostic)); // 本地异常交由角色范围所有者保持Drop。
    assign flag_operate = i_rstn && !i_drop && !o_fault_stop_request; // 坏拍和坏头当沿共同禁止保存及业务退休。
    assign o_head_valid = raw_head_valid && flag_operate; // 只有已保护可用头才能公开业务有效。
    assign o_consume_valid = raw_consume_valid && flag_operate; // 与底层真实退休使用同一gate。
    upli_native_rx_protection #(.CHANNEL_KIND(CHANNEL_KIND),.C_PAYLOAD_WIDTH(C_PAYLOAD_WIDTH)) u_ingress ( // 入口先检查收到码再生成保护封套。
        .i_auth_enabled(i_auth_enabled),.i_check_enable(i_rstn),.i_valid(i_valid),.i_port(i_port),.i_vc(i_vc),.i_pool(i_pool), // valid零仍检查原生valid保护。
        .i_payload(i_payload),.i_received_parity(i_received_parity),.o_payload(normalized_payload),.o_parity(normalized_parity), // 完整本拍错误保留到新保护建立边界。
        .o_errors(o_ingress_errors),.o_control_error(ingress_control),.o_data_error(ingress_data),.o_auth_error(ingress_auth),.o_auth_profile_error(ingress_profile) // 不静默吞掉Auth分类。
    ); // 结束入口保护转换。
    upli_native_rx_protection #(.CHANNEL_KIND(CHANNEL_KIND),.C_PAYLOAD_WIDTH(C_PAYLOAD_WIDTH)) u_head ( // 真实SRAM头再次检查原保护并归一化新data错误。
        .i_auth_enabled(i_auth_enabled),.i_check_enable(i_rstn && raw_head_valid),.i_valid(raw_head_valid),.i_port(saved_port),.i_vc(saved_vc),.i_pool(saved_pool), // 无实际头时不解释旧数据。
        .i_payload(saved_envelope[C_PAYLOAD_WIDTH-1:0]),.i_received_parity(saved_envelope[C_PAYLOAD_WIDTH+12:C_PAYLOAD_WIDTH]),.o_payload(o_head_payload),.o_parity(o_head_parity), // 原始封套保护检查覆盖到对外新保护。
        .o_errors(o_head_errors),.o_control_error(head_control),.o_data_error(head_data),.o_auth_error(head_auth),.o_auth_profile_error(head_profile) // 控制/Auth坏头禁止退休而非伪造归还。
    ); // 结束存储保护交叠边界。
    upli_ordered_receive_channel #( // 实际有序接收层是唯一存储/信用所有者。
        .C_NUM_PORTS(C_NUM_PORTS),.C_PAYLOAD_WIDTH(C_ENVELOPE_WIDTH),.C_CREDIT_WIDTH(C_CREDIT_WIDTH),.C_DEFAULT_CAPACITY(C_DEFAULT_CAPACITY),.C_CAPACITIES(C_CAPACITIES), // 封套位宽不增加信用容量。
        .C_RETURN_DEPTH(C_RETURN_DEPTH),.C_PENDING_WIDTH(C_PENDING_WIDTH),.C_ORDER_COUNT_WIDTH(C_ORDER_COUNT_WIDTH) // 直接继承真实队列参数。
    ) u_receive ( // 既有组件内部唯一实例化receive_channel及真实KD28 SRAM。
        .i_clk(i_clk),.i_rstn(i_rstn),.i_credit_connected(i_credit_connected),.i_beats_connected(i_beats_connected), // Drop不是reset，不重新初始化账本。
        .i_receive_valid(i_valid && flag_operate),.i_receive_port(i_port),.i_receive_vc(i_vc),.i_receive_pool(i_pool), // 坏入站不写SRAM、不制造返回记录。
        .i_receive_payload({i_port,i_vc,i_pool,normalized_parity,normalized_payload}), // 实际写入完整保护封套。
        .i_consumer_port(i_consumer_port),.i_consumer_ready(i_consumer_ready && flag_operate), // 外部consume握手与实际SRAM退休保持完全相同。
        .o_head_payload(saved_envelope),.o_head_vc(o_head_vc),.o_head_pool(o_head_pool),.o_head_account(o_head_account),.o_head_valid(raw_head_valid),.o_consume_valid(raw_consume_valid), // 全部消费字段来自同一真实头。
        .o_receive_accepted(o_receive_accepted),.o_diagnostic(o_storage_diagnostic),.o_counts(o_counts),.o_pending_count(o_pending_count), // 不改变注册accepted语义。
        .o_order_counts(o_order_counts),.o_order_error(o_order_error),.o_order_error_sticky(o_order_error_sticky), // 顺序元数据错误请求外部fault owner。
        .o_credit_valid(raw_credit_valid),.o_credit_pool(raw_credit_pool),.o_credit_vc(raw_credit_vc),.o_credit_num(raw_credit_num),.o_credit_init_done(raw_credit_done) // 保存的可信归还记录不因Drop被撤销。
    ); // 结束唯一有序存储实例。
    upli_credit_return_adapter u_return ( // 直接保护原有注册返回，不建立新队列或TDM。
        .i_credit_valid(raw_credit_valid),.i_credit_pool(raw_credit_pool),.i_credit_vc(raw_credit_vc),.i_credit_num(raw_credit_num),.i_credit_init_done(raw_credit_done), // 保留完整原账户归还字段。
        .o_credit_valid(o_credit_valid),.o_credit_pool(o_credit_pool),.o_credit_vc(o_credit_vc),.o_credit_num(o_credit_num),.o_credit_init_done(o_credit_init_done), // 初始化和正常返回均直接透传。
        .o_credit_valid_parity(o_credit_valid_parity),.o_credit_parity(o_credit_parity) // 实际返回完整组保护码。
    ); // 结束唯一返回保护适配器。
endmodule // 结束有限范围的原生安全接收候选。
`default_nettype wire // 恢复独立后续源码默认网络规则。
