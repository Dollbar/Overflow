// 模块 rs_tx_block_formatter：将一拍连续DL数据或已选控制Flit位置转换为并行RS块字段。
// 无状态组合逻辑；上层须保持整条Flit元数据，并只提交o_format_valid有效的完整块组。
module rs_tx_block_formatter #( // 模块 rs_tx_block_formatter 声明并行块格式器
    parameter integer C_BLOCKS = 2 // 参数 C_BLOCKS 指定每拍连续块数，合法值为一、二、四、八
) ( // 开始原生组合块字段端口声明
    input wire [(64*C_BLOCKS)-1:0] i_data, // 输入同拍DL数据，较低编号块位于低位
    input wire [6:0] i_block_index, // 输入本组首块在八十块Flit中的索引
    input wire [2:0] i_flit_kind, // 输入数据、空闲、本地故障、远端故障或掉电种类
    input wire [1:0] i_marker, // 输入无标记、普通AM或快速RAM标记选择
    input wire [7:0] i_am_count, // 输入上层已决定的RAM至AM计数字节，不在本模块调度
    input wire i_link_resiliency, // 输入链路弹性启用标志，决定空闲及故障尾块格式
    input wire i_pl_id, // 输入物理层零或一标识
    output wire o_format_valid, // 输出组合和索引合法标志，非法时禁止向PCS提交
    output wire o_is_data, // 输出本组有效且来自DL数据的标志
    output wire [(2*C_BLOCKS)-1:0] o_sync_headers, // 输出每块独立逻辑同步头，低编号块在低位
    output wire [(64*C_BLOCKS)-1:0] o_payloads // 输出每块六十四位字段，最低字节为D0或块类型
); // 结束原生块格式端口声明
localparam [6:0] C_INDEX_MASK = C_BLOCKS[6:0] - 7'd1; // 常量索引掩码以明确七位运算限定合法并行组边界
localparam [7:0] C_LAST_INDEX = 8'd80 - C_BLOCKS[7:0]; // 常量末组首索引以明确八位运算确保整组均处于同一Flit
localparam C_BLOCK_LIMIT = C_BLOCKS; // 常量保留参数的有符号整数类型并显式命名生成循环上界
wire flag_index_valid; // 信号表示首索引对齐且全部输出块均存在
wire flag_control_valid; // 信号独立判定合法控制来源，避免依赖数据资格和最终有效输出
wire [63:0] wire_base_control; // 信号保存非Start位置的控制块基础字段
genvar g_block; // 生成变量枚举同拍连续输出块
assign flag_index_valid = ((i_block_index & C_INDEX_MASK) == 7'd0) && ({1'b0, i_block_index} <= C_LAST_INDEX); // 检查组边界和八十块上限
assign flag_control_valid = flag_index_valid && (i_flit_kind >= 3'd1) && (i_flit_kind <= 3'd4) && (i_marker <= 2'd2) && !((i_flit_kind == 3'd4) && (i_marker == 2'd2)); // 控制资格独立检查索引、合法种类与掉电标记限制
assign o_is_data = flag_index_valid && (i_flit_kind == 3'd0) && (i_marker == 2'd0); // 数据资格直接由原生输入生成，不经过最终格式有效信号
assign o_format_valid = o_is_data || flag_control_valid; // 两个互斥来源均独立合法时生成最终组有效标志
assign wire_base_control = (i_flit_kind == 3'd1) ? 64'h000000000000001e : (i_flit_kind == 3'd2) ? 64'h000000000100004b : (i_flit_kind == 3'd3) ? 64'h000000000200004b : (i_flit_kind == 3'd4) ? 64'h00000000000000ff : 64'd0; // 根据已选控制种类生成空闲、故障或掉电字段
generate // 开始并行块和非法参数检查生成区域
    if ((C_BLOCKS != 1) && (C_BLOCKS != 2) && (C_BLOCKS != 4) && (C_BLOCKS != 8)) begin : gen_invalid_blocks // 非法并行度必须在展开时明确拒绝
        UALINK_RS_BLOCK_COUNT_INVALID invalid_blocks (); // 实例化明确未定义模块使非法参数展开失败
    end else begin : gen_valid_blocks // 结束非法分支并仅在合法并行度时展开数据通路
    for (g_block = 32'd0; g_block < C_BLOCK_LIMIT; g_block = g_block + 32'd1) begin : gen_blocks // 为每个连续块生成独立数据和控制字段选择
        localparam [7:0] C_BLOCK_OFFSET = g_block[7:0]; // 常量以明确八位记录本块在同拍组内的偏移
        wire [7:0] wire_position; // 信号记录本块在完整Flit中的绝对位置
        wire flag_start; // 信号标记首八个Start块位置
        wire flag_tail; // 信号标记需要PL ID的最后一个Start块
        wire [7:0] wire_count; // 信号仅在首个RAM块承载上层计数，其它Start块为零
        wire [63:0] wire_control; // 信号保存本位置完整控制块字段
        assign wire_position = {1'b0, i_block_index} + C_BLOCK_OFFSET; // 以八位加法保留非法输入越界，避免七位回绕
        assign flag_start = (i_marker != 2'd0) && (wire_position < 8'd8); // 标记序列仅覆盖最先八块
        assign flag_tail = (i_marker != 2'd0) && (wire_position == 8'd79) && (i_link_resiliency || (i_flit_kind == 3'd4)); // 掉电Start尾块无条件携带PL ID，其它Start由弹性配置决定
        assign wire_count = ((i_marker == 2'd2) && (wire_position == 8'd0)) ? i_am_count : 8'd0; // RAM计数字节只进入本Flit的第一块
        assign wire_control = flag_tail ? {7'd0, i_pl_id, 48'd0, 8'h78} : flag_start ? {{7{wire_count}}, 8'h78} : wire_base_control; // 选择末块标识、Start重复计数或基础控制字段
        assign o_sync_headers[(2*g_block)+:2] = {flag_control_valid, o_is_data}; // 两个互斥来源直接组成逻辑头，非法组合自然清零
        assign o_payloads[(64*g_block)+:64] = ({64{o_is_data}} & i_data[(64*g_block)+:64]) | ({64{flag_control_valid}} & wire_control); // 两个互斥合法来源并行掩码后合并，所有非法输入仍输出零
    end // 结束连续块生成分支 gen_blocks
    end // 结束合法并行度数据通路分支 gen_valid_blocks
endgenerate // 结束并行块和非法参数检查生成区域
endmodule // 结束模块 rs_tx_block_formatter
