`default_nettype none // 禁止隐式网络掩盖源优先与目的优先矩阵连接错误。
// 本地单播packet仲裁候选；raw selection保留owner，实际传输仍须由fabric检查valid与route。
module switch_arbiter #( // switch_arbiter模块为每个出口独立保留整包所有权和下一包轮询次序。
    parameter integer PORTS = 4 // 输入输出端口数须为正整数，本轮独立验证一至五。
) ( // 端口均属于i_clk域，不在模块内部跨时钟域。
    input wire i_clk, // 使用同一上升沿更新包所有权。
    input wire i_rstn, // 同步低有效复位，同时组合屏蔽公开选择和owned。
    input wire [PORTS-1:0] i_valid, // 每源当前beat是否有效，反压期间须保持包字段。
    input wire [PORTS*PORTS-1:0] i_route_match, // source-major唯一目的位图，由外部lookup保证唯一性。
    input wire [PORTS-1:0] i_last, // 每源当前beat是包末拍；只在实际握手时生效。
    input wire [PORTS-1:0] i_ready, // 每出口实际接收能力，不参与组合选择。
    output reg [PORTS*PORTS-1:0] o_select, // egress-major raw owner onehot，不能直接当有效grant。
    output wire [PORTS-1:0] o_owned // 实际锁包状态供配置提交判断，包含包内气泡。
); // 结束本地单播仲裁接口声明。
    localparam PORT_COUNT = PORTS; // 显式静态出口数同时约束组合扫描和状态展开。
    reg [PORTS-1:0] locked_q; // 首拍停顿或未结束包的出口锁定位。
    integer owner_q [0:PORTS-1]; // 每个锁定出口拥有的源索引，不含任何协议Tag。
    integer round_robin_q [0:PORTS-1]; // 下一包从上个实际结束源之后开始竞争。
    integer selected [0:PORTS-1]; // 当前raw选择，负一表示空闲出口没有合法请求。
    integer egress, offset, candidate; // 组合有界轮询索引，和时序循环变量分开。
    genvar state_port; // 静态展开每个出口寄存过程，所有时序赋值均为非阻塞。
    assign o_owned = i_rstn ? locked_q : {PORTS{1'b0}}; // 复位期间禁止把旧包所有权公开给配置层。

    always @(*) begin // 计算目的优先选择矩阵，不以接收ready决定请求是否可见。
        o_select = {(PORTS*PORTS){1'b0}}; // 未选出口及复位状态始终输出确定零。
        candidate = 0; // 没有空闲扫描时也完整驱动过程变量。
        offset = 0; // 锁包路径不执行扫描，仍给偏移默认值。
        for (egress = 0; egress < PORT_COUNT; egress = egress + 1) begin // 每出口独立仲裁，最多选择一个源。
            selected[egress] = -1; // 空闲且无合法请求时不建立所有权。
            if (i_rstn) begin // 组合复位屏蔽不依赖下一次时钟沿。
                if (locked_q[egress]) begin // 包内气泡或临时route失配不允许其他源抢占。
                    selected[egress] = owner_q[egress]; // raw选择持续公开原owner，fabric另行限定有效传输。
                end else begin // 尚无包owner时依据上次完成后的次序选择新包。
                    for (offset = 0; offset < PORT_COUNT; offset = offset + 1) begin // 每个源最多检查一次，循环边界可静态综合。
                        candidate = round_robin_q[egress] + offset; // 将轮询起点和候选偏移合成无截断整数。
                        if (candidate >= PORTS) candidate = candidate - PORTS; // 非二次幂端口数也正确回绕。
                        if (selected[egress] < 0 && i_valid[candidate] && i_route_match[candidate*PORTS+egress]) begin // 只保留次序中的第一个有效唯一目的请求。
                            selected[egress] = candidate; // 选择不等待下游ready，支持首拍反压时绑定。
                        end // 结束当前源资格判断。
                    end // 结束本出口全部候选扫描。
                end // 结束锁定包与新包的选择分支。
                if (selected[egress] >= 0) o_select[egress*PORTS+selected[egress]] = 1'b1; // 将单个源索引展开为目的优先raw onehot。
            end // 结束正常组合选择与复位屏蔽分支。
        end // 结束所有出口组合仲裁。
    end // 结束组合选择过程。

    generate for (state_port = 0; state_port < PORT_COUNT; state_port = state_port + 1) begin: gen_owner // 每出口静态展开一个独立包状态过程。
        always @(posedge i_clk) begin // 只有时钟沿能够建立、保持或释放实际包所有权。
            if (!i_rstn) begin // 同步复位取消旧包并恢复从源零开始的公平次序。
                locked_q[state_port] <= 1'b0; // 清除本出口包锁定，不修改其他出口的状态位。
                owner_q[state_port] <= 0; // 无锁状态的索引也保持确定值。
                round_robin_q[state_port] <= 0; // 本出口从源零开始第一次竞争。
            end else begin // 非复位时仅有效且route匹配的owner能推动状态。
                if (selected[state_port] >= 0 && i_valid[selected[state_port]] && i_route_match[selected[state_port]*PORTS+state_port]) begin // raw选择不等于有效grant，失配与气泡保持原状态。
                    if (i_ready[state_port] && i_last[selected[state_port]]) begin // 只有有效匹配末拍实际被接受才退休当前包。
                        locked_q[state_port] <= 1'b0; // 完整包结束后开放下一包竞争。
                        if (selected[state_port] == PORTS-1) round_robin_q[state_port] <= 0; // 最后一个源完成后准确回到源零。
                        else round_robin_q[state_port] <= selected[state_port] + 1; // 次序从本次完成源之后开始，避免持续请求饿死。
                    end else begin // 首拍停顿与已接纳非末拍都必须绑定当前包。
                        locked_q[state_port] <= 1'b1; // 即使ready为零也保留首拍已公开的选择。
                        owner_q[state_port] <= selected[state_port]; // 后续气泡期间保持整个包的源身份。
                    end // 结束末拍退休和继续持有分支。
                end // 无有效匹配传输时不释放owner，也不推进轮询。
            end // 结束同步复位和正常状态更新。
        end // 结束本出口的包owner寄存过程。
    end endgenerate // 结束各出口独立状态寄存器展开。
endmodule // 结束switch_arbiter候选模块。
`default_nettype wire // 恢复后续独立源文件的默认网络规则。
