// 普通Read/Write响应构造；候选限定认证关闭，实际末拍确认后交回final所有权。
`timescale 1ns/1ps // 与原生发送器使用相同仿真时间单位。
`default_nettype none // 禁止隐式接线。
module endpoint_response_formatter #( // 普通响应formatter模块，保存单在途命令metadata与完整结果。
    parameter integer C_NUM_PORTS = 1 // 实际物理端口数仅支持一、二、四。
) ( // 此处是本地ready/valid接口，不是原生UPLI总线。
    input wire i_clk, // 共同上升沿时钟。
    input wire i_rstn, // 同步低有效取消命令与未交回的结果。
    input wire i_command_valid, // 命令接纳信号 i_command_valid。
    input wire [9:0] i_command_token, // 命令接纳信号 i_command_token。
    input wire [7:0] i_command_station, // 命令接纳信号 i_command_station。
    input wire [1:0] i_command_port, // 命令接纳信号 i_command_port。
    input wire [1:0] i_command_vc, // 命令接纳信号 i_command_vc。
    input wire [183:0] i_command_payload, // 原请求完整184位，含原始网络身份与几何。
    input wire [3:0] i_command_response_pools, // 外部显式选择每个响应拍的真实信用账户。
    input wire i_command_auth_enabled, // 显式认证能力；本profile仅允许零。
    input wire i_completion_valid, // 后端结果信号 i_completion_valid。
    input wire [9:0] i_completion_token, // 后端结果信号 i_completion_token。
    input wire [3:0] i_completion_status, // 后端结果信号 i_completion_status。
    input wire [2047:0] i_completion_data, // 后端返回相对自然拍零起的完整四拍数据。
    input wire [3:0] i_completion_poison, // 后端结果信号 i_completion_poison。
    input wire i_rd_candidate_accepted, // 候选交接信号 i_rd_candidate_accepted。
    input wire i_wr_candidate_accepted, // 候选交接信号 i_wr_candidate_accepted。
    input wire i_rd_sent_valid, // 实际发送观察信号 i_rd_sent_valid。
    input wire [1:0] i_rd_sent_port, // 实际发送观察信号 i_rd_sent_port。
    input wire [1:0] i_rd_sent_vc, // 实际发送观察信号 i_rd_sent_vc。
    input wire i_rd_sent_pool, // 实际发送观察信号 i_rd_sent_pool。
    input wire [618:0] i_rd_sent_payload, // 实际发送观察信号 i_rd_sent_payload。
    input wire i_wr_sent_valid, // 实际发送观察信号 i_wr_sent_valid。
    input wire [1:0] i_wr_sent_port, // 实际发送观察信号 i_wr_sent_port。
    input wire [1:0] i_wr_sent_vc, // 实际发送观察信号 i_wr_sent_vc。
    input wire i_wr_sent_pool, // 实际发送观察信号 i_wr_sent_pool。
    input wire [100:0] i_wr_sent_payload, // 实际发送观察信号 i_wr_sent_payload。
    input wire i_final_ready, // 最终发送所有权信号 i_final_ready。
    output wire o_command_ready, // 命令接纳信号 o_command_ready。
    output wire o_completion_ready, // 后端结果信号 o_completion_ready。
    output wire o_rd_candidate_valid, // 候选交接信号 o_rd_candidate_valid。
    output wire [1:0] o_rd_candidate_port, // 候选交接信号 o_rd_candidate_port。
    output wire [1:0] o_rd_candidate_vc, // 候选交接信号 o_rd_candidate_vc。
    output wire [3:0] o_rd_candidate_pools, // 候选交接信号 o_rd_candidate_pools。
    output wire [2475:0] o_rd_candidate_payload, // 候选交接信号 o_rd_candidate_payload。
    output wire o_wr_candidate_valid, // 候选交接信号 o_wr_candidate_valid。
    output wire [1:0] o_wr_candidate_port, // 候选交接信号 o_wr_candidate_port。
    output wire [1:0] o_wr_candidate_vc, // 候选交接信号 o_wr_candidate_vc。
    output wire o_wr_candidate_pool, // 候选交接信号 o_wr_candidate_pool。
    output wire [100:0] o_wr_candidate_payload, // 候选交接信号 o_wr_candidate_payload。
    output wire o_final_valid, // 最终发送所有权信号 o_final_valid。
    output wire [9:0] o_final_token, // 最终发送所有权信号 o_final_token。
    output wire [7:0] o_owner_station, // 保留station上下文，不推断网络路由。
    output wire [183:0] o_owner_payload, // 当前命令原文观察口，不是第二消费接口。
    output wire o_busy, // 状态信号 o_busy。
    output wire o_error, // 有效非法事件诊断；不作为Drop或恢复决策。
    output wire o_error_sticky // 共同复位清除的诊断历史。
); // 完整接口定义结束。
    localparam [2:0] S_IDLE=3'd0, S_RESULT=3'd1, S_CANDIDATE=3'd2, S_SENDING=3'd3, S_FINAL=3'd4, S_FAILED=3'd5; // 错误发送确认进入隔离等待共同reset，绝不补造final。
    localparam [3:0] PORT_MASK=(C_NUM_PORTS==4)?4'hf:(C_NUM_PORTS==2)?4'h3:4'h1; // 实际配置端口集合。
    reg [2:0] state; // 单在途命令生命周期。
    reg [9:0] saved_token; // 本地原token完整保存，不重分配网络Tag。
    reg [7:0] saved_station; // 原station身份用于上层观察。
    reg [183:0] saved_payload; // 完整原命令，避免使用已经变化的上游字段。
    reg [1:0] saved_port,saved_vc,saved_num,read_index; // 原端口VC、多拍编码与下一实际拍位置。
    reg [3:0] saved_pools,saved_status,saved_poison; // 响应账户、统一状态和逐拍poison。
    reg [2047:0] saved_data; // 完整结果，包括错误状态和无效byte的原始值。
    reg saved_write,error_history; // 命令类别及诊断历史。
    wire [8:0] command_bytes,region_end,beat_extent; // 最大四拍的几何扩展算术。
    wire [2:0] command_beats; // 合法自然数据拍数一至四。
    wire command_write,command_full,command_legal,status_legal,completion_good; // 请求资格与结果唯一关联。
    wire read_start,write_start,read_observe_ok,write_observe_ok,read_last_expected; // 实际原生确认，不把候选交接等同末拍。
    wire [10:0] saved_tag; // 完整十一位原网络Tag。
    wire [9:0] response_dst,response_src; // Dst回到原Src，原Dst仅生成debug Src。
    wire candidate_bad,read_bad,write_bad; // 分开暴露接口契约违例。
    wire unused_observed_fields; // 实际Data/Auth/debug Src不参与身份退休，不能以unused补造保护检查。
    wire [3:0] declared_mask; // 固定一至四拍有效集合。
    assign unused_observed_fields=^{i_rd_sent_payload[618:545],i_rd_sent_payload[521:6],i_rd_sent_payload[2:0],i_wr_sent_payload[100:35],i_wr_sent_payload[23:10],beat_extent[5:0]}; // 明确保留观察封套但忽略非关联字段与取整低位。
    assign declared_mask={(&saved_num),saved_num[1],(|saved_num),1'b1}; // 避免零号offset无符号恒真比较。
    genvar g; // 四份固定619位容器展开。
    assign command_bytes=({3'd0,i_command_payload[21:16]}+9'd1)<<2; // Length表示DWORD数减一。
    assign region_end={1'b0,i_command_payload[35:28]}+command_bytes; // 请求不能越过本地256字节区域。
    assign beat_extent={3'd0,i_command_payload[33:28]}+command_bytes+9'd63; // 自然64字节拍数量向上取整。
    assign command_beats=beat_extent[8:6]; // 最大四拍，上游完整地址其余位全部保留。
    assign command_write=(i_command_payload[27:22]==6'h28)||(i_command_payload[27:22]==6'h29); // 只支持已冻结普通Write与WriteFull。
    assign command_full=(i_command_payload[27:22]==6'h29); // Full必须完整自然拍。
    assign command_legal=PORT_MASK[i_command_port]&&!i_command_auth_enabled&&(i_command_payload[181:118]==64'd0)&&((i_command_payload[27:22]==6'h03)||command_write)&&(i_command_payload[29:28]==2'd0)&&(region_end<=9'd256)&&(command_beats>=3'd1)&&(command_beats<=3'd4)&&(command_write?({1'b0,i_command_payload[86:85]}+3'd1==command_beats):(i_command_payload[86:85]==2'd0))&&(!command_full||((i_command_payload[33:28]==6'd0)&&(command_bytes[5:0]==6'd0))); // 认证能力、原身份和几何显式限定，不截断57位地址。
    assign status_legal=(i_completion_status==4'd0)||(i_completion_status==4'd2)||(i_completion_status==4'd3)||(i_completion_status==4'd6)||(i_completion_status==4'd8); // 已冻结普通响应状态；不猜特殊响应编码。
    assign completion_good=(state==S_RESULT)&&(i_completion_token == saved_token)&&status_legal; // 当前唯一命令才可接纳结果。
    assign o_command_ready=i_rstn&&(state==S_IDLE)&&command_legal; // 容量背压不计诊断，也不旁路同沿释放。
    assign o_completion_ready=i_rstn; // 非法结果允许消费为诊断，但绝不改变合法结果所有权。
    assign saved_tag=saved_payload[97:87]; // 原Tag高位不能被内部slot替换。
    assign response_dst=saved_payload[117:108]; // 原请求Source是返回的功能目标。
    assign response_src=saved_payload[107:98]; // 原目标映射为debug Source，观察确认不依赖它。
    assign o_rd_candidate_valid=i_rstn&&(state==S_CANDIDATE)&&!saved_write; // 候选在实际首拍之前持续稳定。
    assign o_rd_candidate_port=o_rd_candidate_valid?saved_port:2'd0; // 无效输出确定为零。
    assign o_rd_candidate_vc=o_rd_candidate_valid?saved_vc:2'd0; // 保留原请求VC。
    assign o_rd_candidate_pools=o_rd_candidate_valid?saved_pools:4'd0; // 显式逐拍账户由原生sender真实消耗。
    generate // 各拍使用固定本地容器，不是TL或线级包格式。
        for(g=0;g<4;g=g+1)begin:gen_read_words // 未声明的尾容器固定清零。
            localparam [1:0] OFFSET=g; // 有效自然拍序号。
            assign o_rd_candidate_payload[g*619 +: 619]=(o_rd_candidate_valid&&declared_mask[g])?{64'd0,response_src,response_dst,saved_tag,saved_num,saved_data[g*512 +: 512],saved_status,OFFSET,(OFFSET==saved_num),saved_poison[g],2'd0}:619'd0; // Auth关闭、完整Data、统一Status和逐拍poison完整生成。
        end // 结束四拍固定生成。
        if((C_NUM_PORTS!=1)&&(C_NUM_PORTS!=2)&&(C_NUM_PORTS!=4))begin:gen_bad_ports // 非法配置不能静默退化。
            ENDPOINT_RESPONSE_FORMATTER_REQUIRES_PORTS_1_2_4 invalid_configuration(); // 综合和编译必须拒绝非法组合。
        end // 结束参数约束。
    endgenerate // 结束静态展开。
    assign o_wr_candidate_valid=i_rstn&&(state==S_CANDIDATE)&&saved_write; // Write只生成一拍无数据响应。
    assign o_wr_candidate_port=o_wr_candidate_valid?saved_port:2'd0; // 原物理端口不截断。
    assign o_wr_candidate_vc=o_wr_candidate_valid?saved_vc:2'd0; // 原请求VC完整返回。
    assign o_wr_candidate_pool=o_wr_candidate_valid&&saved_pools[0]; // 单拍选定账户由sender负责信用。
    assign o_wr_candidate_payload=o_wr_candidate_valid?{64'd0,2'd0,saved_tag,saved_status,response_src,response_dst}:101'd0; // 普通Type零与原身份，认证关闭输出零Auth。
    assign read_start=(state==S_CANDIDATE)&&!saved_write&&i_rd_candidate_accepted; // installed sender的accept与首实际Beat同沿。
    assign write_start=(state==S_CANDIDATE)&&saved_write&&i_wr_candidate_accepted; // Write首拍也是唯一拍。
    assign read_last_expected=(read_index==saved_num); // 只有已按序观察到最后完整Beat才能交回。
    assign read_observe_ok=!saved_write&&(read_start||(state==S_SENDING))&&(i_rd_sent_port==saved_port)&&(i_rd_sent_vc==saved_vc)&&(i_rd_sent_pool==saved_pools[read_index])&&(i_rd_sent_payload[534:524]==saved_tag)&&(i_rd_sent_payload[544:535]==response_dst)&&(i_rd_sent_payload[523:522]==saved_num)&&(i_rd_sent_payload[5:4]==read_index)&&(i_rd_sent_payload[3]==read_last_expected); // Src仅debug不参与功能身份；数据及保护由原生发送器负责。
    assign write_observe_ok=write_start&&(i_wr_sent_port==saved_port)&&(i_wr_sent_vc==saved_vc)&&(i_wr_sent_pool==saved_pools[0])&&(i_wr_sent_payload[34:24]==saved_tag)&&(i_wr_sent_payload[9:0]==response_dst); // 唯一实际Write响应确认，不能以candidatevalid冒充发送。
    assign candidate_bad=(i_rd_candidate_accepted&&(!o_rd_candidate_valid||!i_rd_sent_valid))||(i_wr_candidate_accepted&&(!o_wr_candidate_valid||!i_wr_sent_valid)); // 接纳必须伴随对应实际首拍。
    assign read_bad=i_rd_sent_valid&&!read_observe_ok; // 错误位置或身份不能推进计数。
    assign write_bad=i_wr_sent_valid&&!write_observe_ok; // 错误Write事件不能释放上下文。
    assign o_final_valid=i_rstn&&(state==S_FINAL); // 实际末拍采样后下一周期才有效。
    assign o_final_token=o_final_valid?saved_token:10'd0; // final背压期间原token稳定。
    assign o_busy=i_rstn&&(state!=S_IDLE); // 单槽状态只是本地占用，不是连接许可。
    assign o_owner_station=o_busy?saved_station:8'd0; // 空闲或reset不泄漏旧上下文。
    assign o_owner_payload=o_busy?saved_payload:184'd0; // 完整原文观察用于集成诊断。
    assign o_error=i_rstn&&((i_command_valid&&!command_legal)||(i_completion_valid&&!completion_good)||candidate_bad||read_bad||write_bad); // 正常holding、信用等待或final背压不报错。
    assign o_error_sticky=i_rstn&&(error_history||o_error); // 当前事件与历史合并，不发起任何Drop。
    always @(posedge i_clk)begin // 所有权状态与payload采用同一同步reset。
        if (!i_rstn) begin // 取消未发送或已发送未final的旧事务，不伪造完成。
            state<=S_IDLE; saved_token<=10'd0; saved_station<=8'd0; saved_payload<=184'd0; // 清除命令身份和生命周期。
            saved_port<=2'd0; saved_vc<=2'd0; saved_num<=2'd0; read_index<=2'd0; // 清除端口与发送进度。
            saved_pools<=4'd0; saved_status<=4'd0; saved_poison<=4'd0; saved_data<=2048'd0; // 清除未交回结果与账户选择。
            saved_write<=1'b0; error_history<=1'b0; // 开始新的共同reset epoch。
        end else begin // 不存在任何异步状态或隐含时钟门控。
            if(o_error)error_history<=1'b1; // 非法事件仅设置可见诊断。
            if(i_command_valid&&o_command_ready)begin // 只保存真实原子command握手。
                state<=S_RESULT; saved_token<=i_command_token; saved_station<=i_command_station; saved_payload<=i_command_payload; // 原命令完整持有到final。
                saved_port<=i_command_port; saved_vc<=i_command_vc; saved_num<=command_beats[1:0]-2'd1; // 四拍编码3显式保留。
                saved_pools<=i_command_response_pools; saved_write<=command_write; read_index<=2'd0; // 重启该命令实际响应进度。
            end // 结束命令接纳。
            if(i_completion_valid&&completion_good)begin // 错token、早到或重复结果不能覆盖保存的数据。
                state<=S_CANDIDATE; saved_status<=i_completion_status; saved_data<=i_completion_data; saved_poison<=i_completion_poison; // 错误状态也保存全部数据和poison。
            end // 结束后端结果转移。
            if(i_rd_sent_valid&&read_observe_ok)begin // 首拍可与accept同沿，后续实际拍逐一计数。
                if (read_last_expected) state <= S_FINAL; // 只在真实末拍后产生final。
                else begin state<=S_SENDING; read_index<=read_index+2'd1; end // 候选消失后继续等待原生sender尾部。
            end // 结束实际Read确认。
            if(i_wr_sent_valid&&write_observe_ok)state<=S_FINAL; // Write唯一实际拍之后才能final。
            if(o_final_valid&&i_final_ready)state<=S_IDLE; // adapter确认final后本地才重新允许command。
            if((state==S_CANDIDATE||state==S_SENDING)&&(candidate_bad||read_bad||write_bad))state<=S_FAILED; // 发送契约违例保留所有权直到共同reset，禁止错误释放。
        end // 结束非reset时钟更新。
    end // 结束完整同步状态机。
endmodule // 结束普通响应formatter；认证算法与顶层自动接入仍未实现。
`default_nettype wire // 恢复编译单元网络默认设置。
