`timescale 1ns/1ps // 定义可配置板卡叶域系统测试时间尺度
module tb_kdlink_card_profiles; // 定义六种统一规格和混插板卡系统自检
    logic clk; // 产生叶域逻辑时钟
    logic rst_n; // 驱动叶域低有效复位
    logic prepare; // 驱动板卡目录prepare
    logic [15:0] prepare_epoch; // 驱动板卡目录目标epoch
    logic entry_valid; // 驱动卡槽描述符valid
    wire entry_ready; // 观察卡槽描述符ready
    logic [4:0] entry_slot; // 驱动卡槽编号
    logic [4:0] entry_base_node; // 驱动卡槽首node
    logic [2:0] entry_npu_count_code; // 驱动卡槽NPU规格码
    wire entry_reject; // 观察卡槽描述符拒绝
    logic commit; // 驱动板卡目录提交
    logic quiescent; // 驱动叶域静默状态
    wire commit_accept; // 观察目录提交成功
    wire commit_reject; // 观察目录提交拒绝
    logic [31:0] card_present; // 驱动最多三十二张卡在位状态
    logic [31:0] card_reset_done; // 驱动最多三十二张卡复位完成状态
    logic [7:0] plane_enable; // 驱动八个交换平面使能
    logic [511:0] endpoint_slice_link_up; // 驱动五百一十二条slice链路状态
    logic [511:0] endpoint_tx_valid; // 驱动全部endpoint发送valid
    wire [511:0] endpoint_tx_ready; // 观察全部endpoint发送ready
    logic [327679:0] endpoint_tx_flit; // 驱动全部endpoint发送flit
    wire [511:0] endpoint_rx_valid; // 观察全部endpoint接收valid
    logic [511:0] endpoint_rx_ready; // 驱动全部endpoint接收ready
    wire [327679:0] endpoint_rx_flit; // 观察全部endpoint接收flit
    wire [31:0] configured_node_mask; // 观察目录node映射掩码
    wire [31:0] node_active; // 观察卡级健康node掩码
    wire [31:0] card_active; // 观察健康卡槽掩码
    wire [15:0] active_epoch; // 观察活动目录epoch
    wire shadow_error; // 观察shadow配置错误
    wire [15:0] protocol_error; // 观察交换fabric协议错误
    integer profile_code; // 遍历六种每卡NPU规格
    integer profile_count; // 保存当前规格每卡NPU数量
    integer profile_slots; // 保存当前规格卡槽数量
    integer slot_index; // 遍历当前配置卡槽
    integer node_index; // 遍历全部三十二node
    integer flit_index; // 遍历全部五百一十二路发送flit
    integer mixed_count [0:9]; // 保存十张混插卡的NPU数量
    integer mixed_base [0:9]; // 保存十张混插卡的首node
    logic [31:0] expected_slot_mask; // 保存当前布局期望卡槽掩码

    kdlink_leaf_domain_model u_dut ( // 实例化支持混合板卡划分的完整叶域模型
        .clk_i(clk), .rst_n_i(rst_n), .prepare_i(prepare), .prepare_epoch_i(prepare_epoch), // 连接叶域时钟复位和prepare
        .entry_valid_i(entry_valid), .entry_ready_o(entry_ready), .entry_slot_i(entry_slot), // 连接卡槽描述符握手和编号
        .entry_base_node_i(entry_base_node), .entry_npu_count_code_i(entry_npu_count_code), .entry_reject_o(entry_reject), // 连接卡槽范围规格和拒绝状态
        .commit_i(commit), .quiescent_i(quiescent), .commit_accept_o(commit_accept), .commit_reject_o(commit_reject), // 连接目录原子提交控制
        .card_present_i(card_present), .card_reset_done_i(card_reset_done), .plane_enable_i(plane_enable), // 连接卡槽和平面动态状态
        .endpoint_slice_link_up_i(endpoint_slice_link_up), .endpoint_tx_valid_i(endpoint_tx_valid), .endpoint_tx_ready_o(endpoint_tx_ready), // 连接endpoint链路和发送握手
        .endpoint_tx_flit_i(endpoint_tx_flit), .endpoint_rx_valid_o(endpoint_rx_valid), .endpoint_rx_ready_i(endpoint_rx_ready), // 连接endpoint发送数据和接收握手
        .endpoint_rx_flit_o(endpoint_rx_flit), .configured_node_mask_o(configured_node_mask), .node_active_o(node_active), // 连接endpoint接收数据和node状态
        .card_active_o(card_active), .active_epoch_o(active_epoch), .shadow_error_o(shadow_error), .protocol_error_o(protocol_error) // 连接卡槽epoch和错误状态
    ); // 结束通用叶域模型实例

    always #0.5 clk = ~clk; // 产生一GHz逻辑测试时钟

    task automatic start_prepare(input integer epoch_value); // 定义开始一次shadow配置的辅助过程
        begin // 开始prepare辅助过程主体
            @(negedge clk); prepare = 1'b1; prepare_epoch = epoch_value[15:0]; // 驱动prepare和目标epoch
            @(negedge clk); prepare = 1'b0; // 在下一下降沿撤销prepare
            if (!entry_ready || shadow_error) $fatal(1, "Leaf domain directory did not prepare cleanly"); // 检查shadow配置窗口已经打开
        end // 结束prepare辅助过程主体
    endtask // 结束start_prepare辅助过程

    task automatic write_entry( // 定义写入一个叶域卡槽描述符的辅助过程
        input integer slot_value, // 接收卡槽编号
        input integer base_value, // 接收首node编号
        input integer code_value // 接收NPU规格码
    ); // 结束write_entry端口声明
        begin // 开始描述符写入主体
            @(negedge clk); entry_valid = 1'b1; entry_slot = slot_value[4:0]; entry_base_node = base_value[4:0]; entry_npu_count_code = code_value[2:0]; // 驱动完整卡槽描述符
            @(negedge clk); entry_valid = 1'b0; // 在描述符采样后撤销valid
            @(negedge clk); // 等待一级描述符校验流水提交当前卡槽状态
        end // 结束描述符写入主体
    endtask // 结束write_entry辅助过程

    task automatic request_commit; // 定义叶域静默条件下的原子提交辅助过程
        begin // 开始提交辅助过程主体
            @(negedge clk); commit = 1'b1; // 驱动单周期commit请求
            @(negedge clk); commit = 1'b0; // 在commit采样后撤销请求
        end // 结束提交辅助过程主体
    endtask // 结束request_commit辅助过程

    initial begin // 执行全部叶域板卡规格集成测试
        clk = 1'b0; rst_n = 1'b0; prepare = 1'b0; prepare_epoch = 16'd0; // 初始化时钟复位和prepare接口
        entry_valid = 1'b0; entry_slot = 5'd0; entry_base_node = 5'd0; entry_npu_count_code = 3'd0; // 初始化卡槽描述符接口
        commit = 1'b0; quiescent = 1'b1; card_present = 32'hffffffff; card_reset_done = 32'hffffffff; // 初始化提交和卡槽动态状态
        plane_enable = 8'hff; endpoint_slice_link_up = {512{1'b1}}; endpoint_tx_valid = 512'd0; // 初始化全部平面slice和发送valid
        endpoint_rx_ready = {512{1'b1}}; // 初始化全部endpoint接收ready
        for (flit_index = 0; flit_index < 512; flit_index = flit_index + 1) begin // 清空全部五百一十二路发送flit
            endpoint_tx_flit[flit_index*640 +: 640] = 640'd0; // 清空当前endpoint发送flit
        end // 结束全部发送flit初始化
        mixed_count[0] = 8; mixed_count[1] = 8; mixed_count[2] = 4; mixed_count[3] = 4; mixed_count[4] = 2; // 定义混插布局前五张卡
        mixed_count[5] = 2; mixed_count[6] = 1; mixed_count[7] = 1; mixed_count[8] = 1; mixed_count[9] = 1; // 定义混插布局后五张卡
        mixed_base[0] = 0; mixed_base[1] = 8; mixed_base[2] = 16; mixed_base[3] = 20; mixed_base[4] = 24; // 定义混插布局前五个首node
        mixed_base[5] = 26; mixed_base[6] = 28; mixed_base[7] = 29; mixed_base[8] = 30; mixed_base[9] = 31; // 定义混插布局后五个首node
        repeat (4) @(posedge clk); // 保持复位覆盖多个逻辑周期
        @(negedge clk); rst_n = 1'b1; // 在下降沿释放复位
        #0.01; // 等待叶域组合门控稳定
        if (configured_node_mask != 32'hffffffff || card_active != 32'h000000ff || node_active != 32'hffffffff) $fatal(1, "Leaf default 8x4 layout mismatch"); // 检查旧八卡四NPU布局兼容
        for (profile_code = 0; profile_code < 6; profile_code = profile_code + 1) begin // 遍历六种统一板卡规格
            profile_count = 1 << profile_code; profile_slots = 32 >> profile_code; // 计算当前每卡NPU数和卡槽数
            start_prepare(profile_code + 1); // 为当前统一规格开始shadow配置
            for (slot_index = 0; slot_index < profile_slots; slot_index = slot_index + 1) begin // 配置当前布局全部卡槽
                write_entry(slot_index, slot_index * profile_count, profile_code); // 写入连续无重叠卡槽范围
            end // 结束当前统一规格卡槽写入
            request_commit(); // 原子提交当前统一布局
            if (!commit_accept || commit_reject || active_epoch != (profile_code[15:0] + 16'd1)) $fatal(1, "Leaf homogeneous commit failed profile=%0d", profile_code); // 检查提交结果和epoch
            if (profile_slots == 32) expected_slot_mask = 32'hffffffff; else expected_slot_mask = (32'h00000001 << profile_slots) - 32'h00000001; // 生成当前布局卡槽掩码
            if (configured_node_mask != 32'hffffffff || card_active != expected_slot_mask || node_active != 32'hffffffff) $fatal(1, "Leaf homogeneous masks mismatch profile=%0d", profile_code); // 检查node和卡槽全部可用
            card_present[profile_slots-1] = 1'b0; #0.01; // 拔出当前布局最后一张卡
            for (node_index = 0; node_index < 32; node_index = node_index + 1) begin // 检查node和slice故障隔离
                if (node_active[node_index] != (node_index < (32 - profile_count))) $fatal(1, "Leaf node isolation mismatch profile=%0d node=%0d", profile_code, node_index); // 检查只隔离被拔卡拥有的node
                if (node_index >= (32 - profile_count) && endpoint_tx_ready[node_index*16 +: 16] != 16'd0) $fatal(1, "Removed card still accepts endpoint traffic profile=%0d node=%0d", profile_code, node_index); // 检查被拔卡全部slice阻断ready
            end // 结束当前规格故障隔离检查
            card_present[profile_slots-1] = 1'b1; #0.01; // 恢复最后一张卡在位状态
        end // 结束六种统一规格测试
        start_prepare(16); // 开始混插板卡布局配置
        for (slot_index = 0; slot_index < 10; slot_index = slot_index + 1) begin // 写入十张不同规格板卡
            case (mixed_count[slot_index]) // 将混插NPU数量转换为三位规格码
                1: profile_code = 0; // 单NPU卡选择规格零
                2: profile_code = 1; // 双NPU卡选择规格一
                4: profile_code = 2; // 四NPU卡选择规格二
                8: profile_code = 3; // 八NPU卡选择规格三
                default: profile_code = 7; // 将非预期测试数据转换为非法码
            endcase // 结束混插规格转换
            write_entry(slot_index, mixed_base[slot_index], profile_code); // 写入当前混插卡描述符
        end // 结束十张混插卡写入
        request_commit(); // 原子提交混插布局
        if (!commit_accept || card_active != 32'h000003ff || node_active != 32'hffffffff || configured_node_mask != 32'hffffffff) $fatal(1, "Leaf mixed-card layout failed"); // 检查混插布局全部node和卡槽可用
        card_reset_done[2] = 1'b0; #0.01; // 复位混插布局中的首张四NPU卡
        if (node_active[19:16] != 4'd0 || node_active[15:0] != 16'hffff || node_active[31:20] != 12'hfff) $fatal(1, "Mixed-card reset isolation failed"); // 检查复位只隔离该卡四个node
        card_reset_done[2] = 1'b1; plane_enable[7] = 1'b0; #0.01; // 恢复卡并禁用第七交换平面
        for (node_index = 0; node_index < 32; node_index = node_index + 1) begin // 检查平面故障跨全部板型一致
            if (endpoint_tx_ready[node_index*16 + 14 +: 2] != 2'b00) $fatal(1, "Disabled plane accepts traffic node=%0d", node_index); // 检查每个node的双slice都被平面门控
        end // 结束平面故障检查
        plane_enable[7] = 1'b1; endpoint_slice_link_up[511] = 1'b0; #0.01; // 恢复平面并关闭最后一条物理slice
        if (endpoint_tx_ready[511] || !node_active[31]) $fatal(1, "Per-slice isolation affected card/node state"); // 检查slice故障不扩散到整卡或node
        if (protocol_error != 16'd0) $fatal(1, "Leaf profile control introduced fabric protocol errors"); // 检查目录操作未污染交换协议状态
        $display("TB_KDLINK_CARD_PROFILES_PASS profiles=6 mixed_cards=10 nodes=32 slices=512 card_isolation=1 plane_isolation=1 slice_isolation=1"); // 报告叶域板卡规格集成测试通过
        $finish; // 正常结束板卡规格系统测试
    end // 结束叶域板卡规格测试主过程

    initial begin // 建立叶域板卡规格测试看门狗
        #30000; // 等待远超全部配置事务的时间
        $fatal(1, "KDLink card profile system timeout"); // 超时表示目录或fabric未能推进
    end // 结束系统测试看门狗
endmodule // 结束tb_kdlink_card_profiles测试模块
