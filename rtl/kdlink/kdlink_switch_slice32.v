module kdlink_switch_slice32 ( // 定义单 slice 三十二端口八 VC VOQ switch 数据面
    input wire clk_i, // 接收 switch 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire [31:0] ingress_valid_i, // 接收三十二 ingress 有效位
    output reg [31:0] ingress_ready_o, // 返回三十二 ingress 本地 VOQ 接收能力
    input wire [20479:0] ingress_flit_i, // 接收三十二个 640-bit flit
    output wire [31:0] egress_valid_o, // 输出三十二 egress 有效位
    input wire [31:0] egress_ready_i, // 接收三十二 egress 本地 FIFO 消费能力
    output wire [20479:0] egress_flit_o, // 输出三十二个 640-bit flit
    output wire [31:0] escape_pending_o, // 输出各 ingress 的 VC0 pending 状态
    output reg protocol_error_o // 指示 VOQ 或 egress FIFO 内部不变量错误
); // 结束端口声明
    localparam integer VOQ_COUNT = 8192; // 固定三十二 ingress 乘三十二 destination 乘八 VC
    localparam integer VOQ_DEPTH = 4; // 固定每 VOQ 四 flit 深度
    localparam integer EGRESS_DEPTH = 4; // 固定每 egress 四 flit 深度
    /* verilator lint_off WIDTHEXPAND */ // 参数化数组索引按 integer 计算并在固定范围内截断
    reg [639:0] voq_mem_q [0:32767]; // 保存全部 input-banked VOQ flit
    reg [1:0] voq_read_ptr_q [0:VOQ_COUNT-1]; // 保存全部 VOQ 读指针
    reg [1:0] voq_write_ptr_q [0:VOQ_COUNT-1]; // 保存全部 VOQ 写指针
    reg [2:0] voq_count_q [0:VOQ_COUNT-1]; // 保存全部 VOQ occupancy
    reg [7:0] input_rr_q [0:31]; // 保存各 ingress destination/VC 选择起点
    reg [4:0] output_rr_q [0:31]; // 保存各 egress ingress 选择起点
    reg [31:0] selected_valid_d; // 保存各 ingress 的 VOQ winner 有效位
    reg [159:0] selected_dst_d; // 保存各 ingress 的 VOQ winner destination
    reg [95:0] selected_vc_d; // 保存各 ingress 的 VOQ winner VC
    reg [31:0] grant_valid_d; // 保存各 egress matching grant 有效位
    reg [159:0] grant_input_d; // 保存各 egress matching ingress
    reg [31:0] input_grant_d; // 保存各 ingress 本周期是否被 matching
    reg [VOQ_COUNT-1:0] push_event_d; // 保存全部 VOQ push 事件
    reg [VOQ_COUNT-1:0] pop_event_d; // 保存全部 VOQ pop 事件
    reg [31:0] crossbar_valid_q; // 保存 grant 后注册 crossbar 有效位
    reg [20479:0] crossbar_flit_q; // 保存 grant 后注册 crossbar flit
    reg [639:0] egress_mem_q [0:127]; // 保存三十二组四深度 egress FIFO
    reg [1:0] egress_read_ptr_q [0:31]; // 保存各 egress FIFO 读指针
    reg [1:0] egress_write_ptr_q [0:31]; // 保存各 egress FIFO 写指针
    reg [2:0] egress_count_q [0:31]; // 保存各 egress FIFO occupancy
    wire [159:0] ingress_dst; // 提取各 ingress 最终 destination
    wire [95:0] ingress_vc; // 提取各 ingress VC
    integer input_index; // 提供 ingress 循环索引
    integer output_index; // 提供 egress 循环索引
    integer queue_index; // 提供 VOQ 循环索引
    integer select_offset; // 提供 ingress VOQ 扫描偏移
    integer request_offset; // 提供 egress ingress 扫描偏移
    integer candidate_index; // 保存 destination/VC 候选索引
    integer candidate_input; // 保存 ingress 候选索引
    integer candidate_queue; // 保存 VOQ 候选索引
    integer escape_destination; // 保存 VC0 destination 候选
    integer push_queue; // 保存 ingress push VOQ 索引
    integer pop_queue; // 保存 matching pop VOQ 索引
    genvar port_index; // 提供静态 port 生成索引
    generate // 提取 header 路由字段并连接 egress FIFO 输出
        for (port_index = 0; port_index < 32; port_index = port_index + 1) begin : g_port // 生成一个 switch port 连接
            assign ingress_dst[port_index*5 +: 5] = ingress_flit_i[port_index*640 + 537 +: 5]; // 提取 header destination 字段
            assign ingress_vc[port_index*3 +: 3] = ingress_flit_i[port_index*640 + 525 +: 3]; // 提取 header VC 字段
            assign egress_valid_o[port_index] = egress_count_q[port_index] != 3'd0; // occupancy 非零时声明 egress 有效
            assign egress_flit_o[port_index*640 +: 640] = egress_mem_q[port_index*4 + egress_read_ptr_q[port_index]]; // 输出当前 egress FIFO 队首
        end // 结束 port 连接生成
    endgenerate // 结束静态 port 连接
    generate // 形成各 ingress VC0 pending 可观测状态
        for (port_index = 0; port_index < 32; port_index = port_index + 1) begin : g_escape_status // 生成单 ingress escape 状态
            wire [31:0] escape_nonempty; // 汇总本 ingress 三十二 destination 的 VC0 状态
            genvar escape_index; // 提供 escape destination 生成索引
            for (escape_index = 0; escape_index < 32; escape_index = escape_index + 1) begin : g_escape_destination // 生成单 destination escape 状态
                assign escape_nonempty[escape_index] = voq_count_q[port_index*256 + escape_index*8] != 3'd0; // 检查对应 VC0 VOQ 非空
            end // 结束单 destination escape 状态
            assign escape_pending_o[port_index] = |escape_nonempty; // 汇总本 ingress escape pending
        end // 结束 escape 状态生成
    endgenerate // 结束 escape pending 连接
    always @(*) begin // 计算 ingress admission、VOQ 选择和两级 matching
        ingress_ready_o = 32'd0; // 默认全部 ingress 不接收
        selected_valid_d = 32'd0; // 默认全部 ingress 无 winner
        selected_dst_d = 160'd0; // 默认 winner destination 为零
        selected_vc_d = 96'd0; // 默认 winner VC 为零
        grant_valid_d = 32'd0; // 默认全部 egress 无 grant
        grant_input_d = 160'd0; // 默认 grant ingress 为零
        input_grant_d = 32'd0; // 默认全部 ingress 未被 matching
        push_event_d = {VOQ_COUNT{1'b0}}; // 默认无 VOQ push
        pop_event_d = {VOQ_COUNT{1'b0}}; // 默认无 VOQ pop
        candidate_input = 0; // 默认 ingress 候选索引为零
        pop_queue = 0; // 默认 pop VOQ 索引为零
        for (input_index = 0; input_index < 32; input_index = input_index + 1) begin // 计算各 ingress admission 和候选 VOQ
            push_queue = input_index*256 + ingress_dst[input_index*5 +: 5]*8 + ingress_vc[input_index*3 +: 3]; // 形成输入 flit 对应 VOQ 索引
            ingress_ready_o[input_index] = voq_count_q[push_queue] < VOQ_DEPTH; // 仅由目标 VOQ 注册 occupancy 产生本地 ready
            if (ingress_valid_i[input_index] && ingress_ready_o[input_index]) push_event_d[push_queue] = 1'b1; // 记录合法 VOQ push
            for (select_offset = 0; select_offset < 32; select_offset = select_offset + 1) begin // 优先扫描三十二 destination 的 escape VC
                escape_destination = (input_rr_q[input_index][7:3] + select_offset) & 31; // 形成 escape destination 候选
                candidate_queue = input_index*256 + escape_destination*8; // 形成 escape VC0 VOQ 索引
                if (!selected_valid_d[input_index] && voq_count_q[candidate_queue] != 3'd0) begin // 捕获首个非空 escape VOQ
                    selected_valid_d[input_index] = 1'b1; // 标记本 ingress winner 有效
                    selected_dst_d[input_index*5 +: 5] = escape_destination[4:0]; // 保存 escape destination
                    selected_vc_d[input_index*3 +: 3] = 3'd0; // 保存 escape VC 编号
                end // 结束 escape winner 捕获
            end // 结束 escape VOQ 扫描
            for (select_offset = 0; select_offset < 256; select_offset = select_offset + 1) begin // 未命中 escape 时扫描全部 destination/VC
                candidate_index = (input_rr_q[input_index] + select_offset) & 255; // 形成 modulo 二百五十六候选
                candidate_queue = input_index*256 + candidate_index; // 形成普通候选 VOQ 索引
                if (!selected_valid_d[input_index] && voq_count_q[candidate_queue] != 3'd0) begin // 捕获首个非空普通 VOQ
                    selected_valid_d[input_index] = 1'b1; // 标记本 ingress winner 有效
                    selected_dst_d[input_index*5 +: 5] = candidate_index[7:3]; // 保存普通 destination
                    selected_vc_d[input_index*3 +: 3] = candidate_index[2:0]; // 保存普通 VC
                end // 结束普通 winner 捕获
            end // 结束全部 VOQ 扫描
        end // 结束 ingress admission 和 VOQ 选择
        for (output_index = 0; output_index < 32; output_index = output_index + 1) begin // 为各 egress 匹配一个 ingress
            if ((egress_count_q[output_index] + {2'd0, crossbar_valid_q[output_index]}) < EGRESS_DEPTH) begin // 检查 egress FIFO 和在途 grant 预留空间
                for (request_offset = 0; request_offset < 32; request_offset = request_offset + 1) begin // 从本 egress round-robin 起点扫描 ingress
                    candidate_input = (output_rr_q[output_index] + request_offset) & 31; // 形成 modulo 三十二 ingress 候选
                    if (!grant_valid_d[output_index] && selected_valid_d[candidate_input] && (selected_dst_d[candidate_input*5 +: 5] == output_index[4:0])) begin // 捕获首个请求本 egress 的 ingress
                        grant_valid_d[output_index] = 1'b1; // 标记本 egress grant 有效
                        grant_input_d[output_index*5 +: 5] = candidate_input[4:0]; // 保存 grant ingress
                        input_grant_d[candidate_input] = 1'b1; // 标记该 ingress 已被匹配
                    end // 结束 egress grant 捕获
                end // 结束 ingress 请求扫描
            end // 结束 egress 容量检查
            if (grant_valid_d[output_index]) begin // 形成 grant 对应 VOQ pop
                pop_queue = grant_input_d[output_index*5 +: 5]*256 + output_index*8 + selected_vc_d[grant_input_d[output_index*5 +: 5]*3 +: 3]; // 形成 winner VOQ 索引
                pop_event_d[pop_queue] = 1'b1; // 记录合法 VOQ pop
            end // 结束 VOQ pop 形成
        end // 结束全部 egress matching
    end // 结束 admission 和 matching 计算
    always @(posedge clk_i or negedge rst_n_i) begin // 更新 VOQ、crossbar 和 egress FIFO 状态
        if (!rst_n_i) begin // 检测复位有效
            protocol_error_o <= 1'b0; // 清除协议不变量错误
            crossbar_valid_q <= 32'd0; // 清除全部在途 crossbar valid
            crossbar_flit_q <= 20480'd0; // 清零全部在途 crossbar flit
            for (input_index = 0; input_index < 32; input_index = input_index + 1) input_rr_q[input_index] <= 8'd0; // 清零全部 ingress round-robin 起点
            for (output_index = 0; output_index < 32; output_index = output_index + 1) begin // 清零全部 egress 状态
                output_rr_q[output_index] <= 5'd0; // 清零 egress round-robin 起点
                egress_read_ptr_q[output_index] <= 2'd0; // 清零 egress 读指针
                egress_write_ptr_q[output_index] <= 2'd0; // 清零 egress 写指针
                egress_count_q[output_index] <= 3'd0; // 清零 egress occupancy
            end // 结束 egress 状态清零
            for (queue_index = 0; queue_index < VOQ_COUNT; queue_index = queue_index + 1) begin // 清零全部 VOQ 控制状态
                voq_read_ptr_q[queue_index] <= 2'd0; // 清零 VOQ 读指针
                voq_write_ptr_q[queue_index] <= 2'd0; // 清零 VOQ 写指针
                voq_count_q[queue_index] <= 3'd0; // 清零 VOQ occupancy
            end // 结束 VOQ 控制状态清零
        end else begin // 处理正常 switch 流水
            protocol_error_o <= 1'b0; // 默认本周期无不变量错误
            crossbar_valid_q <= grant_valid_d; // 注册本周期 matching grant
            for (input_index = 0; input_index < 32; input_index = input_index + 1) begin // 更新 ingress 公平性起点
                if (input_grant_d[input_index]) input_rr_q[input_index] <= {selected_dst_d[input_index*5 +: 5], selected_vc_d[input_index*3 +: 3]} + 8'd1; // 从已服务 VOQ 后继开始
            end // 结束 ingress 公平性更新
            for (output_index = 0; output_index < 32; output_index = output_index + 1) begin // 捕获 grant flit 并更新 egress FIFO
                if (grant_valid_d[output_index]) begin // 检查本 egress matching 成立
                    crossbar_flit_q[output_index*640 +: 640] <= voq_mem_q[(grant_input_d[output_index*5 +: 5]*256 + output_index*8 + selected_vc_d[grant_input_d[output_index*5 +: 5]*3 +: 3])*4 + voq_read_ptr_q[grant_input_d[output_index*5 +: 5]*256 + output_index*8 + selected_vc_d[grant_input_d[output_index*5 +: 5]*3 +: 3]]]; // 注册 winner VOQ 队首 flit
                    output_rr_q[output_index] <= grant_input_d[output_index*5 +: 5] + 5'd1; // 下一次从后继 ingress 开始
                    if (voq_count_q[grant_input_d[output_index*5 +: 5]*256 + output_index*8 + selected_vc_d[grant_input_d[output_index*5 +: 5]*3 +: 3]] == 3'd0) protocol_error_o <= 1'b1; // 报告意外空 VOQ grant
                end // 结束 matching flit 捕获
                case ({crossbar_valid_q[output_index], egress_valid_o[output_index] && egress_ready_i[output_index]}) // 按 egress push/pop 更新 FIFO
                    2'b10: begin // 仅 crossbar push
                        if (egress_count_q[output_index] >= EGRESS_DEPTH) begin // 检查 egress overflow
                            protocol_error_o <= 1'b1; // 报告 egress overflow
                        end else begin // egress 有可用空间
                            egress_mem_q[output_index*4 + egress_write_ptr_q[output_index]] <= crossbar_flit_q[output_index*640 +: 640]; // 写入 egress FIFO
                            egress_write_ptr_q[output_index] <= egress_write_ptr_q[output_index] + 2'd1; // 推进 egress 写指针
                            egress_count_q[output_index] <= egress_count_q[output_index] + 3'd1; // 增加 egress occupancy
                        end // 结束 egress 空间处理
                    end // 结束仅 push 处理
                    2'b01: begin // 仅 egress pop
                        egress_read_ptr_q[output_index] <= egress_read_ptr_q[output_index] + 2'd1; // 推进 egress 读指针
                        egress_count_q[output_index] <= egress_count_q[output_index] - 3'd1; // 减少 egress occupancy
                    end // 结束仅 pop 处理
                    2'b11: begin // 同拍 egress push 和 pop
                        egress_mem_q[output_index*4 + egress_write_ptr_q[output_index]] <= crossbar_flit_q[output_index*640 +: 640]; // 写入新的 egress flit
                        egress_write_ptr_q[output_index] <= egress_write_ptr_q[output_index] + 2'd1; // 推进 egress 写指针
                        egress_read_ptr_q[output_index] <= egress_read_ptr_q[output_index] + 2'd1; // 推进 egress 读指针
                    end // 结束同拍 push/pop
                    default: begin // 处理 egress 空闲
                        egress_count_q[output_index] <= egress_count_q[output_index]; // 保持 egress occupancy
                    end // 结束 egress 空闲
                endcase // 结束 egress FIFO 更新
            end // 结束全部 egress 更新
            for (queue_index = 0; queue_index < VOQ_COUNT; queue_index = queue_index + 1) begin // 更新全部 input-banked VOQ
                case ({push_event_d[queue_index], pop_event_d[queue_index]}) // 按 VOQ push/pop 更新状态
                    2'b10: begin // 仅 VOQ push
                        voq_mem_q[queue_index*4 + voq_write_ptr_q[queue_index]] <= ingress_flit_i[(queue_index >> 8)*640 +: 640]; // 写入 ingress flit
                        voq_write_ptr_q[queue_index] <= voq_write_ptr_q[queue_index] + 2'd1; // 推进 VOQ 写指针
                        voq_count_q[queue_index] <= voq_count_q[queue_index] + 3'd1; // 增加 VOQ occupancy
                    end // 结束仅 push 处理
                    2'b01: begin // 仅 VOQ pop
                        voq_read_ptr_q[queue_index] <= voq_read_ptr_q[queue_index] + 2'd1; // 推进 VOQ 读指针
                        voq_count_q[queue_index] <= voq_count_q[queue_index] - 3'd1; // 减少 VOQ occupancy
                    end // 结束仅 pop 处理
                    2'b11: begin // 同拍 VOQ push 和 pop
                        voq_mem_q[queue_index*4 + voq_write_ptr_q[queue_index]] <= ingress_flit_i[(queue_index >> 8)*640 +: 640]; // 写入新的 ingress flit
                        voq_write_ptr_q[queue_index] <= voq_write_ptr_q[queue_index] + 2'd1; // 推进 VOQ 写指针
                        voq_read_ptr_q[queue_index] <= voq_read_ptr_q[queue_index] + 2'd1; // 推进 VOQ 读指针
                    end // 结束同拍 push/pop
                    default: begin // 处理 VOQ 空闲
                        voq_count_q[queue_index] <= voq_count_q[queue_index]; // 保持 VOQ occupancy
                    end // 结束 VOQ 空闲
                endcase // 结束 VOQ 状态更新
            end // 结束全部 VOQ 更新
        end // 结束正常 switch 流水
    end // 结束 switch 状态更新
    /* verilator lint_on WIDTHEXPAND */ // 恢复数组索引宽度检查
endmodule // 结束单 slice 三十二端口 switch
