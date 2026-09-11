`timescale 1ns/1ps // 本地typed交接与上游packet流使用共同采样沿。
`default_nettype none // 拆分后的每个原始字段必须明确接线。
module switch_egress_repack #( // 出口本地记录typed交接模块，不冒充TL prepared字段解包器。
    parameter integer PORTS=4, VCS=4, TOKEN_WIDTH=8 // 物理端口、VC配置和透明包身份宽度。
)( // 完整544位记录的既有布局固定，不允许隐式截短。
    input wire i_clk, i_rstn, // 上升沿和同步低有效共同epoch复位。
    input wire [PORTS-1:0] i_valid, // 上游实际每物理egress有效word。
    input wire [PORTS*544-1:0] i_data, // 原记录包含本地DLheader24、aux6、msg2、TLflit512。
    input wire [PORTS-1:0] i_last, // 上游packet末word，不能从TLmsg猜测。
    input wire [PORTS*TOKEN_WIDTH-1:0] i_token, // 原队列保存的包身份。
    input wire [PORTS*2-1:0] i_vc, // 原scheduler实际VC。
    input wire [PORTS-1:0] i_response, // 原scheduler实际Request或Response类别。
    output wire [PORTS-1:0] o_ready, // 本级真实存储接纳，与TL source capture不同。
    input wire [PORTS-1:0] i_ready, // 下游typed消费者原子接受全部字段的资格。
    output wire [PORTS-1:0] o_valid, // 本级已保存完整记录的有效观察。
    output wire [PORTS*24-1:0] o_local_dl_header, // 原本地DLheader完整24位，不重新编码hop状态。
    output wire [PORTS*6-1:0] o_record_aux, // 原记录六个额外位完整保留，不假定恒零。
    output wire [PORTS*2-1:0] o_tl_msg, // 原TL flit的两位msg标签，不作为packet类别替代。
    output wire [PORTS*512-1:0] o_tl_flit, // 原已打包TL flit全512位，非prepared源control组。
    output wire [PORTS-1:0] o_last, // 与本级保存记录相同的原packet末边界。
    output wire [PORTS*TOKEN_WIDTH-1:0] o_token, // 包身份与全部typed字段原子传递。
    output wire [PORTS*2-1:0] o_vc, // 保存的实际VC，反压期间不读新输入。
    output wire [PORTS-1:0] o_response, // 保存的实际类别，反压期间不读新输入。
    output wire [PORTS-1:0] o_input_error // 有效输入的非法VC仅阻止该新记录，不吞掉旧输出。
); // 结束明确未直连tl_tx_prepared的本地交接边界。
    localparam [31:0] C_PORTS=PORTS; // 静态展开每个独立物理端口。
    localparam [2:0] C_VCS=VCS[2:0]; // VC完整两位零扩展比较，四VC不发生截断。
    genvar p; // 每个物理端口独立一项elastic寄存。
    generate // 配置保护和独立存储结构。
        if (((PORTS!=1)&&(PORTS!=2)&&(PORTS!=4))||((VCS!=1)&&(VCS!=2)&&(VCS!=4))||(TOKEN_WIDTH<1)) begin : gen_invalid // 只支持已声明的端口和字段形状。
            switch_egress_repack_parameters_invalid Invalid_Inst (); // 非法参数必须在elaboration失败。
        end // 结束参数保护。
        for (p=32'd0; p<C_PORTS; p=p+32'd1) begin : gen_ports // 各端口没有交叉ready或共享记录。
            reg reg_valid,reg_last,reg_response; // 保存记录有效及原packet属性。
            reg [543:0] reg_record; // 完整本地record一次原子捕获。
            reg [TOKEN_WIDTH-1:0] reg_token; // 与记录同行的真实身份。
            reg [1:0] reg_vc; // 与记录同行的真实VC。
            assign o_input_error[p]=i_rstn&&i_valid[p]&&({1'b0,i_vc[p*2+:2]}>=C_VCS); // 未valid时不解释VC噪声。
            assign o_ready[p]=i_rstn&&!o_input_error[p]&&(!reg_valid||i_ready[p]); // 空槽或旧记录同沿出队允许真实接纳。
            assign o_valid[p]=i_rstn&&reg_valid; // 新非法输入不能撤销先前可信输出。
            assign o_local_dl_header[p*24+:24]=reg_record[543:520]&{24{o_valid[p]}}; // 精确保留最高24位本地header。
            assign o_record_aux[p*6+:6]=reg_record[519:514]&{6{o_valid[p]}}; // 六个非TLflit记录位不得遗失。
            assign o_tl_msg[p*2+:2]=reg_record[513:512]&{2{o_valid[p]}}; // 原两位flit消息类别原样保存。
            assign o_tl_flit[p*512+:512]=reg_record[511:0]&{512{o_valid[p]}}; // 完整512位flit不重排大小端。
            assign o_last[p]=reg_last&&o_valid[p]; // 无效时packet末边界归零。
            assign o_token[p*TOKEN_WIDTH+:TOKEN_WIDTH]=reg_token&{TOKEN_WIDTH{o_valid[p]}}; // 无效时身份观察归零。
            assign o_vc[p*2+:2]=reg_vc&{2{o_valid[p]}}; // 无效时VC观察归零。
            assign o_response[p]=reg_response&&o_valid[p]; // 本地类别不从msg字段重新推断。
            always @(posedge i_clk) begin // 原子入队、出队和同拍替换共享一个状态所有者。
                if (!i_rstn) begin // 共同复位取消全部在途typed记录。
                    reg_valid<=1'b0;reg_record<=544'd0; // 没有旧payload残留。
                    reg_last<=1'b0;reg_response<=1'b0;reg_token<={TOKEN_WIDTH{1'b0}};reg_vc<=2'd0; // 元数据与payload一起复位。
                end else begin // 正常沿只依据明确握手更新。
                    if (o_valid[p]&&i_ready[p]) reg_valid<=1'b0; // 旧可信记录被真实下游接纳。
                    if (i_valid[p]&&o_ready[p]) begin // 完整新record及所有sideband一次捕获。
                        reg_valid<=1'b1; // 同拍入出时新记录保持占用。
                        reg_record<=i_data[p*544+:544]; // 全部544位一起保存。
                        reg_token<=i_token[p*TOKEN_WIDTH+:TOKEN_WIDTH]; // 原token不能跟随下一候选变化。
                        reg_vc<=i_vc[p*2+:2]; // 原VC不能跟随下一候选变化。
                        reg_last<=i_last[p];reg_response<=i_response[p]; // 类别和packet边界与同一word一致。
                    end // 结束真实新记录接纳。
                end // 结束正常沿状态更新。
            end // 结束本端口elastic寄存状态。
        end // 结束全部独立物理出口。
    endgenerate // 结束有限配置结构。
endmodule // 结束全宽本地记录typed交接模块。
`default_nettype wire // 恢复后续独立源码默认网络规则。
