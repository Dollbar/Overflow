`timescale 1ns/1ps // 同域响应选择与实际RX退休共用采样沿。
`default_nettype none // 完整响应与账户字段禁止隐式漏接。
module upli_endpoint_response_collector #( // 响应收集模块提供本地双通道交付适配，不新增存储或信用所有者。
    parameter integer C_NUM_PORTS = 1 // 支持一、二、四物理端口。
)( // 所有二项扁平总线低项为Read、高项为Write。
    input wire i_clk, i_rstn, // 共同上升沿时钟和同步低有效复位。
    input wire i_stop, // 外部角色故障或其他已定义业务停止资格。
    input wire [1:0] i_select_valid, // 上游两个独立端口选择请求，不是原生valid。
    input wire [3:0] i_select_port, // 每通道两位物理端口选择。
    input wire [1:0] i_head_valid, i_consume_valid, // 原RX的保护头资格及包含信用队列空间的退休资格。
    input wire [3:0] i_head_vc, // 原SRAM所保存的两个VC字段。
    input wire [1:0] i_head_pool, // 原SRAM所保存的两个Pool字段。
    input wire [5:0] i_head_account, // 原RX的两个账户选择，零至三专用、四共享。
    input wire [618:0] i_read_payload, // 完整Read原生字段含Auth、poison和Src调试字段。
    input wire [100:0] i_write_payload, // 完整Write字段含TypeInfo，ISOLATE不作为普通完成解释。
    input wire [1:0] i_retire_ready, // 下游真实接受完整响应事件的资格。
    output wire [3:0] o_consumer_port, // 唯一原RX的端口选择，锁定期间不被新选择改变。
    output wire [1:0] o_consumer_ready, // 唯一退休握手返回原RX，不另生成信用。
    output wire [1:0] o_response_valid, // 必须同时有真实头和原RX退休资格。
    output wire [3:0] o_response_port, o_response_vc, // 与完整响应同属一个实际头的端口与VC。
    output wire [1:0] o_response_pool, // 原始共享池标志，不重建或抹去VC。
    output wire [5:0] o_response_account, // 原账户仅观察，不能驱动第二个归还队列。
    output wire [618:0] o_read_payload, // 无效时确定归零，有效时完整保留619位。
    output wire [100:0] o_write_payload, // 无效时确定归零，有效时完整保留101位。
    output wire [1:0] o_retired, // 本沿实际业务退休事件，与原RX握手一一对应。
    output wire [1:0] o_metadata_error, // 当前沿非法选择或可信头账户不匹配。
    output wire o_fault_stop_request // 本地诊断保持至共同复位，由外层决定角色Drop范围。
); // 结束无新增信用接口的响应交付层。
    reg [1:0] reg_locked; // 头已经可见但尚未退休时保持该通道所有权。
    reg [3:0] reg_port; // 两个独立通道各保存一个已锁定物理端口。
    reg reg_error; // 元数据故障保持至复位，不能静默跳过坏头。
    wire [1:0] selected; // 当前通道有外部选择或既有锁定所有权。
    wire flag_operate; // 当前业务动作统一故障和停止门控。
    localparam [2:0] C_PORT_LIMIT = C_NUM_PORTS[2:0]; // 与原生两位port零扩展比较以覆盖非法索引。
    localparam [31:0] C_CHANNELS = 32'd2; // 静态展开两种响应通道，不混用原生kind编号。
    genvar c; // 两条独立头选择路径的常量索引。
    assign o_fault_stop_request = i_rstn && (reg_error || (|o_metadata_error)); // 当前故障立即阻断并在时钟沿保存历史。
    assign flag_operate = i_rstn && !i_stop && !o_fault_stop_request; // Stop不清除锁定，不触碰已登记信用。
    assign o_consumer_ready = o_response_valid & i_retire_ready; // 一个下游退休精确对应一个原RX退休。
    assign o_retired = o_consumer_ready; // 独立外部账本观察唯一实际退休事件。
    assign o_response_port = o_consumer_port; // 无效时端口仍表示本地查询，不声称有效响应元数据。
    assign o_read_payload = i_read_payload & {619{o_response_valid[0]}}; // 不遮蔽错误数据、Auth、Src或poison字段。
    assign o_write_payload = i_write_payload & {101{o_response_valid[1]}}; // TypeInfo不用于这里的事务准入。
    always @(posedge i_clk) begin // 本地错误仅在共同reset后清除。
        if (!i_rstn) reg_error <= 1'b0; // 新epoch不保留旧诊断。
        else if (|o_metadata_error) reg_error <= 1'b1; // 元数据错误不能靠下一拍字段变化恢复业务。
    end // 结束诊断历史。
    generate // 参数保护和两路独立所有权展开。
        if ((C_NUM_PORTS != 1) && (C_NUM_PORTS != 2) && (C_NUM_PORTS != 4)) begin : gen_invalid // 非法port数量不静默缩小。
            upli_endpoint_response_collector_ports_invalid Invalid_Ports_Inst (); // 非法配置要求展开失败。
        end // 结束参数合法性保护。
        for (c = 32'd0; c < C_CHANNELS; c = c+32'd1) begin : gen_channel // Read和Write不施加跨通道全局顺序。
            wire [1:0] current_port; // 当前查询端口由锁定所有权优先选择。
            wire port_legal, account_legal; // 只检查本层可信结构元数据，不解释响应状态或Tag。
            assign current_port = reg_locked[c] ? reg_port[c*2 +: 2] : i_select_port[c*2 +: 2]; // 反压期间新的外部选择不能更换有效头。
            assign selected[c] = reg_locked[c] || i_select_valid[c]; // 已锁定头不受新候选撤销影响。
            assign port_legal = ({1'b0,current_port} < C_PORT_LIMIT); // 原生port按完整两位检查。
            assign account_legal = i_head_account[c*3 +: 3] == (i_head_pool[c] ? 3'd4 : {1'b0,i_head_vc[c*2 +: 2]}); // 共享账户四仍保留原始VC。
            assign o_metadata_error[c] = i_rstn && selected[c] && (!port_legal || (i_head_valid[c] && !account_legal)); // 没有实际头时不解释旧账户字段。
            assign o_consumer_port[c*2 +: 2] = current_port & {2{i_rstn}}; // 复位期间查询端口确定归零。
            assign o_response_valid[c] = flag_operate && selected[c] && i_head_valid[c] && i_consume_valid[c]; // 归还队列背压不能表现为成功交付。
            assign o_response_vc[c*2 +: 2] = i_head_vc[c*2 +: 2] & {2{o_response_valid[c]}}; // 真实保存VC跟随有效响应。
            assign o_response_pool[c] = i_head_pool[c] & o_response_valid[c]; // 真实保存Pool跟随有效响应。
            assign o_response_account[c*3 +: 3] = i_head_account[c*3 +: 3] & {3{o_response_valid[c]}}; // 无效账户观察归零。
            always @(posedge i_clk) begin // 每通道头所有权独立推进。
                if (!i_rstn) begin // 共同复位取消尚未退休的选择锁。
                    reg_locked[c] <= 1'b0; // 下一个epoch重新等待上游选择。
                    reg_port[c*2 +: 2] <= 2'd0; // 无旧端口残留。
                end else if (o_retired[c]) begin // 仅原RX与真实下游共同退休才释放所有权。
                    reg_locked[c] <= 1'b0; // 下周期可选择任一端口。
                end else if (flag_operate && selected[c] && i_head_valid[c]) begin // 信用返回空间不足时也必须先锁定可见头。
                    reg_locked[c] <= 1'b1; // 头未交付前不切换查询。
                    reg_port[c*2 +: 2] <= current_port; // 保存可见头对应的物理端口。
                end // 结束保持或更新选择锁。
            end // 结束当前通道所有权寄存。
        end // 结束两路独立响应交付路径。
    endgenerate // 结束静态结构。
endmodule // 结束响应收集模块，不实现事务Tag匹配、认证、Isolation或信用初始化。
`default_nettype wire // 恢复后续独立源码的默认网络规则。
