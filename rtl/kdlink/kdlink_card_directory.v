module kdlink_card_directory #( // 定义三十二节点叶域的原子板卡目录
    parameter [2:0] DEFAULT_NPU_COUNT_CODE = 3'd2 // 选择复位后的每卡四NPU兼容布局
) ( // 开始板卡目录端口声明
    input wire clk_i, // 接收目录控制时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire prepare_i, // 清空shadow目录并开始新一轮配置
    input wire [15:0] prepare_epoch_i, // 接收待提交的拓扑epoch
    input wire entry_valid_i, // 指示一个卡槽描述符有效
    output wire entry_ready_o, // 指示shadow目录可接受描述符
    input wire [4:0] entry_slot_i, // 接收最多三十二个物理卡槽编号
    input wire [4:0] entry_base_node_i, // 接收该卡拥有的首个叶域node编号
    input wire [2:0] entry_npu_count_code_i, // 接收一二四八十六或三十二NPU规格码
    output wire entry_reject_o, // 指示当前描述符非法并污染shadow配置
    input wire commit_i, // 请求原子提交shadow目录
    input wire quiescent_i, // 指示叶域已经停止接收新的传输
    output wire commit_accept_o, // 指示新目录已经原子生效
    output wire commit_reject_o, // 指示提交条件不满足
    input wire [31:0] card_present_i, // 接收所有卡槽在位状态
    input wire [31:0] card_reset_done_i, // 接收所有卡槽复位完成状态
    input wire [4:0] query_node_i, // 接收待查询的叶域node编号
    output wire query_mapped_o, // 指示查询node已经分配给卡槽
    output wire [4:0] query_slot_o, // 输出查询node所属卡槽
    output wire [4:0] query_local_npu_o, // 输出查询node在卡内的NPU编号
    output wire [2:0] query_npu_count_code_o, // 输出查询node所属卡的规格码
    output wire query_active_o, // 指示查询node所属卡在位且复位完成
    output wire [31:0] configured_node_mask_o, // 输出当前已配置node掩码
    output wire [31:0] node_active_o, // 输出所有node的卡级可用状态
    output wire [31:0] configured_slot_mask_o, // 输出当前已配置卡槽掩码
    output wire [15:0] active_epoch_o, // 输出当前活动目录epoch
    output wire shadow_error_o // 指示shadow目录存在粘滞配置错误
); // 结束板卡目录端口声明
    reg [4:0] active_owner_slot_q [0:31]; // 保存每个活动node所属卡槽
    reg [4:0] active_local_npu_q [0:31]; // 保存每个活动node的卡内编号
    reg [2:0] active_npu_count_code_q [0:31]; // 保存每个活动node所属卡规格
    reg [31:0] active_node_valid_q; // 保存活动node分配掩码
    reg [31:0] active_slot_valid_q; // 保存活动卡槽分配掩码
    reg [15:0] active_epoch_q; // 保存活动目录拓扑epoch
    reg [4:0] shadow_owner_slot_q [0:31]; // 保存每个shadow node所属卡槽
    reg [4:0] shadow_local_npu_q [0:31]; // 保存每个shadow node的卡内编号
    reg [2:0] shadow_npu_count_code_q [0:31]; // 保存每个shadow node所属卡规格
    reg [31:0] shadow_node_valid_q; // 保存shadow node分配掩码
    reg [31:0] shadow_slot_valid_q; // 保存shadow卡槽分配掩码
    reg [15:0] shadow_epoch_q; // 保存shadow目录拓扑epoch
    reg shadow_prepared_q; // 标记shadow目录已经执行prepare
    reg shadow_error_q; // 保存shadow配置粘滞错误
    reg entry_reject_q; // 保存单周期描述符拒绝脉冲
    reg commit_accept_q; // 保存单周期提交成功脉冲
    reg commit_reject_q; // 保存单周期提交拒绝脉冲
    reg [5:0] entry_npu_count_d; // 解码当前描述符的NPU数量
    reg entry_profile_valid_d; // 标记当前NPU规格码合法
    reg [31:0] entry_node_mask_d; // 生成当前卡描述符占用的node掩码
    reg [6:0] entry_node_limit_d; // 保存当前卡范围的开区间上界
    reg entry_static_invalid_d; // 汇总当前描述符规格和范围静态非法条件
    reg entry_pending_q; // 标记一个已经握手的描述符正在校验流水中
    reg [4:0] pending_entry_slot_q; // 流水保存待校验卡槽编号
    reg [4:0] pending_entry_base_node_q; // 流水保存待校验首node编号
    reg [2:0] pending_entry_npu_count_code_q; // 流水保存待校验卡规格码
    reg [31:0] pending_entry_node_mask_q; // 流水保存待校验node范围掩码
    reg pending_entry_static_invalid_q; // 流水保存规格和范围静态非法状态
    integer mask_node_index; // 遍历组合范围掩码的三十二个node
    integer state_node_index; // 遍历时序目录中的三十二个node寄存器
    integer state_slot_index; // 遍历时序目录中的三十二个卡槽寄存器
    genvar active_node_index; // 展开活动node状态查询
    wire [15:0] epoch_delta; // 计算shadow相对活动epoch的模差值
    wire epoch_is_newer; // 标记shadow epoch处于合法前向半区
    wire pending_entry_invalid; // 汇总流水描述符与当前shadow状态的全部非法条件

    assign entry_ready_o = shadow_prepared_q && !shadow_error_q && !entry_pending_q; // 仅在干净shadow事务且校验流水空闲时接收描述符
    assign entry_reject_o = entry_reject_q; // 输出描述符拒绝脉冲
    assign commit_accept_o = commit_accept_q; // 输出目录提交成功脉冲
    assign commit_reject_o = commit_reject_q; // 输出目录提交拒绝脉冲
    assign query_mapped_o = active_node_valid_q[query_node_i]; // 直接索引查询node映射状态
    assign query_slot_o = active_owner_slot_q[query_node_i]; // 直接索引查询node所属卡槽
    assign query_local_npu_o = active_local_npu_q[query_node_i]; // 直接索引查询node卡内编号
    assign query_npu_count_code_o = active_npu_count_code_q[query_node_i]; // 直接索引查询node卡规格
    assign query_active_o = query_mapped_o && card_present_i[query_slot_o] && card_reset_done_i[query_slot_o]; // 合并映射在位和复位状态
    assign configured_node_mask_o = active_node_valid_q; // 输出活动node分配掩码
    assign configured_slot_mask_o = active_slot_valid_q; // 输出活动卡槽分配掩码
    assign active_epoch_o = active_epoch_q; // 输出活动目录epoch
    assign shadow_error_o = shadow_error_q; // 输出shadow配置粘滞错误
    assign epoch_delta = shadow_epoch_q - active_epoch_q; // 使用十六位模减法处理epoch回绕
    assign epoch_is_newer = (epoch_delta != 16'd0) && !epoch_delta[15]; // 接受非零且位于前向半区的epoch
    assign pending_entry_invalid = pending_entry_static_invalid_q || shadow_slot_valid_q[pending_entry_slot_q] || (|(pending_entry_node_mask_q & shadow_node_valid_q)); // 在流水边界后检查重复卡槽和node范围重叠

    always @(*) begin // 解码描述符并形成不重叠node写掩码
        entry_npu_count_d = 6'd0; // 默认非法规格不占用node
        entry_profile_valid_d = 1'b1; // 默认规格码合法后由case覆盖非法值
        case (entry_npu_count_code_i) // 解码每卡NPU数量规格
            3'd0: entry_npu_count_d = 6'd1; // 规格零表示单NPU卡
            3'd1: entry_npu_count_d = 6'd2; // 规格一表示双NPU卡
            3'd2: entry_npu_count_d = 6'd4; // 规格二表示四NPU卡
            3'd3: entry_npu_count_d = 6'd8; // 规格三表示八NPU卡
            3'd4: entry_npu_count_d = 6'd16; // 规格四表示十六NPU卡
            3'd5: entry_npu_count_d = 6'd32; // 规格五表示三十二NPU卡
            default: begin entry_npu_count_d = 6'd0; entry_profile_valid_d = 1'b0; end // 拒绝保留规格码六和七
        endcase // 结束NPU规格解码
        entry_node_limit_d = {2'b00, entry_base_node_i} + {1'b0, entry_npu_count_d}; // 计算七位范围上界避免加法溢出
        entry_node_mask_d = 32'd0; // 默认不选择任何node
        for (mask_node_index = 0; mask_node_index < 32; mask_node_index = mask_node_index + 1) begin // 遍历全部node生成范围掩码
            if (entry_profile_valid_d && (mask_node_index >= entry_base_node_i) && (mask_node_index < entry_node_limit_d)) begin // 选择描述符覆盖范围
                entry_node_mask_d[mask_node_index] = 1'b1; // 标记该node将写入shadow目录
            end else begin // 处理范围之外或非法规格
                entry_node_mask_d[mask_node_index] = 1'b0; // 保持该node未被当前描述符选择
            end // 结束当前node范围判定
        end // 结束全部node范围掩码生成
        entry_static_invalid_d = !entry_profile_valid_d; // 首先拒绝非法规格码
        if (entry_node_limit_d > 7'd32) entry_static_invalid_d = 1'b1; // 拒绝超出三十二node边界的卡范围
    end // 结束描述符合法性组合逻辑

    generate // 展开三十二个node卡级状态输出
        for (active_node_index = 0; active_node_index < 32; active_node_index = active_node_index + 1) begin : gen_node_active // 为每个node生成独立状态
            assign node_active_o[active_node_index] = active_node_valid_q[active_node_index] && card_present_i[active_owner_slot_q[active_node_index]] && card_reset_done_i[active_owner_slot_q[active_node_index]]; // 仅映射到健康卡槽的node可用
        end // 结束单个node状态生成
    endgenerate // 结束全部node状态输出结构

    always @(posedge clk_i or negedge rst_n_i) begin // 更新活动和shadow目录全部状态
        if (!rst_n_i) begin // 异步复位建立八卡四NPU兼容布局
            active_node_valid_q <= 32'hffffffff; // 默认全部三十二node完成映射
            active_slot_valid_q <= 32'd0; // 先清空活动卡槽掩码
            active_epoch_q <= 16'd0; // 默认拓扑epoch从零开始
            shadow_node_valid_q <= 32'd0; // 清空shadow node掩码
            shadow_slot_valid_q <= 32'd0; // 清空shadow卡槽掩码
            shadow_epoch_q <= 16'd0; // 清空shadow epoch
            shadow_prepared_q <= 1'b0; // 标记尚未开始shadow事务
            shadow_error_q <= 1'b0; // 清除shadow错误
            entry_pending_q <= 1'b0; // 清除描述符校验流水
            pending_entry_slot_q <= 5'd0; // 清零流水卡槽编号
            pending_entry_base_node_q <= 5'd0; // 清零流水首node编号
            pending_entry_npu_count_code_q <= 3'd0; // 清零流水卡规格码
            pending_entry_node_mask_q <= 32'd0; // 清零流水node范围掩码
            pending_entry_static_invalid_q <= 1'b0; // 清除流水静态非法状态
            entry_reject_q <= 1'b0; // 清除描述符拒绝脉冲
            commit_accept_q <= 1'b0; // 清除提交成功脉冲
            commit_reject_q <= 1'b0; // 清除提交拒绝脉冲
            for (state_node_index = 0; state_node_index < 32; state_node_index = state_node_index + 1) begin // 初始化全部node默认映射
                active_owner_slot_q[state_node_index] <= state_node_index[4:0] >> DEFAULT_NPU_COUNT_CODE; // 按默认规格计算所属卡槽
                active_local_npu_q[state_node_index] <= state_node_index[4:0] & ((5'b00001 << DEFAULT_NPU_COUNT_CODE) - 5'b00001); // 按默认规格计算卡内编号
                active_npu_count_code_q[state_node_index] <= DEFAULT_NPU_COUNT_CODE; // 为每个node记录默认卡规格
                shadow_owner_slot_q[state_node_index] <= 5'd0; // 清空shadow所属卡槽
                shadow_local_npu_q[state_node_index] <= 5'd0; // 清空shadow卡内编号
                shadow_npu_count_code_q[state_node_index] <= 3'd0; // 清空shadow卡规格
            end // 结束默认node映射初始化
            for (state_slot_index = 0; state_slot_index < 32; state_slot_index = state_slot_index + 1) begin // 初始化默认活动卡槽掩码
                if (state_slot_index < (32 >> DEFAULT_NPU_COUNT_CODE)) begin // 标记默认布局使用的卡槽
                    active_slot_valid_q[state_slot_index] <= 1'b1; // 使能默认布局卡槽
                end else begin // 处理默认布局未使用的卡槽
                    active_slot_valid_q[state_slot_index] <= 1'b0; // 禁用未使用卡槽
                end // 结束默认卡槽判定
            end // 结束默认卡槽掩码初始化
        end else begin // 正常运行处理prepare entry和commit
            entry_reject_q <= 1'b0; // 默认撤销描述符拒绝脉冲
            commit_accept_q <= 1'b0; // 默认撤销提交成功脉冲
            commit_reject_q <= 1'b0; // 默认撤销提交拒绝脉冲
            entry_pending_q <= 1'b0; // 默认当前校验流水处理后返回空闲
            if (prepare_i) begin // prepare拥有最高配置优先级
                shadow_node_valid_q <= 32'd0; // 清空上一轮shadow node映射
                shadow_slot_valid_q <= 32'd0; // 清空上一轮shadow卡槽映射
                shadow_epoch_q <= prepare_epoch_i; // 锁存新配置目标epoch
                shadow_prepared_q <= 1'b1; // 开启shadow描述符接收窗口
                shadow_error_q <= 1'b0; // 新prepare清除旧配置错误
                for (state_node_index = 0; state_node_index < 32; state_node_index = state_node_index + 1) begin // 清空shadow node元数据
                    shadow_owner_slot_q[state_node_index] <= 5'd0; // 清空shadow所属卡槽
                    shadow_local_npu_q[state_node_index] <= 5'd0; // 清空shadow卡内编号
                    shadow_npu_count_code_q[state_node_index] <= 3'd0; // 清空shadow卡规格
                end // 结束shadow node元数据清空
                entry_pending_q <= 1'b0; // 新prepare丢弃任何尚未处理的旧shadow描述符
            end else if (entry_pending_q) begin // 处理上一周期已经握手的shadow卡槽描述符
                if (pending_entry_invalid) begin // 处理非法重叠越界或重复描述符
                    shadow_error_q <= 1'b1; // 粘滞错误阻止当前shadow提交
                    entry_reject_q <= 1'b1; // 报告当前描述符被拒绝
                end else begin // 处理合法卡槽描述符
                    shadow_slot_valid_q[pending_entry_slot_q] <= 1'b1; // 标记shadow卡槽已经配置
                    for (state_node_index = 0; state_node_index < 32; state_node_index = state_node_index + 1) begin // 展开该卡拥有的全部node
                        if (pending_entry_node_mask_q[state_node_index]) begin // 仅写流水卡范围内node
                            shadow_node_valid_q[state_node_index] <= 1'b1; // 标记shadow node已经映射
                            shadow_owner_slot_q[state_node_index] <= pending_entry_slot_q; // 记录node所属物理卡槽
                            shadow_local_npu_q[state_node_index] <= state_node_index[4:0] - pending_entry_base_node_q; // 记录node的卡内NPU编号
                            shadow_npu_count_code_q[state_node_index] <= pending_entry_npu_count_code_q; // 记录node所属卡规格
                        end // 结束当前node写入条件
                    end // 结束当前卡node范围展开
                end // 结束描述符合法性分支
            end // 结束shadow描述符接收
            if (entry_valid_i && entry_ready_o && !prepare_i) begin // 捕获一个描述符到独立校验流水
                entry_pending_q <= 1'b1; // 标记下周期校验当前描述符
                pending_entry_slot_q <= entry_slot_i; // 流水保存卡槽编号
                pending_entry_base_node_q <= entry_base_node_i; // 流水保存首node编号
                pending_entry_npu_count_code_q <= entry_npu_count_code_i; // 流水保存卡规格码
                pending_entry_node_mask_q <= entry_node_mask_d; // 在范围生成后建立时序边界
                pending_entry_static_invalid_q <= entry_static_invalid_d; // 流水保存静态非法条件
            end // 结束描述符流水捕获
            if (commit_i) begin // 独立处理目录提交请求
                if (prepare_i || entry_valid_i || entry_pending_q) begin // 禁止配置写入、待校验描述符与提交同周期以免提交旧shadow快照
                    commit_reject_q <= 1'b1; // 报告控制阶段冲突并保持活动目录不变
                end else if (shadow_prepared_q && !shadow_error_q && (shadow_node_valid_q != 32'd0) && epoch_is_newer && quiescent_i) begin // 检查原子提交全部条件
                    active_node_valid_q <= shadow_node_valid_q; // 原子替换活动node掩码
                    active_slot_valid_q <= shadow_slot_valid_q; // 原子替换活动卡槽掩码
                    active_epoch_q <= shadow_epoch_q; // 提交新的拓扑epoch
                    shadow_prepared_q <= 1'b0; // 关闭已提交shadow事务
                    commit_accept_q <= 1'b1; // 报告目录提交成功
                    for (state_node_index = 0; state_node_index < 32; state_node_index = state_node_index + 1) begin // 复制全部shadow node元数据
                        active_owner_slot_q[state_node_index] <= shadow_owner_slot_q[state_node_index]; // 提交node所属卡槽
                        active_local_npu_q[state_node_index] <= shadow_local_npu_q[state_node_index]; // 提交node卡内编号
                        active_npu_count_code_q[state_node_index] <= shadow_npu_count_code_q[state_node_index]; // 提交node卡规格
                    end // 结束活动目录元数据复制
                end else begin // 处理未prepare错误空目录陈旧epoch或非quiescent
                    commit_reject_q <= 1'b1; // 报告提交条件不满足且保持旧目录
                end // 结束目录提交条件分支
            end // 结束目录提交请求处理
        end // 结束正常运行分支
    end // 结束板卡目录时序逻辑
endmodule // 结束kdlink_card_directory模块
