module kdlink_route_epoch_manager #( // 定义当前、影子和上一排空代次管理器
    parameter [15:0] RESET_EPOCH = 16'd0, // 指定硬复位后的初始拓扑代次
    parameter [7:0] RESET_PLANE_MASK = 8'h01 // 指定硬复位后的安全活动平面
) ( // 开始路由代次管理器端口声明
    input wire clk_i, // 接收拓扑控制时钟
    input wire rst_n_i, // 接收低有效异步硬复位
    input wire prepare_valid_i, // 接收新拓扑代次 prepare 请求
    input wire [15:0] prepare_epoch_i, // 接收待准备拓扑代次
    input wire [7:0] prepare_plane_mask_i, // 接收待准备活动平面掩码
    input wire commit_valid_i, // 接收原子发布已准备代次请求
    input wire [15:0] commit_epoch_i, // 接收待发布拓扑代次
    input wire previous_drained_i, // 接收上一代次事务和 packet 已完全排空指示
    output reg [15:0] current_epoch_o, // 输出当前活动拓扑代次
    output reg [7:0] current_plane_mask_o, // 输出当前活动平面掩码
    output reg [15:0] previous_epoch_o, // 输出受控排空的上一拓扑代次
    output reg previous_epoch_valid_o, // 输出上一代次仍可被转发指示
    output reg route_reset_o, // 输出提交新代次的一周期换路脉冲
    output reg config_error_o // 输出非法 prepare 或 commit sticky 错误
); // 结束路由代次管理器端口声明
    reg prepared_valid_q; // 保存影子拓扑代次有效位
    reg [15:0] prepared_epoch_q; // 保存影子拓扑代次
    reg [7:0] prepared_plane_mask_q; // 保存影子活动平面掩码
    wire prepare_contract_valid; // 标记新代次保留 plane0 escape 且不等于当前代次
    wire commit_contract_valid; // 标记提交精确命中影子代次且双代窗口可用
    assign prepare_contract_valid = prepare_plane_mask_i[0] && (prepare_epoch_i != current_epoch_o) && (!previous_epoch_valid_o || previous_drained_i); // 要求存在 escape 并限制最多双代并存
    assign commit_contract_valid = prepared_valid_q && (commit_epoch_i == prepared_epoch_q) && (!previous_epoch_valid_o || previous_drained_i); // 仅发布精确影子代次且上一代已经排空
    always @(posedge clk_i or negedge rst_n_i) begin // 更新当前、影子和上一排空代次
        if (!rst_n_i) begin // 硬复位建立仅 plane0 的安全初始代次
            current_epoch_o <= RESET_EPOCH; current_plane_mask_o <= RESET_PLANE_MASK; // 初始化当前代次和平面掩码
            previous_epoch_o <= 16'd0; previous_epoch_valid_o <= 1'b0; // 清除上一排空代次
            prepared_valid_q <= 1'b0; prepared_epoch_q <= 16'd0; prepared_plane_mask_q <= 8'd0; // 清除影子代次
            route_reset_o <= 1'b0; config_error_o <= !RESET_PLANE_MASK[0]; // 检查复位 profile 保留 escape 平面
        end else begin // 正常处理 prepare、commit 和排空事件
            route_reset_o <= 1'b0; // 默认不触发源事务换路重发
            if (previous_epoch_valid_o && previous_drained_i) previous_epoch_valid_o <= 1'b0; // 完全排空后关闭上一代次接收窗口
            if (prepare_valid_i) begin // 捕获不影响当前转发的影子拓扑
                if (prepare_contract_valid) begin prepared_valid_q <= 1'b1; prepared_epoch_q <= prepare_epoch_i; prepared_plane_mask_q <= prepare_plane_mask_i; end // 保存合法影子代次
                else config_error_o <= 1'b1; // sticky 报告无 escape、重复代次或三代并存请求
            end // 结束影子拓扑准备
            if (commit_valid_i) begin // 尝试原子切换已准备拓扑
                if (commit_contract_valid) begin // 精确提交影子代次
                    previous_epoch_o <= current_epoch_o; previous_epoch_valid_o <= 1'b1; // 将旧当前代次转入受控排空窗口
                    current_epoch_o <= prepared_epoch_q; current_plane_mask_o <= prepared_plane_mask_q; // 原子发布新代次和平面掩码
                    prepared_valid_q <= 1'b0; route_reset_o <= 1'b1; // 清除影子并触发未完成事务换路
                end else config_error_o <= 1'b1; // sticky 报告无 prepare、键不符或三代并存提交
            end // 结束拓扑代次提交
        end // 结束正常代次管理
    end // 结束路由代次管理器时序逻辑
endmodule // 结束 kdlink_route_epoch_manager
