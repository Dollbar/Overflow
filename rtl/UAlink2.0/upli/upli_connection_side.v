// UPLI single-side connection controller; Common 2.0 sections 4.1-4.3.
// UALink 工程；2026-09-07；仅实现单侧连接控制，不生成对端信号或信用。
// 同步复位与寄存器延迟见 docs/upli_connection_rtl_plan.md；无跨时钟域。
`timescale 1ps/1ps // 仅声明仿真单位；本模块没有延迟，综合时钟由外部约束定义。
module upli_connection_side #( // 以同一个控制模块分别构造 Originator 与 Completer 侧。
    parameter C_IS_COMPLETER = 1'b0, // 本侧角色，置一时允许采用 Completer 等待策略。
    parameter C_COMPLETER_WAITS = 1'b0 // 仅 Completer 可选择先等待 Originator 方向连接完成。
) ( // 两侧均使用同一 UPLIClk，接口信息必须在采样边沿前稳定。
    input wire i_clk, // UPLI 共同上升沿时钟，不通过本模块进行门控或调频。
    input wire i_rstn, // 同步低有效接口复位，至少覆盖一次完整采样边沿。
    input wire i_ready, // 本侧能够承诺接受对应信息并启动连接的能力条件。
    input wire i_peer_req, // 对端请求建立其发送方向，作为本侧应答的输入。
    input wire i_peer_ack, // 对端确认本侧请求，完成本侧发送方向的握手。
    output wire o_req, // 本侧发出的连接请求，断言后保持到共同接口复位。
    output wire o_ack, // 本侧对对端请求的接受承诺，断言后保持到接口复位。
    output wire o_tx_connected, // 本侧发送方向已连接，可结合相应规则发送信用。
    output wire o_rx_connected, // 对端发送方向已连接，可接收该方向合法信用。
    output wire o_beats_connected // 双向连接必要条件，不包含信用、初始化或调度资格。
); // 结束单侧 UPLI 连接控制端口定义。
    reg reg_active; // 复位撤销后经过一个采样边沿才允许更新握手状态。
    reg reg_req_o; // 本侧请求寄存器，由同步复位和本侧能力条件驱动。
    reg reg_ack_o; // 本侧接受寄存器，只响应沿前稳定的对端请求。
    wire flag_request_allowed; // Originator 无条件允许主动请求，Completer 可选等待。

    assign flag_request_allowed = (!C_IS_COMPLETER) || (!C_COMPLETER_WAITS) || (i_peer_req && reg_ack_o); // 等待的是对端已连接，不是对端仅发出请求。
    assign o_req = reg_req_o; // 本侧请求直接来自寄存器，不存在对端到请求的组合路径。
    assign o_ack = reg_ack_o; // 本侧接受直接来自寄存器，避免两端组合握手环路。
    assign o_tx_connected = reg_req_o && i_peer_ack; // 发送方向需要本侧请求和对端接受。
    assign o_rx_connected = i_peer_req && reg_ack_o; // 接收方向需要对端请求和本侧接受。
    assign o_beats_connected = o_tx_connected && o_rx_connected; // 只有四个握手信号均有效才满足数据连接前提。

    always @(posedge i_clk) begin // 单独保存撤销复位守卫，保持同步复位语义。
        if (!i_rstn) begin // 采样到低有效复位时禁止本侧握手启动。
            reg_active <= 1'b0; // 清除守卫，保证撤销复位的首个采样沿仍静默。
        end else begin // 首个撤销复位采样沿只为之后的周期开放启动条件。
            reg_active <= 1'b1; // 正常运行期间持续允许同步握手更新。
        end // 结束守卫复位与正常运行分支。
    end // 结束复位撤销守卫寄存器过程。

    always @(posedge i_clk) begin // 请求寄存器与应答寄存器独立，防止双向互等。
        if (!i_rstn) begin // 共同接口复位清除已经发出的请求。
            reg_req_o <= 1'b0; // 请求在一次复位采样后进入无效状态。
        end else if (reg_active && i_ready && flag_request_allowed) begin // 首个撤销沿之后且合法角色条件满足才请求。
            reg_req_o <= 1'b1; // 发出请求后不能因 ready 降低而撤回。
        end else begin // 未到启动条件或已经建立请求时维持原承诺。
            reg_req_o <= reg_req_o; // 明确保存请求，只有同步 reset 能清除。
        end // 结束请求启动与保持分支。
    end // 结束本侧请求寄存器过程。

    always @(posedge i_clk) begin // 应答只检查对端沿前请求和本侧接收能力。
        if (!i_rstn) begin // 共同接口复位撤销之前的接受承诺。
            reg_ack_o <= 1'b0; // 应答在一次复位采样后进入无效状态。
        end else if (reg_active && i_ready && i_peer_req) begin // 本侧已脱离复位并能接受信息才确认对端。
            reg_ack_o <= 1'b1; // 对端请求被寄存确认，不生成组合响应。
        end else begin // 接受承诺不因之后的能力输入变化而撤回。
            reg_ack_o <= reg_ack_o; // 保持应答状态，等待共同接口 reset。
        end // 结束应答启动与保持分支。
    end // 结束本侧接受寄存器过程。
endmodule // 结束 upli_connection_side 单侧同步连接控制模块。
