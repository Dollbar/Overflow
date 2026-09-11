// 模块 rs_tx_frame_control：保持整条Flit元数据并按实际块组提交推进八十块序列。
// 命令接纳与帧完成分离；本地背压接口不表示物理PCS允许停止发送。
module rs_tx_frame_control #( // 模块 rs_tx_frame_control 声明同步帧控制和真实格式器顶层
    parameter integer C_BLOCKS = 2 // 参数 C_BLOCKS 指定每拍连续块数，合法值为一、二、四、八
) ( // 开始原生帧命令、数据与块组端口声明
    input wire i_clk, // 输入唯一上升沿工作时钟
    input wire i_rstn, // 输入同步低有效复位，同时屏蔽所有有效握手事件
    input wire i_cmd_valid, // 输入帧命令有效标志
    input wire [2:0] i_cmd_kind, // 输入数据、空闲、本地故障、远端故障或掉电种类
    input wire [1:0] i_cmd_marker, // 输入无标记、普通AM或快速RAM选择
    input wire [7:0] i_cmd_count, // 输入上层已确定的原始RAM计数字节
    input wire i_cmd_resiliency, // 输入本帧链路弹性配置
    input wire i_cmd_pl_id, // 输入本帧物理层标识
    input wire i_data_valid, // 输入本组DL数据有效标志，须保持至实际消费
    input wire [(64*C_BLOCKS)-1:0] i_data, // 输入连续DL块数据，最低编号块在低位
    input wire i_block_ready, // 输入本地块组接收就绪，不在本层制定PCS暂停政策
    output wire o_cmd_ready, // 输出当前空闲或旧帧最后组实际提交时的命令槽就绪
    output wire o_cmd_accept, // 输出合法命令的实际捕获事件
    output wire o_cmd_reject, // 输出可用命令槽上非法命令的拒绝事件
    output wire o_active, // 输出当前已有帧在处理，复位期间无效
    output wire o_data_ready, // 输出活跃Data帧的数据源就绪
    output wire o_data_take, // 输出本组DL数据实际消费事件
    output wire o_block_valid, // 输出本组完整格式化块有效标志
    output wire o_block_take, // 输出本组块实际传输事件
    output wire o_block_last, // 输出有效末组标志，停顿时不表示完成
    output wire o_frame_done, // 输出完整八十块Flit的最后组实际提交事件
    output wire [6:0] o_block_index, // 输出活跃帧当前组首索引，等待时保持
    output wire [(2*C_BLOCKS)-1:0] o_sync_headers, // 输出真实格式器同步头，无效组清零
    output wire [(64*C_BLOCKS)-1:0] o_payloads, // 输出真实格式器块字段，无效组清零
    output wire o_active_raw, // 输出未屏蔽的真实活跃寄存值，仅供内部末级资格合成
    output wire o_frame_done_raw // 输出未屏蔽的真实完整组接收资格，不代替公开实际提交
); // 结束原生同步帧接口声明
localparam [6:0] C_LAST_GROUP = 7'd80 - C_BLOCKS[6:0]; // 常量计算最后一个完整并行组的首索引
localparam [6:0] C_GROUP_STEP = C_BLOCKS[6:0]; // 常量以七位记录每次真实提交的索引增量
reg r_active; // 寄存器保存当前帧活跃状态
reg [6:0] r_index; // 寄存器保存当前帧下一组首索引
reg [2:0] r_kind; // 寄存器保存整帧种类
reg [1:0] r_marker; // 寄存器保存整帧标记选择
reg [7:0] r_count; // 寄存器保存整帧原始RAM计数
reg r_resiliency; // 寄存器保存整帧链路弹性配置
reg r_pl_id; // 寄存器保存整帧物理层标识
wire flag_command_valid; // 信号表示原生命令种类和标记组合受支持
wire flag_source_valid; // 信号表示活跃帧的控制字段或DL数据已就绪
wire flag_format_valid; // 信号接收真实格式器的完整组合法判断
wire flag_format_data; // 信号接收真实格式器的Data资格判断
wire [(2*C_BLOCKS)-1:0] wire_format_sync; // 信号保存只由捕获元数据和索引决定的完整同步头
wire [(64*C_BLOCKS)-1:0] wire_format_payload; // 信号保存真实格式器输出，在末级统一限定当前源有效
assign flag_command_valid = (i_cmd_kind <= 3'd4) && (i_cmd_marker <= 2'd2) && !((i_cmd_kind == 3'd0) && (i_cmd_marker != 2'd0)) && !((i_cmd_kind == 3'd4) && (i_cmd_marker == 2'd2)); // 独立拒绝保留种类、Data标记和掉电RAM
assign flag_source_valid = i_rstn && r_active && ((r_kind != 3'd0) || i_data_valid); // 只有活跃控制帧或已有DL数据的帧可以提供有效组
assign o_active_raw = r_active; // 内部资格直接来自真实活跃寄存器，不产生额外状态
assign o_frame_done_raw = r_active && ((r_kind != 3'd0) || i_data_valid) && flag_format_valid && i_block_ready && (r_index == C_LAST_GROUP); // 内部完成资格完整保留真实格式合法性、末组和接收握手
assign o_active = i_rstn && r_active; // 复位期间不向外报告活跃帧
assign o_sync_headers = flag_source_valid ? wire_format_sync : {(2*C_BLOCKS){1'b0}}; // 在完整同步头形成后按当前源有效清零无效输出
assign o_payloads = flag_source_valid ? wire_format_payload : {(64*C_BLOCKS){1'b0}}; // 在完整数据和控制字段形成后按当前源有效清零无效输出
assign o_block_valid = flag_source_valid && flag_format_valid; // 实际格式器确认完整合法组后才发布有效
assign o_block_take = o_block_valid && i_block_ready; // 只有有效且被接收的块组计为传输
assign o_block_last = o_block_valid && (r_index == C_LAST_GROUP); // 末组必须有真实有效输出，缺Data时不提前报告
assign o_frame_done = o_block_take && o_block_last; // 整帧完成严格要求最后组实际提交
assign o_cmd_ready = i_rstn && (!r_active || o_frame_done); // 空闲或完成旧帧时提供下一命令槽
assign o_cmd_accept = i_cmd_valid && o_cmd_ready && flag_command_valid; // 捕获合法命令，不在命令周期提前消费Data
assign o_cmd_reject = i_cmd_valid && o_cmd_ready && !flag_command_valid; // 明确拒绝非法命令，不污染旧帧元数据
assign o_data_ready = i_rstn && r_active && (r_kind == 3'd0) && i_block_ready; // Data源就绪与有效块提交分离
assign o_data_take = o_block_take && flag_format_data; // 只有真实Data块传输才消费上游数据
assign o_block_index = o_active ? r_index : 7'd0; // 活跃帧输出当前索引，空闲和复位清零
always @(posedge i_clk) begin // 在唯一真实时钟上更新完整帧状态
    if (!i_rstn) begin // 同步复位取消未完成帧且不声称已经发送
        r_active <= 1'b0; // 复位清除帧活跃状态
        r_index <= 7'd0; // 复位清除块组索引
        r_kind <= 3'd0; // 复位清除捕获种类
        r_marker <= 2'd0; // 复位清除捕获标记
        r_count <= 8'd0; // 复位清除原始RAM计数
        r_resiliency <= 1'b0; // 复位清除链路弹性配置
        r_pl_id <= 1'b0; // 复位清除物理层标识
    end else if (o_cmd_accept) begin // 旧帧完成同沿优先捕获下一帧，实现连续帧衔接
        r_active <= 1'b1; // 标记新帧已接纳
        r_index <= 7'd0; // 新帧始终从第零组开始
        r_kind <= i_cmd_kind; // 捕获并保持整帧种类
        r_marker <= i_cmd_marker; // 捕获并保持整帧标记
        r_count <= i_cmd_count; // 捕获并保持原始RAM计数，不在本层调度
        r_resiliency <= i_cmd_resiliency; // 捕获并保持整帧弹性配置
        r_pl_id <= i_cmd_pl_id; // 捕获并保持整帧物理层标识
    end else if (o_frame_done) begin // 无新合法命令时完成旧帧并进入空闲
        r_active <= 1'b0; // 最后组实际提交后清除活跃状态
        r_index <= 7'd0; // 空闲索引回到零，元数据保持至下一次捕获或复位
    end else if (o_block_take) begin // 非最后组仅在真实传输后前进
        r_index <= r_index + C_GROUP_STEP; // 按实际并行度推进首块索引
    end // 结束同步复位、命令捕获和传输推进优先级
end // 结束完整帧状态时钟过程
generate // 开始合法参数保护和真实格式器实例区域
    if ((C_BLOCKS != 1) && (C_BLOCKS != 2) && (C_BLOCKS != 4) && (C_BLOCKS != 8)) begin : gen_invalid_blocks // 在展开时明确拒绝非法并行度
        UALINK_RS_FRAME_BLOCK_COUNT_INVALID invalid_blocks (); // 实例化未定义模块使非法参数立即失败
    end else begin : gen_valid_blocks // 仅为合法并行度连接实际块格式器
        rs_tx_block_formatter #(.C_BLOCKS(C_BLOCKS)) u_formatter ( // 实例化已验证的真实并行块格式器
            .i_data(i_data), // 连接当前实际DL数据组
            .i_block_index(r_index), // 连接捕获帧的当前组首索引
            .i_flit_kind(r_kind), // 真实格式器只解码整帧捕获种类，源有效在输出端限定
            .i_marker(r_marker), // 连接整帧保持的标记选择
            .i_am_count(r_count), // 连接整帧保持的原始RAM计数字节
            .i_link_resiliency(r_resiliency), // 连接整帧保持的弹性配置
            .i_pl_id(r_pl_id), // 连接整帧保持的物理层标识
            .o_format_valid(flag_format_valid), // 接收实际完整块组合法判断
            .o_is_data(flag_format_data), // 接收实际Data来源资格
            .o_sync_headers(wire_format_sync), // 接收真实格式器完整同步头供末级有效限定
            .o_payloads(wire_format_payload) // 接收真实格式器全部块字段供末级有效限定
        ); // 结束实际并行格式器实例
    end // 结束合法参数实例分支
endgenerate // 结束参数检查与格式器实例区域
endmodule // 结束模块 rs_tx_frame_control
