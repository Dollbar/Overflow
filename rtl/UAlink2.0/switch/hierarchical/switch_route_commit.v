`timescale 1ns/1ps // 定义Route commit控制器仿真时间单位，不参与综合逻辑。
`default_nettype none // 禁止隐式网络掩盖管理状态连接错误。
module switch_route_commit #( // 实现停止准入、等待排空和原子切换的Route提交控制器。
    parameter integer EPOCH_WIDTH = 8 // 指定Route配置代际宽度，回绕由管理软件结合排空处理。
) ( // 全部控制信号位于同一个管理时钟域。
    input wire i_clk, // 在上升沿更新pending、epoch和粘滞错误状态。
    input wire i_rstn, // 同步低有效复位恢复旧active image并清零提交状态。
    input wire i_commit_request, // 管理侧以单周期请求开始一次shadow提交。
    input wire i_inflight_empty, // 数据面确认所有可能引用旧Route的packet ownership均已排空。
    input wire i_shadow_illegal, // Port identity shadow image存在非法项时禁止切换。
    output wire o_admission_enable, // 仅无提交等待时允许入口接纳新packet。
    output wire o_quiesce_request, // 提交等待期间要求各数据层继续排空且禁止新准入。
    output wire o_commit_pulse, // 排空且shadow合法时产生一个原子bank切换脉冲。
    output wire o_pending, // 指示Route提交已接收但尚未完成。
    output reg [EPOCH_WIDTH-1:0] o_epoch, // 每次成功原子提交后递增Route代际。
    output reg o_commit_error // 非法shadow请求或等待期间变非法时形成粘滞错误。
); // 结束Route commit控制器接口定义。
    reg pending_q; // 保存已停止准入并等待全部旧packet排空的状态。
    assign o_pending = pending_q; // 向CSR和数据面暴露唯一pending状态。
    assign o_admission_enable = !pending_q; // pending期间立即停止新的SOP准入。
    assign o_quiesce_request = pending_q; // pending期间持续请求全路径排空。
    assign o_commit_pulse = pending_q && i_inflight_empty && !i_shadow_illegal; // 仅在合法且真正排空时切换双表bank。
    always @(posedge i_clk) begin // 使用同步复位更新提交状态，避免组合ready跨越数据面。
        if (!i_rstn) begin // 复位保持bank0为初始active image并清除旧请求。
            pending_q <= 1'b0; // 复位后没有未完成提交。
            o_epoch <= {EPOCH_WIDTH{1'b0}}; // 初始Route代际固定为零。
            o_commit_error <= 1'b0; // 清除旧非法配置诊断。
        end else begin // 正常周期处理新请求、异常取消或成功提交。
            if (!pending_q) begin // IDLE状态只接受新的管理提交请求。
                if (i_commit_request && i_shadow_illegal) begin // 非法shadow不得干扰当前active业务。
                    pending_q <= 1'b0; // 保持当前active image且不停止业务。
                    o_epoch <= o_epoch; // 拒绝提交时禁止伪造epoch变化。
                    o_commit_error <= 1'b1; // 记录管理请求命中非法shadow image。
                end else if (i_commit_request) begin // 合法请求进入显式quiesce等待。
                    pending_q <= 1'b1; // 从下一周期开始禁止新admission。
                    o_epoch <= o_epoch; // 排空完成前保持Route代际。
                    o_commit_error <= o_commit_error; // 保留既有粘滞诊断。
                end else begin // 没有提交请求时保持IDLE状态。
                    pending_q <= 1'b0; // 正常开放数据面准入。
                    o_epoch <= o_epoch; // 没有commit时active epoch必须稳定。
                    o_commit_error <= o_commit_error; // 粘滞错误只由复位清除。
                end // 结束IDLE请求判定。
            end else if (i_shadow_illegal) begin // 等待排空期间shadow变非法则取消本次切换。
                pending_q <= 1'b0; // 恢复旧active image的数据面准入。
                o_epoch <= o_epoch; // 非法取消不改变Route epoch。
                o_commit_error <= 1'b1; // 记录配置竞争或非法重写。
            end else if (i_inflight_empty) begin // 所有旧packet排空后同一边沿完成原子切换。
                pending_q <= 1'b0; // 成功切换后恢复新packet admission。
                o_epoch <= o_epoch + {{(EPOCH_WIDTH-1){1'b0}}, 1'b1}; // 为新active image分配下一代际。
                o_commit_error <= o_commit_error; // 成功提交不清除历史诊断。
            end else begin // 数据面仍有旧packet时继续等待。
                pending_q <= pending_q; // 保持quiesce直到真正排空。
                o_epoch <= o_epoch; // 等待期间禁止epoch提前变化。
                o_commit_error <= o_commit_error; // 保持粘滞错误状态。
            end // 结束pending状态处理。
        end // 结束正常提交状态更新。
    end // 结束Route commit时序过程。
endmodule // 结束Route commit控制器实现。
`default_nettype wire // 恢复后续编译单元的默认网络规则。
