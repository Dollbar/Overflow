module formal_card_directory; // 定义板卡目录原子切换和隔离形式属性
    (* gclk *) reg clk; // 提供形式时序引擎全局时钟
    reg past_valid; // 标记形式轨迹已经越过初始周期
    reg [3:0] cycle_q; // 驱动确定性的prepare entry commit序列
    (* anyconst *) reg [4:0] query_node; // 任取三十二个叶域node之一
    (* anyconst *) reg [4:0] configured_slot; // 任取三十二个物理卡槽之一
    (* anyconst *) reg [31:0] card_present; // 任取全部卡槽在位状态
    (* anyconst *) reg [31:0] card_reset_done; // 任取全部卡槽复位完成状态
    wire rst_n; // 形成首周期低有效复位
    wire prepare; // 在固定周期清空shadow目录
    wire entry_valid; // 在固定周期写入单卡三十二NPU布局
    wire commit; // 连续请求一次拒绝和一次接受提交
    wire quiescent; // 仅在第二次commit允许原子切换
    wire entry_ready; // 观察shadow描述符ready
    wire entry_reject; // 观察描述符拒绝
    wire commit_accept; // 观察目录提交成功
    wire commit_reject; // 观察目录提交拒绝
    wire query_mapped; // 观察任意node映射状态
    wire [4:0] query_slot; // 观察任意node所属卡槽
    wire [4:0] query_local_npu; // 观察任意node卡内编号
    wire [2:0] query_npu_count_code; // 观察任意node所属卡规格
    wire query_active; // 观察任意node卡级可用状态
    wire [31:0] configured_node_mask; // 观察活动node分配掩码
    wire [31:0] node_active; // 观察全部node卡级可用状态
    wire [31:0] configured_slot_mask; // 观察活动卡槽分配掩码
    wire [15:0] active_epoch; // 观察活动目录epoch
    wire shadow_error; // 观察shadow目录错误
    wire [4:0] legacy_slot; // 计算默认四NPU布局所属卡槽
    wire [4:0] legacy_local_npu; // 计算默认四NPU布局卡内编号
    wire legacy_active; // 计算默认布局任意node期望可用状态
    wire committed_active; // 计算提交后任意node期望可用状态

    initial begin // 初始化形式驱动轨迹状态
        past_valid = 1'b0; // 首周期保持DUT复位
        cycle_q = 4'd0; // 从prepare周期零开始
    end // 结束形式驱动初始化

    assign rst_n = past_valid; // 仅首个形式周期拉低复位
    assign prepare = cycle_q == 4'd0; // 周期零开始epoch一shadow事务
    assign entry_valid = cycle_q == 4'd1; // 周期一写入单卡三十二NPU描述符
    assign commit = (cycle_q == 4'd2) || (cycle_q == 4'd3); // 周期二和三连续请求提交
    assign quiescent = cycle_q == 4'd3; // 仅周期三满足叶域静默条件
    assign legacy_slot = query_node >> 2; // 默认四NPU布局按node高三位选择卡槽
    assign legacy_local_npu = query_node & 5'd3; // 默认四NPU布局按node低两位选择卡内编号
    assign legacy_active = card_present[legacy_slot] && card_reset_done[legacy_slot]; // 合并默认所属卡的动态健康状态
    assign committed_active = card_present[configured_slot] && card_reset_done[configured_slot]; // 合并提交后所属卡的动态健康状态

    kdlink_card_directory u_dut ( // 实例化待证明板卡目录
        .clk_i(clk), .rst_n_i(rst_n), .prepare_i(prepare), .prepare_epoch_i(16'd1), // 连接形式时钟复位和固定新epoch
        .entry_valid_i(entry_valid), .entry_ready_o(entry_ready), .entry_slot_i(configured_slot), // 写入任意卡槽编号
        .entry_base_node_i(5'd0), .entry_npu_count_code_i(3'd5), .entry_reject_o(entry_reject), // 配置覆盖全部node的三十二NPU卡
        .commit_i(commit), .quiescent_i(quiescent), .commit_accept_o(commit_accept), .commit_reject_o(commit_reject), // 连接连续拒绝和接受提交序列
        .card_present_i(card_present), .card_reset_done_i(card_reset_done), .query_node_i(query_node), // 连接任意卡状态和查询node
        .query_mapped_o(query_mapped), .query_slot_o(query_slot), .query_local_npu_o(query_local_npu), // 观察任意node映射结果
        .query_npu_count_code_o(query_npu_count_code), .query_active_o(query_active), // 观察任意node规格和健康状态
        .configured_node_mask_o(configured_node_mask), .node_active_o(node_active), // 观察完整node掩码
        .configured_slot_mask_o(configured_slot_mask), .active_epoch_o(active_epoch), .shadow_error_o(shadow_error) // 观察卡槽掩码epoch和错误
    ); // 结束板卡目录形式实例

    always @(posedge clk) begin // 推进形式序列并证明原子目录不变量
        past_valid <= 1'b1; // 首周期后永久释放DUT复位
        if (!past_valid) begin // 处理形式首周期
            cycle_q <= 4'd0; // 保持prepare序列从周期零开始
        end else begin // 处理有效形式轨迹
            cycle_q <= cycle_q + 4'd1; // 每周期推进确定性配置序列
            assert (!entry_reject && !shadow_error); // 合法完整卡描述符不得触发配置错误
            if (cycle_q <= 4'd3) begin // 在成功commit可见前证明旧目录保持不变
                assert (configured_node_mask == 32'hffffffff); // 默认布局必须映射全部三十二node
                assert (configured_slot_mask == 32'h000000ff); // 默认布局必须保持八张四NPU卡
                assert (active_epoch == 16'd0); // 非静默提交不得提前改变活动epoch
                assert (query_mapped && (query_slot == legacy_slot)); // 任意node必须继续属于默认卡槽
                assert ((query_local_npu == legacy_local_npu) && (query_npu_count_code == 3'd2)); // 默认卡内编号和四NPU规格必须保持
                assert (query_active == legacy_active); // 默认node健康状态只能由所属卡决定
            end // 结束旧目录原子保持证明
            if (cycle_q == 4'd3) begin // 检查第一次非静默提交结果
                assert (commit_reject && !commit_accept); // 非静默提交必须被拒绝
            end // 结束非静默提交拒绝证明
            if (cycle_q >= 4'd4) begin // 在静默提交生效后证明新目录完整一致
                assert (commit_accept || (cycle_q > 4'd4)); // 成功脉冲必须在首个新目录周期出现
                assert (configured_node_mask == 32'hffffffff); // 单卡布局仍须映射全部node
                assert (configured_slot_mask == (32'h00000001 << configured_slot)); // 仅任意选中的卡槽必须被配置
                assert (active_epoch == 16'd1); // 静默提交必须原子推进epoch
                assert (query_mapped && (query_slot == configured_slot)); // 任意node必须映射到选中单卡
                assert ((query_local_npu == query_node) && (query_npu_count_code == 3'd5)); // 单卡三十二NPU布局卡内编号必须等于node
                assert (query_active == committed_active); // 新目录node健康状态只能由选中卡决定
                assert (node_active[query_node] == committed_active); // 向量状态和单node查询必须一致
            end // 结束新目录原子生效证明
        end // 结束有效形式轨迹分支
    end // 结束板卡目录形式断言
endmodule // 结束formal_card_directory模块
