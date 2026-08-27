module kdlink_leaf_domain_model ( // 定义支持混合板卡划分的三十二NPU叶域模型
    input wire clk_i, // 接收叶域逻辑时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire prepare_i, // 接收板卡目录prepare请求
    input wire [15:0] prepare_epoch_i, // 接收板卡目录目标epoch
    input wire entry_valid_i, // 接收卡槽描述符valid
    output wire entry_ready_o, // 输出卡槽描述符ready
    input wire [4:0] entry_slot_i, // 接收最多三十二个卡槽编号
    input wire [4:0] entry_base_node_i, // 接收卡槽首node编号
    input wire [2:0] entry_npu_count_code_i, // 接收一至三十二NPU规格码
    output wire entry_reject_o, // 输出非法卡槽描述符拒绝
    input wire commit_i, // 接收板卡目录原子提交请求
    input wire quiescent_i, // 接收叶域静默状态
    output wire commit_accept_o, // 输出板卡目录提交成功
    output wire commit_reject_o, // 输出板卡目录提交拒绝
    input wire [31:0] card_present_i, // 接收最多三十二张卡在位状态
    input wire [31:0] card_reset_done_i, // 接收最多三十二张卡复位完成状态
    input wire [7:0] plane_enable_i, // 接收八个独立交换平面使能
    input wire [511:0] endpoint_slice_link_up_i, // 接收三十二NPU全部slice链路状态
    input wire [511:0] endpoint_tx_valid_i, // 接收全部endpoint发送valid
    output wire [511:0] endpoint_tx_ready_o, // 输出全部endpoint发送ready
    input wire [327679:0] endpoint_tx_flit_i, // 接收全部endpoint六百四十位flit
    output wire [511:0] endpoint_rx_valid_o, // 输出全部endpoint接收valid
    input wire [511:0] endpoint_rx_ready_i, // 接收全部endpoint接收ready
    output wire [327679:0] endpoint_rx_flit_o, // 输出全部endpoint接收flit
    output wire [31:0] configured_node_mask_o, // 输出目录已映射node掩码
    output wire [31:0] node_active_o, // 输出卡级健康node掩码
    output wire [31:0] card_active_o, // 输出已配置且健康卡槽掩码
    output wire [15:0] active_epoch_o, // 输出活动板卡目录epoch
    output wire shadow_error_o, // 输出板卡目录shadow错误
    output wire [15:0] protocol_error_o // 输出八平面交换协议错误
); // 结束通用叶域模型端口声明
    wire [31:0] configured_slot_mask; // 接收板卡目录已配置卡槽掩码
    wire [511:0] qualified_slice_link_up; // 保存卡平面和slice联合可用状态
    wire [511:0] fabric_tx_valid; // 保存进入交换平面的有效flit掩码
    wire [511:0] fabric_tx_ready; // 接收交换平面入口ready
    wire [327679:0] fabric_tx_flit; // 保存进入交换平面的flit数据
    wire [511:0] fabric_rx_valid; // 接收交换平面出口valid
    wire [511:0] fabric_rx_ready; // 保存交换平面出口ready
    wire [327679:0] fabric_rx_flit; // 接收交换平面出口flit数据
    genvar node_index; // 展开三十二个NPU节点
    genvar plane_index; // 展开每个NPU八个交换平面
    genvar slice_index; // 展开每个端口两个bonded slice

    assign card_active_o = configured_slot_mask & card_present_i & card_reset_done_i; // 合并配置在位和复位形成卡槽健康掩码
    assign fabric_tx_valid = endpoint_tx_valid_i & qualified_slice_link_up; // 阻断不可用node平面或slice的新发送
    assign endpoint_tx_ready_o = fabric_tx_ready & qualified_slice_link_up; // 仅向可用endpoint返回发送ready
    assign fabric_tx_flit = endpoint_tx_flit_i; // 保持可用入口flit位级不变
    assign endpoint_rx_valid_o = fabric_rx_valid & qualified_slice_link_up; // 阻断向不可用endpoint交付数据
    assign fabric_rx_ready = endpoint_rx_ready_i & qualified_slice_link_up; // 仅允许可用endpoint消费交换输出
    assign endpoint_rx_flit_o = fabric_rx_flit; // 保持交换出口flit位级不变

    kdlink_card_directory u_card_directory ( // 实例化可综合原子板卡目录
        .clk_i(clk_i), .rst_n_i(rst_n_i), .prepare_i(prepare_i), .prepare_epoch_i(prepare_epoch_i), // 连接目录时钟复位和prepare接口
        .entry_valid_i(entry_valid_i), .entry_ready_o(entry_ready_o), .entry_slot_i(entry_slot_i), // 连接目录描述符握手和卡槽
        .entry_base_node_i(entry_base_node_i), .entry_npu_count_code_i(entry_npu_count_code_i), .entry_reject_o(entry_reject_o), // 连接目录范围规格和拒绝状态
        .commit_i(commit_i), .quiescent_i(quiescent_i), .commit_accept_o(commit_accept_o), .commit_reject_o(commit_reject_o), // 连接目录原子提交控制
        .card_present_i(card_present_i), .card_reset_done_i(card_reset_done_i), .query_node_i(5'd0), // 连接卡状态并固定未使用单node查询
        .query_mapped_o(), .query_slot_o(), .query_local_npu_o(), .query_npu_count_code_o(), .query_active_o(), // 忽略叶域数据门控不需要的单node查询输出
        .configured_node_mask_o(configured_node_mask_o), .node_active_o(node_active_o), // 接收node映射和健康掩码
        .configured_slot_mask_o(configured_slot_mask), .active_epoch_o(active_epoch_o), .shadow_error_o(shadow_error_o) // 接收卡槽掩码epoch和shadow错误
    ); // 结束板卡目录实例

    generate // 展开全部五百一十二条叶域slice路径的分层门控
        for (node_index = 0; node_index < 32; node_index = node_index + 1) begin : gen_node // 为每个NPU生成路径门控
            for (plane_index = 0; plane_index < 8; plane_index = plane_index + 1) begin : gen_plane // 为每个交换平面生成路径门控
                for (slice_index = 0; slice_index < 2; slice_index = slice_index + 1) begin : gen_slice // 为每个bonded slice生成路径门控
                    localparam integer ENDPOINT_INDEX = node_index*16 + plane_index*2 + slice_index; // 计算固定endpoint slice索引
                    assign qualified_slice_link_up[ENDPOINT_INDEX] = endpoint_slice_link_up_i[ENDPOINT_INDEX] && node_active_o[node_index] && plane_enable_i[plane_index]; // 联合卡node平面和物理slice状态
                end // 结束单个slice门控生成
            end // 结束单个平面门控生成
        end // 结束单个node门控生成
    endgenerate // 结束全部叶域slice路径门控

    kdlink_fabric32 u_fabric ( // 实例化保持不变的三十二节点八平面交换fabric
        .clk_i(clk_i), .rst_n_i(rst_n_i), .endpoint_tx_valid_i(fabric_tx_valid), .endpoint_tx_ready_o(fabric_tx_ready), // 连接fabric入口握手
        .endpoint_tx_flit_i(fabric_tx_flit), .endpoint_rx_valid_o(fabric_rx_valid), .endpoint_rx_ready_i(fabric_rx_ready), // 连接fabric数据和出口握手
        .endpoint_rx_flit_o(fabric_rx_flit), .protocol_error_o(protocol_error_o) // 连接fabric出口数据和协议错误
    ); // 结束三十二节点fabric实例
endmodule // 结束kdlink_leaf_domain_model模块
