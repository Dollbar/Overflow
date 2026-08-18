module coll_vc_arbiter ( // 定义四 VC packet 边界优先和配额仲裁器
    input  wire clk_i, // 接收 link core 时钟
    input  wire rst_n_i, // 接收低有效异步复位
    input  wire [3:0] valid_i, // 接收四 VC 队首 flit 有效位
    input  wire [3:0] admit_i, // 接收四 VC 完整 packet credit 和资源准入位
    input  wire [639:0] flit0_i, // 接收 VC0 队首 logical flit
    input  wire [639:0] flit1_i, // 接收 VC1 队首 logical flit
    input  wire [639:0] flit2_i, // 接收 VC2 队首 logical flit
    input  wire [639:0] flit3_i, // 接收 VC3 队首 logical flit
    output wire [3:0] ready_o, // 返回被选 VC 的 flit 消费握手
    output wire valid_o, // 指示仲裁输出 flit 有效
    input  wire ready_i, // 接收 PHY/TX FIFO 接收能力
    output wire [639:0] flit_o, // 输出被选 logical flit
    output wire [1:0] vc_o // 输出当前被选 VC 编号
); // 结束端口声明
    reg packet_lock_q; // 保存 packet 内不可抢占锁定状态
    reg [1:0] selected_q; // 保存当前锁定 VC 编号
    reg data_rr_q; // 保存 VC0 和 VC1 下次轮询起点
    reg [2:0] high_quota_q; // 保存连续高优先 packet 服务数量零至四
    reg [1:0] candidate_d; // 保存组合选择的候选 VC
    reg candidate_valid_d; // 指示组合候选 VC 有效
    (* keep = "true" *) reg [19:0] select_valid_q; // 为二十个数据段物理保留选择流水级有效副本
    reg [639:0] select_flit0_q; // 保存选择级 VC0 flit 快照
    reg [639:0] select_flit1_q; // 保存选择级 VC1 flit 快照
    reg [639:0] select_flit2_q; // 保存选择级 VC2 flit 快照
    reg [639:0] select_flit3_q; // 保存选择级 VC3 flit 快照
    (* keep = "true" *) reg [1:0] select_vc_q [0:19]; // 为每个三十二位段物理保留选择寄存器副本
    (* keep = "true" *) reg [19:0] output_valid_q; // 为二十个数据段物理保留弹性输出级有效副本
    reg [639:0] output_flit_q; // 保存弹性输出级 logical flit
    reg [1:0] output_vc_q; // 保存弹性输出级 VC 编号
    wire [3:0] runnable; // 表示四 VC 同时满足有效和准入
    wire data_runnable; // 指示任一普通 data VC 可运行
    wire output_ready; // 指示弹性输出级可接收选择级 flit
    wire select_ready; // 指示选择流水级可接收新候选
    wire input_fire; // 指示候选 VC flit 装入选择级
    wire input_eop; // 指示当前候选 flit 为 packet 尾部
    integer segment_index; // 提供二十个三十二位数据段索引
    assign runnable = valid_i & admit_i; // 合并队首有效和 packet admission 条件
    assign data_runnable = runnable[0] || runnable[1]; // 汇总普通 data VC 可运行状态
    assign output_ready = !output_valid_q[0] || ready_i; // 以段零状态判断输出空闲或同拍消费
    assign select_ready = !select_valid_q[0] || output_ready; // 以段零状态判断选择级可装入
    assign input_fire = candidate_valid_d && select_ready; // 形成候选输入握手
    assign valid_o = output_valid_q[0]; // 输出段零寄存后的统一有效状态
    assign vc_o = output_vc_q; // 输出寄存后的 VC 编号
    assign flit_o = output_flit_q; // 输出寄存后的 logical flit
    assign ready_o = candidate_valid_d ? ((4'b0001 << candidate_d) & {4{select_ready}}) : 4'b0000; // 仅向装入选择级的候选 VC 返回 ready
    assign input_eop = (candidate_d == 2'd0) ? flit0_i[594] : (candidate_d == 2'd1) ? flit1_i[594] : (candidate_d == 2'd2) ? flit2_i[594] : flit3_i[594]; // 从候选 logical header 提取 EOP
    always @(*) begin // 组合执行锁定优先和 packet 配额仲裁
        candidate_d = 2'd0; // 默认候选 VC 零
        candidate_valid_d = 1'b0; // 默认没有有效候选
        if (packet_lock_q) begin // 检查当前 packet 锁定状态
            candidate_d = selected_q; // 保持锁定 VC 不可抢占
            candidate_valid_d = valid_i[selected_q]; // 已在 SOP 边界保留整包 credit 后仅等待锁定 VC 数据有效
        end else if (data_runnable && (high_quota_q >= 3'd4)) begin // 检查高优先配额已用尽
            if (runnable[{1'b0, data_rr_q}]) begin // 优先选择 data 轮询起点
                candidate_d = {1'b0, data_rr_q}; // 选择轮询起点 VC
            end else begin // 处理轮询起点不可运行
                candidate_d = {1'b0, !data_rr_q}; // 选择另一个 data VC
            end // 结束 data 配额选择
            candidate_valid_d = 1'b1; // 声明 data 配额候选有效
        end else if (runnable[2]) begin // 检查全局控制 VC2
            candidate_d = 2'd2; // 固定优先选择 VC2
            candidate_valid_d = 1'b1; // 声明 VC2 候选有效
        end else if (runnable[3]) begin // 检查 replay VC3
            candidate_d = 2'd3; // 次优先选择 VC3
            candidate_valid_d = 1'b1; // 声明 VC3 候选有效
        end else if (data_runnable) begin // 检查普通 data VC
            if (runnable[{1'b0, data_rr_q}]) begin // 检查 data 轮询起点可运行
                candidate_d = {1'b0, data_rr_q}; // 选择轮询起点 VC
            end else begin // 处理 data 轮询起点不可运行
                candidate_d = {1'b0, !data_rr_q}; // 选择另一个 data VC
            end // 结束 data 轮询选择
            candidate_valid_d = 1'b1; // 声明 data 候选有效
        end // 结束候选优先级选择
    end // 结束 VC 仲裁组合逻辑
    always @(posedge clk_i or negedge rst_n_i) begin // 更新弹性输出、packet 锁定和配额状态
        if (!rst_n_i) begin // 检测复位有效
            select_valid_q <= 20'd0; // 清除全部分段选择流水级有效
            select_flit0_q <= 640'd0; // 清零选择级 VC0 快照
            select_flit1_q <= 640'd0; // 清零选择级 VC1 快照
            select_flit2_q <= 640'd0; // 清零选择级 VC2 快照
            select_flit3_q <= 640'd0; // 清零选择级 VC3 快照
            output_valid_q <= 20'd0; // 清除全部分段弹性输出有效
            output_flit_q <= 640'd0; // 清零弹性输出 flit
            output_vc_q <= 2'd0; // 清零弹性输出 VC
            packet_lock_q <= 1'b0; // 清除 packet 锁定
            selected_q <= 2'd0; // 清零锁定 VC
            data_rr_q <= 1'b0; // 首次普通 data 选择 VC0
            high_quota_q <= 3'd0; // 清零连续高优先 packet 数量
            for (segment_index = 0; segment_index < 20; segment_index = segment_index + 1) select_vc_q[segment_index] <= 2'd0; // 清零全部分段选择副本
        end else begin // 处理仲裁器正常运行
            for (segment_index = 0; segment_index < 20; segment_index = segment_index + 1) begin // 独立更新二十个三十二位弹性数据段
                if (!select_valid_q[segment_index] || !output_valid_q[segment_index] || ready_i) begin // 检查当前选择段可接收候选
                    select_valid_q[segment_index] <= candidate_valid_d; // 锁存当前段候选有效状态
                    select_flit0_q[segment_index*32 +: 32] <= flit0_i[segment_index*32 +: 32]; // 锁存 VC0 当前段快照
                    select_flit1_q[segment_index*32 +: 32] <= flit1_i[segment_index*32 +: 32]; // 锁存 VC1 当前段快照
                    select_flit2_q[segment_index*32 +: 32] <= flit2_i[segment_index*32 +: 32]; // 锁存 VC2 当前段快照
                    select_flit3_q[segment_index*32 +: 32] <= flit3_i[segment_index*32 +: 32]; // 锁存 VC3 当前段快照
                    select_vc_q[segment_index] <= candidate_d; // 锁存当前段候选 VC 编号
                end // 结束当前选择段更新
                if (!output_valid_q[segment_index] || ready_i) begin // 检查当前输出段可更新
                    output_valid_q[segment_index] <= select_valid_q[segment_index]; // 前推当前段选择有效状态
                    if (select_valid_q[segment_index]) begin // 检查当前选择段存在 flit
                        case (select_vc_q[segment_index]) // 使用本地复制选择寄存器控制当前段
                            2'd0: output_flit_q[segment_index*32 +: 32] <= select_flit0_q[segment_index*32 +: 32]; // 选择 VC0 当前段
                            2'd1: output_flit_q[segment_index*32 +: 32] <= select_flit1_q[segment_index*32 +: 32]; // 选择 VC1 当前段
                            2'd2: output_flit_q[segment_index*32 +: 32] <= select_flit2_q[segment_index*32 +: 32]; // 选择 VC2 当前段
                            default: output_flit_q[segment_index*32 +: 32] <= select_flit3_q[segment_index*32 +: 32]; // 选择 VC3 当前段
                        endcase // 结束当前数据段选择
                    end // 结束当前选择段输出处理
                end // 结束当前输出段更新
            end // 结束二十个弹性数据段更新
            if (output_ready && select_valid_q[0]) output_vc_q <= select_vc_q[0]; // 锁存与段零输出对齐的 VC 编号
            if (input_fire) begin // 检测成功从候选 VC 接收一个 flit
            if (!packet_lock_q && !input_eop) begin // 检测多 flit packet 首个或中间 flit
                packet_lock_q <= 1'b1; // 锁定当前 packet VC
                selected_q <= candidate_d; // 保存当前 packet VC 编号
            end else if (packet_lock_q && input_eop) begin // 检测锁定 packet 尾 flit
                packet_lock_q <= 1'b0; // 在 EOP 后释放 packet 锁定
            end // 结束 packet 锁定更新
            if (input_eop) begin // 仅在 packet 边界更新公平状态
                if (candidate_d < 2) begin // 检查普通 data packet 完成
                    data_rr_q <= !candidate_d[0]; // 下次优先服务另一个 data VC
                    high_quota_q <= 3'd0; // 普通 data 服务后清零高优先配额
                end else if (high_quota_q < 3'd4) begin // 检查高优先配额尚未饱和
                    high_quota_q <= high_quota_q + 1'b1; // 增加连续高优先 packet 数量
                end // 结束 packet 公平状态更新
            end // 结束 packet 边界处理
            end // 结束候选输入握手处理
        end // 结束正常运行处理
    end // 结束仲裁状态时序逻辑
endmodule // 结束四 VC packet 仲裁器
