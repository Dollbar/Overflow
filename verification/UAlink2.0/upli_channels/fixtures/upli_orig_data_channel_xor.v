// Native UPLI OrigData transmit fields; Common 2.0 Table 2-21, sections 2.5/2.7.8/3.1.1.
// 日期2026-09-11；共享 sender 负责信用、连接及连续 burst，此层组合生成保护码。
`default_nettype none // 显式声明所有连接，避免拼写错误形成隐式网络。
module upli_orig_data_channel ( // 原生 OrigData 输出模块不插入握手或流水延迟。
    input wire i_valid, // 共享 sender 确实发送的本拍有效事件。
    input wire [1:0] i_port_id, // 当前端口的两位 TDM 标识。
    input wire [511:0] i_data, // 完整五百一十二位数据，包含未选字节。
    input wire [63:0] i_byte_en, // 每字节一个使能，共六十四位。
    input wire [1:0] i_offset, // 从零开始的相对数据 Beat 索引。
    input wire i_last, // 本次事务最后一个数据 Beat。
    input wire i_error, // 原始数据 poison 标志，不能重新解释为本地 ready。
    input wire [1:0] i_vc, // 保持首次 Request 的虚拟通道。
    input wire i_pool, // 本拍实际使用共享池信用的标志。
    output wire o_orig_data_valid, // 对外原生字段或对应的偶校验保护码。
    output wire [1:0] o_orig_data_port_id, // 对外原生字段或对应的偶校验保护码。
    output wire [511:0] o_orig_data, // 对外原生字段或对应的偶校验保护码。
    output wire [63:0] o_orig_data_byte_en, // 对外原生字段或对应的偶校验保护码。
    output wire [1:0] o_orig_data_offset, // 对外原生字段或对应的偶校验保护码。
    output wire o_orig_data_last, // 对外原生字段或对应的偶校验保护码。
    output wire o_orig_data_error, // 对外原生字段或对应的偶校验保护码。
    output wire [1:0] o_orig_data_vc, // 对外原生字段或对应的偶校验保护码。
    output wire o_orig_data_pool, // 对外原生字段或对应的偶校验保护码。
    output wire o_orig_data_valid_parity, // 对外原生字段或对应的偶校验保护码。
    output wire [7:0] o_orig_data_parity, // 对外原生字段或对应的偶校验保护码。
    output wire o_orig_data_byte_en_parity, // 对外原生字段或对应的偶校验保护码。
    output wire o_orig_data_fields_parity // 对外原生字段或对应的偶校验保护码。
); // 结束完整原生字段端口声明。
    assign o_orig_data_valid = i_valid; // 保持共享 sender 确实发送的本拍有效事件，不改变有效或数据。
    assign o_orig_data_port_id = i_port_id; // 保持当前端口的两位 TDM 标识，不改变有效或数据。
    assign o_orig_data = i_data; // 保持完整五百一十二位数据，包含未选字节，不改变有效或数据。
    assign o_orig_data_byte_en = i_byte_en; // 保持每字节一个使能，共六十四位，不改变有效或数据。
    assign o_orig_data_offset = i_offset; // 保持从零开始的相对数据 Beat 索引，不改变有效或数据。
    assign o_orig_data_last = i_last; // 保持本次事务最后一个数据 Beat，不改变有效或数据。
    assign o_orig_data_error = i_error; // 保持原始数据 poison 标志，不能重新解释为本地 ready，不改变有效或数据。
    assign o_orig_data_vc = i_vc; // 保持保持首次 Request 的虚拟通道，不改变有效或数据。
    assign o_orig_data_pool = i_pool; // 保持本拍实际使用共享池信用的标志，不改变有效或数据。
    assign o_orig_data_valid_parity = i_valid; // 单位有效信号与其校验位保持偶数个置位。
    assign o_orig_data_byte_en_parity = ^i_byte_en; // 独立保护六十四个字节使能，依据第三章明确语义。
    assign o_orig_data_fields_parity = ^{i_last,i_error,i_offset,i_port_id,i_vc,i_pool}; // 九位控制包含 poison 和信用选择。
    genvar gen_group; // 八个固定六十四位分组分别生成数据偶校验。
    generate // 常量展开全部数据保护分组，不形成动态选择。
        for (gen_group = 32'd0; gen_group < 32'd8; gen_group = gen_group + 32'd1) begin : gen_data_parity // 每组覆盖所有八个字节，包括禁用字节。
            assign o_orig_data_parity[gen_group] = ^i_data[gen_group*64 +: 64]; // 数据保护不以 ByteEn 掩蔽。
        end // 结束八个独立数据保护分组。
    endgenerate // 结束固定数据奇偶校验硬件展开。
endmodule // 结束 upli_orig_data_channel 原生字段与保护码输出层。
`default_nettype wire // 恢复后续独立编译单元的默认网络设置。
