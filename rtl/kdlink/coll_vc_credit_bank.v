module coll_vc_credit_bank #( // 定义四 VC credit 计数和累计恢复 bank
    parameter DEPTH = 64, // 配置每 VC RX FIFO 深度
    parameter STREAM_MODE = 1'b0 // 配置数据面是否采用静态窗口无反馈准入
) ( // 开始端口声明
    input  wire clk_i, // 接收 link core 时钟
    input  wire rst_n_i, // 接收低有效异步复位
    input  wire init_valid_i, // 指示当前 VC 初始化 credit 有效
    input  wire [1:0] init_vc_i, // 接收初始化目标 VC
    input  wire [6:0] init_credit_i, // 接收初始化 credit 数量
    input  wire send_valid_i, // 指示 forward flit 发送
    input  wire [1:0] send_vc_i, // 接收发送 flit 所属 VC
    input  wire return_valid_i, // 指示合法 reverse 累计 credit 更新
    input  wire [1:0] return_vc_i, // 接收 reverse word 所属 VC
    input  wire [15:0] return_total_i, // 接收远端累计释放槽位
    input  wire [4:0] reserve_flits0_i, // 接收 VC0 队首完整 packet flit 数
    input  wire [4:0] reserve_flits1_i, // 接收 VC1 队首完整 packet flit 数
    input  wire [4:0] reserve_flits2_i, // 接收 VC2 队首完整 packet flit 数
    input  wire [4:0] reserve_flits3_i, // 接收 VC3 队首完整 packet flit 数
    output wire [3:0] admit_o, // 指示每 VC credit 足以保留完整 packet
    output wire [27:0] credit_count_o, // 输出四个七位 credit 计数
    output reg underflow_o, // 指示 credit 为零仍发送
    output reg overflow_o, // 指示累计恢复后 credit 超过深度
    output reg stale_return_o // 指示重复或反向累计 credit 被忽略
); // 结束端口声明
    reg [6:0] credit_q [0:3]; // 保存每 VC 当前可用 credit
    reg [6:0] credit_d [0:3]; // 保存合并发送和累计恢复后的下一 credit
    reg init_valid_q; // 保存流水化 credit 初始化有效
    reg [3:0] init_select_q; // 保存流水化初始化目标 VC 独热选择
    reg [6:0] init_credit_q; // 保存流水化初始化 credit 数量
    reg send_valid_q; // 保存流水化发送 credit 扣减有效
    reg [3:0] send_select_q; // 保存流水化发送目标 VC 独热选择
    reg return_valid_q; // 保存累计 return 输入隔离级有效
    reg [1:0] return_vc_q; // 保存累计 return 输入隔离级 VC
    reg [15:0] return_total_q; // 保存累计 return 输入隔离级 total
    reg return_distance_valid_q; // 保存累计 return 差分流水有效
    reg [1:0] return_distance_vc_q; // 保存累计 return 差分流水 VC
    reg [15:0] return_distance_total_q; // 保存累计 return 差分流水 total
    reg [15:0] return_distance_baseline_q; // 保存累计 return 差分流水基线
    reg return_candidate_valid_q; // 保存累计 return 差分候选存在
    reg [1:0] return_candidate_vc_q; // 保存累计 return 差分候选 VC
    reg [15:0] return_candidate_distance_q; // 保存累计 return 候选完整差值
    reg [15:0] capture_total_q [0:3]; // 保存每 VC 最近接收的累计 total 前递基线
    reg [3:0] return_apply_q; // 指示每 VC 存在待应用累计差值
    reg [6:0] return_delta_q [0:3]; // 保存每 VC 已校验累计差值
    reg [6:0] return_delta_minus_one_q [0:3]; // 保存每 VC 累计差减一以合并同拍发送
    reg [7:0] recovered_credit_d [0:3]; // 保存应用累计差后的扩展 credit
    wire [15:0] selected_capture_total; // 选择当前隔离 return 对应前递基线
    wire [15:0] return_distance; // 计算当前累计 total 的模十六位前向距离
    wire candidate_distance_valid; // 指示候选累计距离非零且位于前向半空间
    wire candidate_distance_fits; // 指示候选累计距离不超过单 VC 最大在途槽位
    wire candidate_distance_accepted; // 指示候选累计距离位于一至六十四合法范围
    integer reset_vc_index; // 提供四 VC 时序复位和提交索引
    wire send_lane0; // 指示 VC0 发送扣减
    wire send_lane1; // 指示 VC1 发送扣减
    wire send_lane2; // 指示 VC2 发送扣减
    wire send_lane3; // 指示 VC3 发送扣减
    wire [6:0] applied_delta0; // 选择 VC0 恢复增量或发送抵消增量
    wire [6:0] applied_delta1; // 选择 VC1 恢复增量或发送抵消增量
    wire [6:0] applied_delta2; // 选择 VC2 恢复增量或发送抵消增量
    wire [6:0] applied_delta3; // 选择 VC3 恢复增量或发送抵消增量
    wire [6:0] visible_credit0; // 保存计入待提交发送后的 VC0 可见余额
    wire [6:0] visible_credit1; // 保存计入待提交发送后的 VC1 可见余额
    wire [6:0] visible_credit2; // 保存计入待提交发送后的 VC2 可见余额
    wire [6:0] visible_credit3; // 保存计入待提交发送后的 VC3 可见余额
    wire [7:0] recovered_sum0; // 保存 VC0 发送后累计恢复合计
    wire [7:0] recovered_sum1; // 保存 VC1 发送后累计恢复合计
    wire [7:0] recovered_sum2; // 保存 VC2 发送后累计恢复合计
    wire [7:0] recovered_sum3; // 保存 VC3 发送后累计恢复合计
    assign admit_o[0] = STREAM_MODE ? (reserve_flits0_i != 5'd0) : (({1'b0, credit_q[0]} >= ({3'd0, reserve_flits0_i} + {7'd0, send_valid_q && send_select_q[0]})) && reserve_flits0_i != 5'd0); // 流式模式只检查 packet 形态，反馈模式检查 credit
    assign admit_o[1] = STREAM_MODE ? (reserve_flits1_i != 5'd0) : (({1'b0, credit_q[1]} >= ({3'd0, reserve_flits1_i} + {7'd0, send_valid_q && send_select_q[1]})) && reserve_flits1_i != 5'd0); // 流式模式只检查 packet 形态，反馈模式检查 credit
    assign admit_o[2] = STREAM_MODE ? (reserve_flits2_i != 5'd0) : (({1'b0, credit_q[2]} >= ({3'd0, reserve_flits2_i} + {7'd0, send_valid_q && send_select_q[2]})) && reserve_flits2_i != 5'd0); // 流式模式只检查 packet 形态，反馈模式检查 credit
    assign admit_o[3] = STREAM_MODE ? (reserve_flits3_i != 5'd0) : (({1'b0, credit_q[3]} >= ({3'd0, reserve_flits3_i} + {7'd0, send_valid_q && send_select_q[3]})) && reserve_flits3_i != 5'd0); // 流式模式只检查 packet 形态，反馈模式检查 credit
    assign visible_credit0 = (!STREAM_MODE && send_lane0 && credit_q[0] != 7'd0) ? credit_q[0] - 7'd1 : credit_q[0]; // 形成 VC0 可见余额
    assign visible_credit1 = (!STREAM_MODE && send_lane1 && credit_q[1] != 7'd0) ? credit_q[1] - 7'd1 : credit_q[1]; // 形成 VC1 可见余额
    assign visible_credit2 = (!STREAM_MODE && send_lane2 && credit_q[2] != 7'd0) ? credit_q[2] - 7'd1 : credit_q[2]; // 形成 VC2 可见余额
    assign visible_credit3 = (!STREAM_MODE && send_lane3 && credit_q[3] != 7'd0) ? credit_q[3] - 7'd1 : credit_q[3]; // 形成 VC3 可见余额
    assign credit_count_o = {visible_credit3, visible_credit2, visible_credit1, visible_credit0}; // 展平输出四 VC 有效 credit
    assign selected_capture_total = (return_vc_q == 2'd0) ? capture_total_q[0] : (return_vc_q == 2'd1) ? capture_total_q[1] : (return_vc_q == 2'd2) ? capture_total_q[2] : capture_total_q[3]; // 选择累计差分前递基线
    assign return_distance = return_distance_total_q - return_distance_baseline_q; // 在独立流水级以模十六位减法支持累计计数环绕
    assign candidate_distance_valid = (return_candidate_distance_q != 16'd0) && !return_candidate_distance_q[15]; // 拒绝重复值和反向半空间旧值
    assign candidate_distance_fits = !(|return_candidate_distance_q[15:7]) && (!return_candidate_distance_q[6] || !(|return_candidate_distance_q[5:0])); // 以六十四深度常量简化累计距离上界判断
    assign candidate_distance_accepted = !(|return_candidate_distance_q[15:7]) && (return_candidate_distance_q[6] ^ (|return_candidate_distance_q[5:0])); // 合并非零和小于等于六十四判断
    assign send_lane0 = send_valid_q && send_select_q[0]; // 解码已流水化 VC0 发送事件
    assign send_lane1 = send_valid_q && send_select_q[1]; // 解码已流水化 VC1 发送事件
    assign send_lane2 = send_valid_q && send_select_q[2]; // 解码已流水化 VC2 发送事件
    assign send_lane3 = send_valid_q && send_select_q[3]; // 解码已流水化 VC3 发送事件
    assign applied_delta0 = (send_lane0 && credit_q[0] != 7'd0) ? return_delta_minus_one_q[0] : return_delta_q[0]; // 合并 VC0 同拍发送和恢复
    assign applied_delta1 = (send_lane1 && credit_q[1] != 7'd0) ? return_delta_minus_one_q[1] : return_delta_q[1]; // 合并 VC1 同拍发送和恢复
    assign applied_delta2 = (send_lane2 && credit_q[2] != 7'd0) ? return_delta_minus_one_q[2] : return_delta_q[2]; // 合并 VC2 同拍发送和恢复
    assign applied_delta3 = (send_lane3 && credit_q[3] != 7'd0) ? return_delta_minus_one_q[3] : return_delta_q[3]; // 合并 VC3 同拍发送和恢复
    assign recovered_sum0 = {1'b0, credit_q[0]} + {1'b0, applied_delta0}; // 计算 VC0 恢复后总额
    assign recovered_sum1 = {1'b0, credit_q[1]} + {1'b0, applied_delta1}; // 计算 VC1 恢复后总额
    assign recovered_sum2 = {1'b0, credit_q[2]} + {1'b0, applied_delta2}; // 计算 VC2 恢复后总额
    assign recovered_sum3 = {1'b0, credit_q[3]} + {1'b0, applied_delta3}; // 计算 VC3 恢复后总额
    always @(*) begin // 组合合并初始化 发送和已流水化 credit return
        credit_d[0] = credit_q[0]; // 默认保持 VC0 当前余额
        credit_d[1] = credit_q[1]; // 默认保持 VC1 当前余额
        credit_d[2] = credit_q[2]; // 默认保持 VC2 当前余额
        credit_d[3] = credit_q[3]; // 默认保持 VC3 当前余额
        recovered_credit_d[0] = recovered_sum0; // 保存 VC0 恢复合计用于错误检测
        recovered_credit_d[1] = recovered_sum1; // 保存 VC1 恢复合计用于错误检测
        recovered_credit_d[2] = recovered_sum2; // 保存 VC2 恢复合计用于错误检测
        recovered_credit_d[3] = recovered_sum3; // 保存 VC3 恢复合计用于错误检测
        if (init_select_q[0]) begin credit_d[0] = (init_credit_q > DEPTH) ? 7'd64 : init_credit_q; if (send_lane0 && credit_d[0] != 7'd0) credit_d[0] = credit_d[0] - 7'd1; end else if (return_apply_q[0] && recovered_sum0 <= DEPTH) credit_d[0] = recovered_sum0[6:0]; else if (send_lane0 && credit_q[0] != 7'd0) credit_d[0] = credit_q[0] - 7'd1; // 按优先级更新 VC0
        if (init_select_q[1]) begin credit_d[1] = (init_credit_q > DEPTH) ? 7'd64 : init_credit_q; if (send_lane1 && credit_d[1] != 7'd0) credit_d[1] = credit_d[1] - 7'd1; end else if (return_apply_q[1] && recovered_sum1 <= DEPTH) credit_d[1] = recovered_sum1[6:0]; else if (send_lane1 && credit_q[1] != 7'd0) credit_d[1] = credit_q[1] - 7'd1; // 按优先级更新 VC1
        if (init_select_q[2]) begin credit_d[2] = (init_credit_q > DEPTH) ? 7'd64 : init_credit_q; if (send_lane2 && credit_d[2] != 7'd0) credit_d[2] = credit_d[2] - 7'd1; end else if (return_apply_q[2] && recovered_sum2 <= DEPTH) credit_d[2] = recovered_sum2[6:0]; else if (send_lane2 && credit_q[2] != 7'd0) credit_d[2] = credit_q[2] - 7'd1; // 按优先级更新 VC2
        if (init_select_q[3]) begin credit_d[3] = (init_credit_q > DEPTH) ? 7'd64 : init_credit_q; if (send_lane3 && credit_d[3] != 7'd0) credit_d[3] = credit_d[3] - 7'd1; end else if (return_apply_q[3] && recovered_sum3 <= DEPTH) credit_d[3] = recovered_sum3[6:0]; else if (send_lane3 && credit_q[3] != 7'd0) credit_d[3] = credit_q[3] - 7'd1; // 按优先级更新 VC3
    end // 结束 credit 下一状态组合逻辑
    always @(posedge clk_i or negedge rst_n_i) begin // 更新 credit 和累计 return 接收流水
        if (!rst_n_i) begin // 检测复位有效
            underflow_o <= 1'b0; // 清除 underflow 脉冲
            overflow_o <= 1'b0; // 清除 overflow 脉冲
            stale_return_o <= 1'b0; // 清除 stale return 脉冲
            init_valid_q <= 1'b0; // 清除初始化流水有效
            init_select_q <= 4'd0; // 清零初始化独热选择
            init_credit_q <= 7'd0; // 清零初始化 credit
            send_valid_q <= 1'b0; // 清除发送扣减流水有效
            send_select_q <= 4'd0; // 清零发送扣减独热选择
            return_valid_q <= 1'b0; // 清除累计 return 输入隔离级
            return_vc_q <= 2'd0; // 清零累计 return VC
            return_total_q <= 16'd0; // 清零累计 return total
            return_distance_valid_q <= 1'b0; // 清除累计 return 差分流水有效
            return_distance_vc_q <= 2'd0; // 清零累计 return 差分流水 VC
            return_distance_total_q <= 16'd0; // 清零累计 return 差分流水 total
            return_distance_baseline_q <= 16'd0; // 清零累计 return 差分流水基线
            return_candidate_valid_q <= 1'b0; // 清除累计 return 差分候选
            return_candidate_vc_q <= 2'd0; // 清零累计 return 候选 VC
            return_candidate_distance_q <= 16'd0; // 清零累计 return 候选差值
            return_apply_q <= 4'd0; // 清除全部待应用累计差
            for (reset_vc_index = 0; reset_vc_index < 4; reset_vc_index = reset_vc_index + 1) begin // 复位四个 VC lane
                credit_q[reset_vc_index] <= 7'd0; // 清零当前 credit
                capture_total_q[reset_vc_index] <= 16'd0; // 清零累计 return 前递基线
                return_delta_q[reset_vc_index] <= 7'd0; // 清零待应用累计差
                return_delta_minus_one_q[reset_vc_index] <= 7'd0; // 清零待应用累计差减一
            end // 结束四 VC 复位
        end else begin // 处理正常 credit 流水
            underflow_o <= (send_lane0 && credit_q[0] == 7'd0) || (send_lane1 && credit_q[1] == 7'd0) || (send_lane2 && credit_q[2] == 7'd0) || (send_lane3 && credit_q[3] == 7'd0); // 已流水化发送遇零余额即报告 underflow
            overflow_o <= (return_apply_q[0] && recovered_credit_d[0] > DEPTH) || (return_apply_q[1] && recovered_credit_d[1] > DEPTH) || (return_apply_q[2] && recovered_credit_d[2] > DEPTH) || (return_apply_q[3] && recovered_credit_d[3] > DEPTH) || (return_candidate_valid_q && candidate_distance_valid && !candidate_distance_fits); // 汇总余额越界和非法过大累计跳变
            stale_return_o <= return_candidate_valid_q && !candidate_distance_valid; // 对重复或反向累计值生成错误脉冲
            init_valid_q <= init_valid_i; // 锁存初始化请求切断输入路径
            if (init_valid_i) init_select_q <= 4'b0001 << init_vc_i; else init_select_q <= 4'd0; // 将初始化目标预译码为独热选择
            init_credit_q <= init_credit_i; // 锁存初始化 credit
            if (STREAM_MODE) begin send_valid_q <= 1'b0; send_select_q <= 4'd0; end else begin send_valid_q <= send_valid_i; if (send_valid_i) send_select_q <= 4'b0001 << send_vc_i; else send_select_q <= 4'd0; end // 流式模式不把发送事件接入反馈 credit 路径
            if (STREAM_MODE) begin return_valid_q <= 1'b0; return_vc_q <= 2'd0; return_total_q <= 16'd0; end else begin return_valid_q <= return_valid_i; return_vc_q <= return_vc_i; return_total_q <= return_total_i; end // 流式模式只保留 reverse 旁路，不更新数据准入
            return_distance_valid_q <= return_valid_q; // 锁存累计 return 差分流水有效
            return_distance_vc_q <= return_vc_q; // 锁存累计 return 差分流水 VC
            return_distance_total_q <= return_total_q; // 锁存累计 return 差分流水 total
            return_distance_baseline_q <= selected_capture_total; // 锁存所选前递基线切断动态 VC 选择路径
            return_candidate_valid_q <= return_distance_valid_q; // 锁存累计 return 差分候选存在
            return_candidate_vc_q <= return_distance_vc_q; // 锁存候选 VC 供校验应用
            return_candidate_distance_q <= return_distance; // 锁存完整累计差切断十六位差分路径
            return_apply_q <= 4'd0; // 默认清除上一拍待应用标志
            for (reset_vc_index = 0; reset_vc_index < 4; reset_vc_index = reset_vc_index + 1) credit_q[reset_vc_index] <= credit_d[reset_vc_index]; // 同步提交四 VC 下一余额
            if (init_valid_q) begin // 应用流水化初始化对应累计基线
                if (init_select_q[0]) capture_total_q[0] <= {9'd0, init_credit_q}; // 初始化 VC0 累计基线
                else if (init_select_q[1]) capture_total_q[1] <= {9'd0, init_credit_q}; // 初始化 VC1 累计基线
                else if (init_select_q[2]) capture_total_q[2] <= {9'd0, init_credit_q}; // 初始化 VC2 累计基线
                else if (init_select_q[3]) capture_total_q[3] <= {9'd0, init_credit_q}; // 初始化 VC3 累计基线
            end // 结束累计基线初始化
            if (return_valid_q) begin // 前递每拍接收的累计 total 以维持同 VC return II 等于一
                case (return_vc_q) // 更新对应 VC 前递基线
                    2'd0: capture_total_q[0] <= return_total_q; // 前递 VC0 最新接收 total
                    2'd1: capture_total_q[1] <= return_total_q; // 前递 VC1 最新接收 total
                    2'd2: capture_total_q[2] <= return_total_q; // 前递 VC2 最新接收 total
                    default: capture_total_q[3] <= return_total_q; // 前递 VC3 最新接收 total
                endcase // 结束累计 total 前递选择
            end // 结束累计 total 前递
            if (return_candidate_valid_q && candidate_distance_accepted) begin // 应用前拍合法累计推进
                case (return_candidate_vc_q) // 将候选累计差值写入对应 VC 应用 lane
                    2'd0: begin return_apply_q[0] <= 1'b1; return_delta_q[0] <= return_candidate_distance_q[6:0]; return_delta_minus_one_q[0] <= return_candidate_distance_q[6:0] - 7'd1; end // 接受 VC0 累计推进
                    2'd1: begin return_apply_q[1] <= 1'b1; return_delta_q[1] <= return_candidate_distance_q[6:0]; return_delta_minus_one_q[1] <= return_candidate_distance_q[6:0] - 7'd1; end // 接受 VC1 累计推进
                    2'd2: begin return_apply_q[2] <= 1'b1; return_delta_q[2] <= return_candidate_distance_q[6:0]; return_delta_minus_one_q[2] <= return_candidate_distance_q[6:0] - 7'd1; end // 接受 VC2 累计推进
                    default: begin return_apply_q[3] <= 1'b1; return_delta_q[3] <= return_candidate_distance_q[6:0]; return_delta_minus_one_q[3] <= return_candidate_distance_q[6:0] - 7'd1; end // 接受 VC3 累计推进
                endcase // 结束累计 return VC 分发
            end // 结束合法累计推进处理
        end // 结束正常 credit 流水
    end // 结束 credit 状态时序逻辑
endmodule // 结束四 VC cumulative credit bank
