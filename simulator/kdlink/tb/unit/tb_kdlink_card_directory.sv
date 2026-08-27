`timescale 1ns/1ps // 定义板卡目录单元测试时间尺度
module tb_kdlink_card_directory; // 定义可配置板卡目录自检测试
    logic clk; // 产生目录控制时钟
    logic rst_n; // 驱动低有效异步复位
    logic prepare; // 驱动shadow目录prepare
    logic [15:0] prepare_epoch; // 驱动shadow目标epoch
    logic entry_valid; // 驱动卡槽描述符有效
    wire entry_ready; // 观察描述符接收就绪
    logic [4:0] entry_slot; // 驱动卡槽编号
    logic [4:0] entry_base_node; // 驱动卡槽首node编号
    logic [2:0] entry_npu_count_code; // 驱动每卡NPU规格码
    wire entry_reject; // 观察非法描述符拒绝
    logic commit; // 驱动目录提交请求
    logic quiescent; // 驱动叶域静默状态
    wire commit_accept; // 观察目录提交成功
    wire commit_reject; // 观察目录提交拒绝
    logic [31:0] card_present; // 驱动三十二卡槽在位状态
    logic [31:0] card_reset_done; // 驱动三十二卡槽复位完成状态
    logic [4:0] query_node; // 驱动node查询索引
    wire query_mapped; // 观察node映射状态
    wire [4:0] query_slot; // 观察node所属卡槽
    wire [4:0] query_local_npu; // 观察node卡内编号
    wire [2:0] query_npu_count_code; // 观察node所属卡规格
    wire query_active; // 观察node卡级可用状态
    wire [31:0] configured_node_mask; // 观察活动node掩码
    wire [31:0] node_active; // 观察全部node可用状态
    wire [31:0] configured_slot_mask; // 观察活动卡槽掩码
    wire [15:0] active_epoch; // 观察活动目录epoch
    wire shadow_error; // 观察shadow粘滞错误
    integer profile_code; // 遍历六种每卡NPU规格
    integer profile_count; // 保存当前规格每卡NPU数量
    integer profile_slots; // 保存当前规格卡槽数量
    integer slot_index; // 遍历当前配置卡槽
    integer node_index; // 遍历全部三十二node
    integer expected_slot; // 保存期望node所属卡槽
    integer expected_local; // 保存期望node卡内编号
    logic [31:0] expected_slot_mask; // 保存当前统一布局期望卡槽掩码
    integer mixed_count [0:9]; // 保存混插布局每槽NPU数量
    integer mixed_base [0:9]; // 保存混插布局每槽首node

    kdlink_card_directory u_dut ( // 实例化待测可综合板卡目录
        .clk_i(clk), .rst_n_i(rst_n), .prepare_i(prepare), .prepare_epoch_i(prepare_epoch), // 连接时钟复位和prepare接口
        .entry_valid_i(entry_valid), .entry_ready_o(entry_ready), .entry_slot_i(entry_slot), // 连接描述符握手和卡槽编号
        .entry_base_node_i(entry_base_node), .entry_npu_count_code_i(entry_npu_count_code), .entry_reject_o(entry_reject), // 连接描述符范围规格和拒绝状态
        .commit_i(commit), .quiescent_i(quiescent), .commit_accept_o(commit_accept), .commit_reject_o(commit_reject), // 连接原子提交控制
        .card_present_i(card_present), .card_reset_done_i(card_reset_done), .query_node_i(query_node), // 连接卡槽动态状态和node查询
        .query_mapped_o(query_mapped), .query_slot_o(query_slot), .query_local_npu_o(query_local_npu), // 观察查询映射结果
        .query_npu_count_code_o(query_npu_count_code), .query_active_o(query_active), // 观察查询规格和可用状态
        .configured_node_mask_o(configured_node_mask), .node_active_o(node_active), // 观察node分配和可用掩码
        .configured_slot_mask_o(configured_slot_mask), .active_epoch_o(active_epoch), .shadow_error_o(shadow_error) // 观察卡槽掩码epoch和错误
    ); // 结束板卡目录实例

    always #0.5 clk = ~clk; // 产生一GHz逻辑测试时钟

    task automatic start_prepare(input integer epoch_value); // 定义清空shadow并开始配置的辅助过程
        begin // 开始prepare辅助过程
            @(negedge clk); prepare = 1'b1; prepare_epoch = epoch_value[15:0]; // 在下降沿驱动prepare和目标epoch
            @(negedge clk); prepare = 1'b0; // 在下一下降沿撤销prepare
            if (!entry_ready || shadow_error) $fatal(1, "Card directory did not enter clean prepared state"); // 检查shadow事务已经就绪
        end // 结束prepare辅助过程主体
    endtask // 结束start_prepare辅助过程

    task automatic write_entry( // 定义写入一个卡槽描述符的辅助过程
        input integer slot_value, // 接收卡槽编号
        input integer base_value, // 接收首node编号
        input integer code_value // 接收NPU规格码
    ); // 结束write_entry端口声明
        begin // 开始描述符写入过程
            @(negedge clk); entry_valid = 1'b1; entry_slot = slot_value[4:0]; entry_base_node = base_value[4:0]; entry_npu_count_code = code_value[2:0]; // 驱动完整描述符
            @(negedge clk); entry_valid = 1'b0; // 在描述符采样后撤销valid
            @(negedge clk); // 等待一级描述符校验流水提交接受或拒绝结果
        end // 结束描述符写入主体
    endtask // 结束write_entry辅助过程

    task automatic request_commit(input logic quiet_value); // 定义请求原子提交的辅助过程
        begin // 开始提交辅助过程
            @(negedge clk); quiescent = quiet_value; commit = 1'b1; // 驱动静默条件和commit脉冲
            @(negedge clk); commit = 1'b0; // 在提交采样后撤销commit
        end // 结束提交辅助过程主体
    endtask // 结束request_commit辅助过程

    task automatic configure_irregular_leaf( // 定义配置任意一至三十二NPU部分叶域的辅助过程
        input integer total_count, // 接收当前叶域有效NPU总数
        input integer epoch_value // 接收当前部分叶域拓扑代次
    ); // 结束configure_irregular_leaf端口声明
        integer remaining_count; // 保存尚未分配的NPU数量
        integer base_value; // 保存下一张卡的连续首node
        integer card_count; // 保存当前卡支持的二次幂NPU数量
        integer card_code; // 保存当前卡NPU规格码
        integer card_slot; // 保存紧凑分配卡槽编号
        logic [31:0] expected_node_mask; // 保存部分叶域期望有效node掩码
        begin // 开始紧凑部分叶域配置
            start_prepare(epoch_value); // 清空shadow并开始新的部分叶域配置
            remaining_count = total_count; base_value = 0; card_slot = 0; // 从node零开始连续紧凑分配
            while (remaining_count > 0) begin // 按十六八四二一的贪心顺序拆分任意数量
                if (remaining_count >= 16) begin card_count = 16; card_code = 4; end // 优先选择十六NPU卡
                else if (remaining_count >= 8) begin card_count = 8; card_code = 3; end // 其次选择八NPU卡
                else if (remaining_count >= 4) begin card_count = 4; card_code = 2; end // 其次选择四NPU卡
                else if (remaining_count >= 2) begin card_count = 2; card_code = 1; end // 其次选择双NPU卡
                else begin card_count = 1; card_code = 0; end // 最后选择单NPU卡
                write_entry(card_slot, base_value, card_code); // 写入当前连续且不重叠的卡描述符
                base_value = base_value + card_count; remaining_count = remaining_count - card_count; card_slot = card_slot + 1; // 推进紧凑布局游标
            end // 结束当前数量的二进制拆分
            request_commit(1'b1); // 在叶域静默条件下原子提交部分人口布局
            if (total_count == 32) expected_node_mask = 32'hffffffff; // 避免三十二位左移边界溢出
            else expected_node_mask = (32'h00000001 << total_count) - 32'h00000001; // 生成从node零开始的连续有效掩码
            if (!commit_accept || commit_reject || configured_node_mask != expected_node_mask) $fatal(1, "Irregular leaf commit failed total=%0d", total_count); // 检查提交状态和精确有效掩码
            for (node_index = 0; node_index < 32; node_index = node_index + 1) begin // 穷举部分叶域全部逻辑node
                query_node = node_index[4:0]; #0.01; // 查询当前逻辑node映射和活动状态
                if (query_mapped != (node_index < total_count) || query_active != (node_index < total_count)) $fatal(1, "Irregular leaf membership mismatch total=%0d node=%0d", total_count, node_index); // 要求只有请求数量内的node参与
            end // 结束部分叶域全部node检查
        end // 结束紧凑部分叶域配置
    endtask // 结束configure_irregular_leaf辅助过程

    initial begin // 执行全部目录映射和错误恢复测试
        clk = 1'b0; rst_n = 1'b0; prepare = 1'b0; prepare_epoch = 16'd0; // 初始化时钟复位和prepare接口
        entry_valid = 1'b0; entry_slot = 5'd0; entry_base_node = 5'd0; entry_npu_count_code = 3'd0; // 初始化描述符接口
        commit = 1'b0; quiescent = 1'b1; card_present = 32'hffffffff; card_reset_done = 32'hffffffff; query_node = 5'd0; // 初始化提交卡状态和查询接口
        mixed_count[0] = 8; mixed_count[1] = 8; mixed_count[2] = 4; mixed_count[3] = 4; mixed_count[4] = 2; // 定义混插布局前五张卡
        mixed_count[5] = 2; mixed_count[6] = 1; mixed_count[7] = 1; mixed_count[8] = 1; mixed_count[9] = 1; // 定义混插布局后五张卡
        mixed_base[0] = 0; mixed_base[1] = 8; mixed_base[2] = 16; mixed_base[3] = 20; mixed_base[4] = 24; // 定义混插布局前五个首node
        mixed_base[5] = 26; mixed_base[6] = 28; mixed_base[7] = 29; mixed_base[8] = 30; mixed_base[9] = 31; // 定义混插布局后五个首node
        repeat (4) @(posedge clk); // 保持复位覆盖多个时钟边沿
        @(negedge clk); rst_n = 1'b1; // 在下降沿释放复位
        #0.01; // 等待组合查询稳定
        if (configured_node_mask != 32'hffffffff || configured_slot_mask != 32'h000000ff || active_epoch != 16'd0) $fatal(1, "Legacy 8x4 reset layout mismatch"); // 检查默认八卡四NPU布局
        for (node_index = 0; node_index < 32; node_index = node_index + 1) begin // 穷举默认布局全部node
            query_node = node_index[4:0]; expected_slot = node_index >> 2; expected_local = node_index & 3; #0.01; // 查询当前默认node并计算期望映射
            if (!query_mapped || query_slot != expected_slot[4:0] || query_local_npu != expected_local[4:0] || query_npu_count_code != 3'd2 || !query_active) $fatal(1, "Legacy mapping mismatch node=%0d", node_index); // 检查默认映射完全兼容
        end // 结束默认布局穷举
        for (profile_code = 0; profile_code < 6; profile_code = profile_code + 1) begin // 遍历一二四八十六和三十二NPU规格
            profile_count = 1 << profile_code; profile_slots = 32 >> profile_code; // 计算当前规格卡内NPU数和卡槽数
            start_prepare(profile_code + 1); // 为当前规格开始新的shadow配置
            for (slot_index = 0; slot_index < profile_slots; slot_index = slot_index + 1) begin // 写入当前统一布局全部卡槽
                write_entry(slot_index, slot_index * profile_count, profile_code); // 配置连续无重叠node范围
                if (entry_reject || shadow_error) $fatal(1, "Valid homogeneous descriptor rejected profile=%0d slot=%0d", profile_code, slot_index); // 检查合法描述符未被拒绝
            end // 结束当前统一布局卡槽写入
            request_commit(1'b1); // 在叶域静默时原子提交布局
            if (!commit_accept || commit_reject || active_epoch != (profile_code[15:0] + 16'd1)) $fatal(1, "Homogeneous commit failed profile=%0d", profile_code); // 检查目录提交和epoch
            if (profile_slots == 32) expected_slot_mask = 32'hffffffff; else expected_slot_mask = (32'h00000001 << profile_slots) - 32'h00000001; // 生成不发生三十二位移位溢出的卡槽掩码
            if (configured_node_mask != 32'hffffffff || configured_slot_mask != expected_slot_mask) $fatal(1, "Homogeneous masks mismatch profile=%0d", profile_code); // 检查全部node和期望卡槽掩码
            for (node_index = 0; node_index < 32; node_index = node_index + 1) begin // 穷举当前统一布局全部node
                query_node = node_index[4:0]; expected_slot = node_index >> profile_code; expected_local = node_index & (profile_count - 1); #0.01; // 计算并查询期望映射
                if (!query_mapped || query_slot != expected_slot[4:0] || query_local_npu != expected_local[4:0] || query_npu_count_code != profile_code[2:0]) $fatal(1, "Homogeneous query mismatch profile=%0d node=%0d", profile_code, node_index); // 检查node到卡槽双射
            end // 结束当前统一布局node穷举
            card_present[profile_slots-1] = 1'b0; #0.01; // 拔出当前布局最后一张卡
            for (node_index = 0; node_index < 32; node_index = node_index + 1) begin // 检查拔卡故障隔离范围
                if (node_active[node_index] != (node_index < (32 - profile_count))) $fatal(1, "Card isolation mismatch profile=%0d node=%0d", profile_code, node_index); // 仅最后一张卡拥有的node必须失活
            end // 结束拔卡隔离检查
            card_present[profile_slots-1] = 1'b1; #0.01; // 恢复最后一张卡在位状态
        end // 结束六种统一布局遍历
        start_prepare(16); // 开始混插布局shadow配置
        for (slot_index = 0; slot_index < 10; slot_index = slot_index + 1) begin // 写入十张混合规格板卡
            case (mixed_count[slot_index]) // 将混插NPU数量转换为规格码
                1: profile_code = 0; // 单NPU卡使用规格零
                2: profile_code = 1; // 双NPU卡使用规格一
                4: profile_code = 2; // 四NPU卡使用规格二
                8: profile_code = 3; // 八NPU卡使用规格三
                default: profile_code = 7; // 将非预期测试数据转为非法码
            endcase // 结束混插规格码转换
            write_entry(slot_index, mixed_base[slot_index], profile_code); // 写入当前混插卡描述符
        end // 结束混插卡槽写入
        request_commit(1'b1); // 提交覆盖全部三十二node的混插布局
        if (!commit_accept || configured_slot_mask != 32'h000003ff || configured_node_mask != 32'hffffffff) $fatal(1, "Mixed layout commit failed"); // 检查混插布局完整生效
        for (node_index = 0; node_index < 32; node_index = node_index + 1) begin // 穷举混插布局全部node
            query_node = node_index[4:0]; #0.01; // 查询当前混插node
            if (!query_mapped || {1'b0, query_local_npu} >= (6'd1 << query_npu_count_code)) $fatal(1, "Mixed layout local NPU mismatch node=%0d", node_index); // 检查每个node映射到合法卡内编号
        end // 结束混插布局node穷举
        start_prepare(17); // 开始验证非quiescent提交保护
        write_entry(0, 0, 5); // 准备单卡三十二NPU合法布局
        request_commit(1'b0); // 在叶域非静默时请求提交
        if (!commit_reject || active_epoch != 16'd16) $fatal(1, "Non-quiescent commit was not rejected"); // 检查旧目录和epoch保持不变
        request_commit(1'b1); // 在叶域静默后重试同一shadow提交
        if (!commit_accept || active_epoch != 16'd17) $fatal(1, "Quiescent retry commit failed"); // 检查合法重试成功
        start_prepare(18); // 开始非法重叠配置测试
        write_entry(0, 0, 3); // 写入首张八NPU卡
        write_entry(1, 7, 3); // 写入与首张卡重叠的八NPU卡
        if (!entry_reject || !shadow_error) $fatal(1, "Overlapping card range was not rejected"); // 检查重叠错误粘滞
        request_commit(1'b1); // 尝试提交已污染shadow目录
        if (!commit_reject || active_epoch != 16'd17) $fatal(1, "Invalid shadow directory replaced active state"); // 检查非法目录不能生效
        start_prepare(17); // 准备与活动epoch相同的陈旧配置
        write_entry(0, 0, 5); // 写入合法单卡布局以隔离epoch错误
        request_commit(1'b1); // 请求提交陈旧epoch
        if (!commit_reject || active_epoch != 16'd17) $fatal(1, "Stale topology epoch was accepted"); // 检查相同epoch被拒绝
        start_prepare(18); // 准备非法保留规格码测试
        write_entry(0, 0, 6); // 写入保留规格码六
        if (!entry_reject || !shadow_error) $fatal(1, "Reserved NPU count code was accepted"); // 检查保留规格码拒绝
        @(negedge clk); prepare = 1'b1; prepare_epoch = 16'd18; commit = 1'b1; // 制造prepare与commit同周期控制冲突
        @(negedge clk); prepare = 1'b0; commit = 1'b0; // 撤销冲突控制信号
        if (!commit_reject || active_epoch != 16'd17 || !entry_ready) $fatal(1, "Prepare/commit collision changed active directory"); // 检查冲突只建立新shadow而不提交旧内容
        start_prepare(19); // 为entry与commit冲突建立干净shadow事务
        @(negedge clk); entry_valid = 1'b1; entry_slot = 5'd0; entry_base_node = 5'd0; entry_npu_count_code = 3'd5; commit = 1'b1; // 同周期写入完整卡描述符并请求提交
        @(negedge clk); entry_valid = 1'b0; commit = 1'b0; // 撤销描述符和提交信号
        if (!commit_reject || entry_reject || active_epoch != 16'd17) $fatal(1, "Entry/commit collision changed active directory"); // 检查描述符可写入但当周期提交被拒绝
        request_commit(1'b1); // 在独立控制周期提交已经写入的shadow目录
        if (!commit_accept || active_epoch != 16'd19 || configured_slot_mask != 32'h00000001) $fatal(1, "Collision recovery commit failed"); // 检查冲突恢复后单卡布局正常生效
        start_prepare(20); // 建立不含任何描述符的空shadow事务
        request_commit(1'b1); // 尝试提交空目录
        if (!commit_reject || active_epoch != 16'd19) $fatal(1, "Empty shadow directory was accepted"); // 检查空目录不能替换活动映射
        start_prepare(21); // 建立越界描述符错误事务
        write_entry(0, 31, 1); // 写入从node三十一开始的双NPU越界范围
        if (!entry_reject || !shadow_error) $fatal(1, "Out-of-range card descriptor was accepted"); // 检查越界范围被拒绝
        start_prepare(22); // 建立重复卡槽错误事务
        write_entry(31, 0, 0); // 为最高编号卡槽写入首个单NPU描述符
        write_entry(31, 1, 0); // 对同一卡槽写入第二个不重叠描述符
        if (!entry_reject || !shadow_error) $fatal(1, "Duplicate card slot was accepted"); // 检查重复卡槽被拒绝
        start_prepare(32'h00005555); // 建立高位epoch和三十二单NPU卡布局
        for (slot_index = 0; slot_index < 32; slot_index = slot_index + 1) begin // 写入覆盖全部物理卡槽的单NPU布局
            write_entry(slot_index, slot_index, 0); // 令每个卡槽拥有同编号node
        end // 结束最高卡槽覆盖配置
        request_commit(1'b1); // 提交三十二卡布局以翻转完整目录状态
        if (!commit_accept || active_epoch != 16'h5555 || configured_slot_mask != 32'hffffffff) $fatal(1, "High-epoch 32-card layout failed"); // 检查高位epoch和卡槽掩码
        card_present = 32'h00000000; card_reset_done = 32'h00000000; #0.01; // 同时关闭全部卡槽健康条件
        if (node_active != 32'h00000000) $fatal(1, "All-down card state leaked an active node"); // 检查全部node失活
        card_present = 32'haaaaaaaa; card_reset_done = 32'h55555555; #0.01; // 交错驱动在位和复位状态
        if (node_active != 32'h00000000) $fatal(1, "Complementary card states leaked an active node"); // 检查健康条件必须同时满足
        card_present = 32'h55555555; card_reset_done = 32'h55555555; #0.01; // 激活偶数编号卡槽
        if (node_active != 32'h55555555) $fatal(1, "Alternating card state mapping mismatch"); // 检查每节点独立卡状态映射
        card_present = 32'hffffffff; card_reset_done = 32'hffffffff; #0.01; // 恢复全部卡槽健康状态
        start_prepare(32'h00007fff); // 建立最高正向半区附近的epoch事务
        write_entry(31, 0, 5); // 将全部node映射到最高编号三十二NPU卡
        request_commit(1'b1); // 提交高卡槽单卡布局
        if (!commit_accept || active_epoch != 16'h7fff || configured_slot_mask != 32'h80000000) $fatal(1, "High-slot full-card layout failed"); // 检查卡槽编号高位和epoch翻转
        start_prepare(32'h0000fffe); // 从七fff向前推进七fff验证epoch高位
        write_entry(31, 31, 0); // 只配置最高node形成部分人口布局
        request_commit(1'b1); // 提交合法部分人口目录
        if (!commit_accept || active_epoch != 16'hfffe || configured_node_mask != 32'h80000000) $fatal(1, "Partial-population layout failed"); // 检查仅最高node映射
        query_node = 5'd0; #0.01; // 查询未配置node
        if (query_mapped || query_active) $fatal(1, "Unmapped node became active"); // 检查目录空洞保持不可用
        query_node = 5'd31; #0.01; // 查询部分目录中唯一映射node
        if (!query_mapped || query_slot != 5'd31 || query_local_npu != 5'd0 || !query_active) $fatal(1, "Partial-population mapped node mismatch"); // 检查最高node完整映射
        configure_irregular_leaf(2, 32'h00000002); // 验证总规模二NPU可由单张双NPU卡组成
        configure_irregular_leaf(3, 32'h00000003); // 验证总规模三NPU可由二加一卡组成
        configure_irregular_leaf(1, 32'h00000004); // 验证三十三NPU系统的末叶仅有一个NPU
        configure_irregular_leaf(14, 32'h00000005); // 验证七十八NPU系统的末叶具有十四个NPU
        configure_irregular_leaf(28, 32'h00000006); // 验证一万五千一百三十二NPU系统的末叶具有二十八个NPU
        start_prepare(32'h00005555); // 通过模回绕建立新的全卡事务
        write_entry(0, 0, 5); // 恢复单卡三十二NPU完整布局
        request_commit(1'b1); // 提交回绕后的新epoch
        if (!commit_accept || active_epoch != 16'h5555 || configured_node_mask != 32'hffffffff) $fatal(1, "Wrapped epoch commit failed"); // 检查前向半区回绕规则
        $display("TB_KDLINK_CARD_DIRECTORY_PASS profiles=6 mixed_cards=10 nodes=32 atomic_commit=1 epoch_guard=1 card_isolation=1 control_collision=1 partial_population=1 irregular_counts=2,3,1,14,28"); // 报告板卡目录及不规则末叶测试通过
        $finish; // 正常结束目录单元测试
    end // 结束目录测试主过程

    initial begin // 建立目录测试看门狗
        #20000; // 等待远超全部定向用例的时间
        $fatal(1, "KDLink card directory timeout"); // 超时表示握手或状态机停滞
    end // 结束目录测试看门狗
endmodule // 结束tb_kdlink_card_directory测试模块
