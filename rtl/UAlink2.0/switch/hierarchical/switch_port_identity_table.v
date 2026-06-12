`timescale 1ns/1ps // 定义Port identity table仿真时间单位，不参与综合逻辑。
`default_nettype none // 禁止隐式网络隐藏端口坐标或合法性错误。
module switch_port_identity_table #( // 实现稳定GlobalPortID到物理Station资源的双bank映射。
    parameter integer PORT_WIDTH = 10, // 指定GlobalPortID宽度。
    parameter integer PORT_COUNT = 1024, // 指定最大稳定端口槽数量。
    parameter integer LOOKUP_PORTS = 1, // 附加无状态并行读口数量；旧scalar接口默认行为保持不变。
    parameter integer NUM_GROUPS = 8, // 当前实例实际实现的Group数量；默认完整profile。
    parameter integer TILES_PER_GROUP = 4, // 当前实例实际实现的每Group Tile数量。
    parameter integer PORTS_PER_TILE = 32, // 当前实例实际实现的每Tile local端口数量。
    parameter integer NUM_STATIONS = (NUM_GROUPS*TILES_PER_GROUP*PORTS_PER_TILE)/4 // 实际物理Station数量；每Station固定四个stable slot。
) ( // 管理写、active lookup和commit位于同一管理/fabric同步边界。
    input wire i_clk, // 在上升沿更新shadow entry、错误标记和active bank。
    input wire i_rstn, // 同步低有效复位使全部端口inactive并选择bank0。
    input wire i_shadow_write, // 管理侧写当前非active identity bank。
    input wire [PORT_WIDTH-1:0] i_shadow_global_port, // 选择待更新的稳定GlobalPort槽。
    input wire i_shadow_active, // 声明该shadow逻辑端口是否在新配置中激活。
    input wire [2:0] i_shadow_group, // 提供目标Group坐标并接受稳定ID一致性检查。
    input wire [1:0] i_shadow_tile, // 提供Group内Tile坐标并接受稳定ID一致性检查。
    input wire [4:0] i_shadow_local_port, // 提供Tile内service-unit基础槽。
    input wire [7:0] i_shadow_station, // 提供全局Station编号。
    input wire [3:0] i_shadow_lane_mask, // 提供x4、x2或x1合法lane ownership。
    input wire [2:0] i_shadow_service_units, // 提供该逻辑端口消耗的一、二或四个service unit。
    input wire [1:0] i_station_active_mode, // 指定该entry提交时的Station模式，x4=0、2x2=1、4x1=2。
    input wire i_commit, // 合法且quiescent时与Route SRAM同步切换active bank。
    input wire [PORT_WIDTH-1:0] i_lookup_global_port, // 从Route entry取得待解析GlobalPortID。
    output reg o_lookup_active, // 仅已提交且合法激活的逻辑端口允许后续admission。
    output reg [2:0] o_lookup_group, // 输出已验证Group坐标。
    output reg [1:0] o_lookup_tile, // 输出已验证Group内Tile坐标。
    output reg [4:0] o_lookup_local_port, // 输出已验证Tile内service-unit基础槽。
    output reg [7:0] o_lookup_station, // 输出已验证Station编号。
    output reg [3:0] o_lookup_lane_mask, // 输出已验证lane ownership。
    output reg [2:0] o_lookup_service_units, // 输出已验证逻辑端口物理容量。
    output reg [PORT_COUNT-1:0] o_active_bitmap, // 暴露当前active image所有端口激活状态。
    output reg o_shadow_illegal, // 当前shadow image任一entry非法时阻止commit。
    output reg o_illegal_map_error, // 记录管理侧曾尝试写入非法bifurcation或坐标。
    output wire o_active_bank, // 暴露identity active bank以检查与Route SRAM同步。
    input wire [LOOKUP_PORTS*PORT_WIDTH-1:0] i_lookup_global_port_vec, // 多入口前端并行解析共享active identity image。
    output wire [LOOKUP_PORTS-1:0] o_lookup_active_vec, // 每个附加口独立报告目标端口活动状态。
    output wire [LOOKUP_PORTS*3-1:0] o_lookup_group_vec, // 每口输出三位Group坐标。
    output wire [LOOKUP_PORTS*2-1:0] o_lookup_tile_vec, // 每口输出两位Tile坐标。
    output wire [LOOKUP_PORTS*5-1:0] o_lookup_local_port_vec // 每口输出五位Tile本地端口。
); // 结束Port identity table接口定义。
    reg active_bank_q; // 单bit selector提供整张identity table原子切换。
    reg active_bank0 [0:PORT_COUNT-1]; // bank0逐端口激活状态。
    reg active_bank1 [0:PORT_COUNT-1]; // bank1逐端口激活状态。
    reg illegal_bank0 [0:PORT_COUNT-1]; // bank0逐entry shadow合法性修复状态。
    reg illegal_bank1 [0:PORT_COUNT-1]; // bank1逐entry shadow合法性修复状态。
    reg oob_illegal_bank0; // bank0曾收到无法索引修复的越界shadow写时保持整bank非法。
    reg oob_illegal_bank1; // bank1曾收到无法索引修复的越界shadow写时保持整bank非法。
    reg [2:0] group_bank0 [0:PORT_COUNT-1]; // bank0保存Group坐标。
    reg [2:0] group_bank1 [0:PORT_COUNT-1]; // bank1保存Group坐标。
    reg [1:0] tile_bank0 [0:PORT_COUNT-1]; // bank0保存Group内Tile坐标。
    reg [1:0] tile_bank1 [0:PORT_COUNT-1]; // bank1保存Group内Tile坐标。
    reg [4:0] local_bank0 [0:PORT_COUNT-1]; // bank0保存Tile内基础槽。
    reg [4:0] local_bank1 [0:PORT_COUNT-1]; // bank1保存Tile内基础槽。
    reg [7:0] station_bank0 [0:PORT_COUNT-1]; // bank0保存Station编号。
    reg [7:0] station_bank1 [0:PORT_COUNT-1]; // bank1保存Station编号。
    reg [3:0] lane_bank0 [0:PORT_COUNT-1]; // bank0保存lane mask。
    reg [3:0] lane_bank1 [0:PORT_COUNT-1]; // bank1保存lane mask。
    reg [2:0] units_bank0 [0:PORT_COUNT-1]; // bank0保存service-unit数量。
    reg [2:0] units_bank1 [0:PORT_COUNT-1]; // bank1保存service-unit数量。
    reg [1:0] mode_bank0 [0:PORT_COUNT-1]; // bank0保存每个active entry所属的统一Station模式。
    reg [1:0] mode_bank1 [0:PORT_COUNT-1]; // bank1保存每个active entry所属的统一Station模式。
    localparam [31:0] PORT_COUNT_VALUE = PORT_COUNT; // 使用无符号32位常量统一参数化端口范围比较。
    localparam integer PORT_INDEX_WIDTH = (PORT_COUNT <= 2) ? 1 :
        (PORT_COUNT <= 4) ? 2 : (PORT_COUNT <= 8) ? 3 :
        (PORT_COUNT <= 16) ? 4 : (PORT_COUNT <= 32) ? 5 :
        (PORT_COUNT <= 64) ? 6 : (PORT_COUNT <= 128) ? 7 :
        (PORT_COUNT <= 256) ? 8 : (PORT_COUNT <= 512) ? 9 : 10;
    localparam [2:0] NUM_GROUPS_VALUE = NUM_GROUPS[2:0]; // 收窄拓扑参数用于无符号坐标比较。
    localparam [1:0] TILES_PER_GROUP_VALUE = TILES_PER_GROUP[1:0];
    localparam [4:0] PORTS_PER_TILE_VALUE = PORTS_PER_TILE[4:0];
    wire [9:0] shadow_port_identity; // 将最大十位稳定GlobalPortID零扩展后统一分解。
    wire [31:0] shadow_port_extended; // 将shadow GlobalPortID零扩展为无符号范围比较值。
    wire [31:0] lookup_port_extended; // 将lookup GlobalPortID零扩展为无符号范围比较值。
    wire [31:0] shadow_physical_ordinal; // 将稀疏GlobalPort坐标显式压缩为物理Station数组ordinal。
    wire write_index_valid; // 标记GlobalPortID是否落在本实例实现范围。
    wire lookup_index_valid; // 标记lookup是否落在本实例实现范围。
    wire [PORT_INDEX_WIDTH-1:0] shadow_index; // 范围检查后用于数组访问的定宽shadow索引。
    wire [PORT_INDEX_WIDTH-1:0] lookup_index; // 范围检查后用于数组访问的定宽lookup索引。
    wire coordinate_legal; // 标记显式坐标是否与稳定GlobalPortID一致且存在于本实例拓扑。
    reg bifurcation_legal; // 标记station slot、lane mask和service unit是否匹配模式。
    wire write_map_legal; // 汇总范围、坐标和bifurcation合法性。
    integer reset_index; // 静态复位循环索引只清除valid和illegal元数据。
    integer bitmap_index; // 组合展开active bitmap和shadow非法归约。
    integer sibling_index; // 每个entry仅检查同Station固定四个slot，保持O(4N)复杂度。
    genvar lookup_vector_index; // 静态展开共享identity image的并行组合读口。
    assign shadow_port_identity = {{(10-PORT_WIDTH){1'b0}}, i_shadow_global_port}; // 固定最大profile为十位且测试缩小配置显式零扩展。
    assign shadow_port_extended = {{(32-PORT_WIDTH){1'b0}}, i_shadow_global_port}; // 形成无符号32位shadow端口索引。
    assign lookup_port_extended = {{(32-PORT_WIDTH){1'b0}}, i_lookup_global_port}; // 形成无符号32位lookup端口索引。
    assign shadow_physical_ordinal =
        (({29'd0, i_shadow_group} * TILES_PER_GROUP) + {30'd0, i_shadow_tile}) *
        PORTS_PER_TILE + {27'd0, i_shadow_local_port}; // Group/Tile/Local坐标确定唯一物理slot，不依赖稀疏GlobalPort数值。
    assign write_index_valid = shadow_port_extended < PORT_COUNT_VALUE; // 非二次幂配置下拒绝越界管理写。
    assign lookup_index_valid = lookup_port_extended < PORT_COUNT_VALUE; // 越界lookup固定失败关闭。
    assign shadow_index = i_shadow_global_port[PORT_INDEX_WIDTH-1:0];
    assign lookup_index = i_lookup_global_port[PORT_INDEX_WIDTH-1:0];
    assign coordinate_legal = (NUM_GROUPS >= 1) && (NUM_GROUPS <= 8) &&
        (TILES_PER_GROUP >= 1) && (TILES_PER_GROUP <= 4) &&
        (PORTS_PER_TILE >= 1) && (PORTS_PER_TILE <= 32) &&
        ((PORTS_PER_TILE % 4) == 0) && (NUM_STATIONS >= 1) && (NUM_STATIONS <= 256) &&
        (NUM_STATIONS*4 == NUM_GROUPS*TILES_PER_GROUP*PORTS_PER_TILE) &&
        ((NUM_GROUPS == 8) || (i_shadow_group < NUM_GROUPS_VALUE)) &&
        ((TILES_PER_GROUP == 4) || (i_shadow_tile < TILES_PER_GROUP_VALUE)) &&
        ((PORTS_PER_TILE == 32) || (i_shadow_local_port < PORTS_PER_TILE_VALUE)) &&
        (i_shadow_group == shadow_port_identity[9:7]) && // 检查稳定ID高三位对应Group。
        (i_shadow_tile == shadow_port_identity[6:5]) && // 检查稳定ID中间两位对应Group内Tile。
        (i_shadow_local_port == shadow_port_identity[4:0]) && // 检查低五位对应Tile内槽。
        (shadow_physical_ordinal < NUM_STATIONS*4) &&
        (i_shadow_station == shadow_physical_ordinal[9:2]); // 稀疏GlobalPort显式映射到实际物理Station。
    assign write_map_legal = write_index_valid && (!i_shadow_active || (coordinate_legal && bifurcation_legal)); // inactive entry允许清除而active entry必须完全合法。
    assign o_active_bank = active_bank_q; // 暴露原子identity bank selector。
    generate for(lookup_vector_index=0;lookup_vector_index<LOOKUP_PORTS;lookup_vector_index=lookup_vector_index+1)begin:g_lookup_vec
        wire [PORT_WIDTH-1:0] lookup_id; // 当前附加口的稳定GlobalPort索引。
        wire [PORT_INDEX_WIDTH-1:0] lookup_safe_id; // 越界编码先钳位零，避免组合数组读越界。
        wire lookup_in_range; // 非二次幂端口表尾部编码必须显式失败关闭。
        wire lookup_usable; // 越界或inactive端口统一失败关闭。
        assign lookup_id=i_lookup_global_port_vec[lookup_vector_index*PORT_WIDTH+:PORT_WIDTH];
        assign lookup_in_range={{(32-PORT_WIDTH){1'b0}},lookup_id}<PORT_COUNT_VALUE;
        assign lookup_safe_id=lookup_in_range?lookup_id[PORT_INDEX_WIDTH-1:0]:
            {PORT_INDEX_WIDTH{1'b0}};
        assign lookup_usable=lookup_in_range&&
            ((!active_bank_q&&active_bank0[lookup_safe_id])||(active_bank_q&&active_bank1[lookup_safe_id]));
        assign o_lookup_active_vec[lookup_vector_index]=lookup_usable;
        assign o_lookup_group_vec[lookup_vector_index*3+:3]=!lookup_usable?3'd0:
            (!active_bank_q?group_bank0[lookup_safe_id]:group_bank1[lookup_safe_id]);
        assign o_lookup_tile_vec[lookup_vector_index*2+:2]=!lookup_usable?2'd0:
            (!active_bank_q?tile_bank0[lookup_safe_id]:tile_bank1[lookup_safe_id]);
        assign o_lookup_local_port_vec[lookup_vector_index*5+:5]=!lookup_usable?5'd0:
            (!active_bank_q?local_bank0[lookup_safe_id]:local_bank1[lookup_safe_id]);
    end endgenerate
    always @(*) begin // 组合检查三种冻结Station bifurcation模式。
        bifurcation_legal = 1'b0; // 未识别模式或slot组合默认非法。
        case (i_station_active_mode) // x4、2x2和4x1使用固定lane分组。
            2'd0: begin // x4仅station slot0拥有全部四lane。
                bifurcation_legal = (shadow_physical_ordinal[1:0] == 2'd0) && // 禁止x4在非基础物理槽激活。
                    (i_shadow_lane_mask == 4'b1111) && (i_shadow_service_units == 3'd4); // x4必须声明四个service unit。
            end // 结束x4合法性检查。
            2'd1: begin // 2x2允许slot0拥有lane0/1且slot2拥有lane2/3。
                bifurcation_legal = ((shadow_physical_ordinal[1:0] == 2'd0) && // 检查第一个x2基础槽。
                    (i_shadow_lane_mask == 4'b0011) && (i_shadow_service_units == 3'd2)) || // 第一个x2固定使用低两lane。
                    ((shadow_physical_ordinal[1:0] == 2'd2) && // 检查第二个x2基础槽。
                    (i_shadow_lane_mask == 4'b1100) && (i_shadow_service_units == 3'd2)); // 第二个x2固定使用高两lane。
            end // 结束2x2合法性检查。
            2'd2: begin // 4x1允许四个slot分别拥有唯一lane。
                case (shadow_physical_ordinal[1:0]) // 直接枚举物理slot避免动态移位宽度歧义。
                    2'd0: bifurcation_legal = (i_shadow_lane_mask == 4'b0001) && (i_shadow_service_units == 3'd1); // slot0对应lane0。
                    2'd1: bifurcation_legal = (i_shadow_lane_mask == 4'b0010) && (i_shadow_service_units == 3'd1); // slot1对应lane1。
                    2'd2: bifurcation_legal = (i_shadow_lane_mask == 4'b0100) && (i_shadow_service_units == 3'd1); // slot2对应lane2。
                    2'd3: bifurcation_legal = (i_shadow_lane_mask == 4'b1000) && (i_shadow_service_units == 3'd1); // slot3对应lane3。
                    default: bifurcation_legal = 1'b0; // 完整覆盖后仍保留失败关闭default。
                endcase // 结束4x1 slot解码。
            end // 结束4x1合法性检查。
            default: bifurcation_legal = 1'b0; // 保留模式3为非法配置。
        endcase // 结束Station mode合法性检查。
    end // 结束bifurcation组合检查过程。
    always @(*) begin // 组合读取active identity并生成active bitmap和shadow错误汇总。
        bitmap_index = 0; // 组合循环临时索引在所有分支确定赋值，禁止无意义锁存器。
        sibling_index = 0; // 无active sibling时也清零临时索引，不把工具循环变量误综合为状态。
        o_lookup_active = 1'b0; // 越界或inactive默认拒绝目的端口。
        o_lookup_group = 3'd0; // 无效端口不泄漏未初始化Group数据。
        o_lookup_tile = 2'd0; // 无效端口不泄漏未初始化Tile数据。
        o_lookup_local_port = 5'd0; // 无效端口不泄漏未初始化local槽。
        o_lookup_station = 8'd0; // 无效端口不泄漏未初始化Station数据。
        o_lookup_lane_mask = 4'd0; // 无效端口不占用任何物理lane。
        o_lookup_service_units = 3'd0; // 无效端口不声明任何服务容量。
        o_shadow_illegal = active_bank_q ? oob_illegal_bank0 : oob_illegal_bank1; // 越界写必须阻止对应shadow bank提交。
        o_active_bitmap = {PORT_COUNT{1'b0}}; // 默认全部端口inactive。
        for (bitmap_index = 0; bitmap_index < PORT_COUNT; bitmap_index = bitmap_index + 1) begin // 展开active状态并归约非active bank非法标记。
            if (!active_bank_q) begin // bank0 active时同时观察bank1 shadow错误。
                o_active_bitmap[bitmap_index] = active_bank0[bitmap_index]; // 输出bank0 active bitmap。
                o_shadow_illegal = o_shadow_illegal || illegal_bank1[bitmap_index]; // 任一bank1非法项阻止commit。
                if (active_bank1[bitmap_index]) begin // 仅active shadow entry参与Station整体一致性检查。
                    for (sibling_index = 0; sibling_index < 4; sibling_index = sibling_index + 1) begin // 检查相同Station四个固定slot而不遍历全表。
                        if ((((bitmap_index >> 2) << 2) + sibling_index) < PORT_COUNT && // 保护非四倍数测试配置的尾部数组范围。
                            (((bitmap_index >> 2) << 2) + sibling_index) != bitmap_index && // 跳过entry自身避免lane mask自重叠。
                            active_bank1[((bitmap_index >> 2) << 2) + sibling_index]) begin // 仅比较同Station另一个active entry。
                            if (mode_bank1[bitmap_index] != mode_bank1[((bitmap_index >> 2) << 2) + sibling_index]) // 同Station active entry必须使用同一bifurcation模式。
                                o_shadow_illegal = 1'b1; // 混合x4、2x2或4x1模式时阻止commit。
                            if ((lane_bank1[bitmap_index] & lane_bank1[((bitmap_index >> 2) << 2) + sibling_index]) != 4'b0000) // 任意两个active entry不得重复拥有物理lane。
                                o_shadow_illegal = 1'b1; // lane overlap保持shadow失败关闭。
                        end // 结束当前同Station sibling有效性判断。
                    end // 结束bank1同Station四slot检查。
                end // 结束bank1 active entry整体检查。
            end else begin // bank1 active时同时观察bank0 shadow错误。
                o_active_bitmap[bitmap_index] = active_bank1[bitmap_index]; // 输出bank1 active bitmap。
                o_shadow_illegal = o_shadow_illegal || illegal_bank0[bitmap_index]; // 任一bank0非法项阻止commit。
                if (active_bank0[bitmap_index]) begin // 仅active shadow entry参与Station整体一致性检查。
                    for (sibling_index = 0; sibling_index < 4; sibling_index = sibling_index + 1) begin // 检查相同Station四个固定slot而不遍历全表。
                        if ((((bitmap_index >> 2) << 2) + sibling_index) < PORT_COUNT && // 保护非四倍数测试配置的尾部数组范围。
                            (((bitmap_index >> 2) << 2) + sibling_index) != bitmap_index && // 跳过entry自身避免lane mask自重叠。
                            active_bank0[((bitmap_index >> 2) << 2) + sibling_index]) begin // 仅比较同Station另一个active entry。
                            if (mode_bank0[bitmap_index] != mode_bank0[((bitmap_index >> 2) << 2) + sibling_index]) // 同Station active entry必须使用同一bifurcation模式。
                                o_shadow_illegal = 1'b1; // 混合x4、2x2或4x1模式时阻止commit。
                            if ((lane_bank0[bitmap_index] & lane_bank0[((bitmap_index >> 2) << 2) + sibling_index]) != 4'b0000) // 任意两个active entry不得重复拥有物理lane。
                                o_shadow_illegal = 1'b1; // lane overlap保持shadow失败关闭。
                        end // 结束当前同Station sibling有效性判断。
                    end // 结束bank0同Station四slot检查。
                end // 结束bank0 active entry整体检查。
            end // 结束当前bitmap槽bank选择。
        end // 结束active bitmap和shadow错误组合循环。
        if (lookup_index_valid && !active_bank_q && active_bank0[lookup_index]) begin // bank0命中已激活合法端口。
            o_lookup_active = 1'b1; // 允许目标端口进入后续admission检查。
            o_lookup_group = group_bank0[lookup_index]; // 输出bank0 Group坐标。
            o_lookup_tile = tile_bank0[lookup_index]; // 输出bank0 Tile坐标。
            o_lookup_local_port = local_bank0[lookup_index]; // 输出bank0 local槽。
            o_lookup_station = station_bank0[lookup_index]; // 输出bank0 Station编号。
            o_lookup_lane_mask = lane_bank0[lookup_index]; // 输出bank0 lane ownership。
            o_lookup_service_units = units_bank0[lookup_index]; // 输出bank0 service-unit数量。
        end else if (lookup_index_valid && active_bank_q && active_bank1[lookup_index]) begin // bank1命中已激活合法端口。
            o_lookup_active = 1'b1; // 允许目标端口进入后续admission检查。
            o_lookup_group = group_bank1[lookup_index]; // 输出bank1 Group坐标。
            o_lookup_tile = tile_bank1[lookup_index]; // 输出bank1 Tile坐标。
            o_lookup_local_port = local_bank1[lookup_index]; // 输出bank1 local槽。
            o_lookup_station = station_bank1[lookup_index]; // 输出bank1 Station编号。
            o_lookup_lane_mask = lane_bank1[lookup_index]; // 输出bank1 lane ownership。
            o_lookup_service_units = units_bank1[lookup_index]; // 输出bank1 service-unit数量。
        end // 结束active identity indexed lookup。
    end // 结束identity table组合读取过程。
    always @(posedge i_clk) begin // 单一时序过程更新双bank有效元数据与配置诊断。
        if (!i_rstn) begin // 同步复位使全部未初始化identity data不可见。
            active_bank_q <= 1'b0; // 复位固定选择bank0 active。
            o_illegal_map_error <= 1'b0; // 清除旧非法写诊断。
            oob_illegal_bank0 <= 1'b0; // 复位清除bank0越界shadow诊断。
            oob_illegal_bank1 <= 1'b0; // 复位清除bank1越界shadow诊断。
            for (reset_index = 0; reset_index < PORT_COUNT; reset_index = reset_index + 1) begin // 仅清除active和illegal metadata。
                active_bank0[reset_index] <= 1'b0; // bank0全部端口复位为inactive。
                active_bank1[reset_index] <= 1'b0; // bank1全部端口复位为inactive。
                illegal_bank0[reset_index] <= 1'b0; // bank0复位为无待修复非法项。
                illegal_bank1[reset_index] <= 1'b0; // bank1复位为无待修复非法项。
            end // 结束identity metadata复位循环。
        end else begin // 正常周期仅写非active bank并允许合法commit切换。
            if (i_shadow_write && write_index_valid) begin // 对实现范围内entry执行合法性检查。
                if (!active_bank_q) begin // bank0 active时唯一修改bank1 shadow。
                    active_bank1[shadow_index] <= write_map_legal && i_shadow_active; // 非法或inactive写都保持端口失败关闭。
                    illegal_bank1[shadow_index] <= !write_map_legal; // 合法重写可修复同一entry非法标记。
                    if (write_map_legal) begin // 只有合法entry才更新物理身份字段。
                        group_bank1[shadow_index] <= i_shadow_group; // 写入合法Group坐标。
                        tile_bank1[shadow_index] <= i_shadow_tile; // 写入合法Tile坐标。
                        local_bank1[shadow_index] <= i_shadow_local_port; // 写入合法local槽。
                        station_bank1[shadow_index] <= i_shadow_station; // 写入合法Station编号。
                        lane_bank1[shadow_index] <= i_shadow_lane_mask; // 写入合法lane mask。
                        units_bank1[shadow_index] <= i_shadow_service_units; // 写入合法service-unit数量。
                        mode_bank1[shadow_index] <= i_station_active_mode; // 保存entry所属Station模式供四slot一致性检查。
                    end // 结束bank1合法字段更新。
                end else begin // bank1 active时唯一修改bank0 shadow。
                    active_bank0[shadow_index] <= write_map_legal && i_shadow_active; // 非法或inactive写都保持端口失败关闭。
                    illegal_bank0[shadow_index] <= !write_map_legal; // 合法重写可修复同一entry非法标记。
                    if (write_map_legal) begin // 只有合法entry才更新物理身份字段。
                        group_bank0[shadow_index] <= i_shadow_group; // 写入合法Group坐标。
                        tile_bank0[shadow_index] <= i_shadow_tile; // 写入合法Tile坐标。
                        local_bank0[shadow_index] <= i_shadow_local_port; // 写入合法local槽。
                        station_bank0[shadow_index] <= i_shadow_station; // 写入合法Station编号。
                        lane_bank0[shadow_index] <= i_shadow_lane_mask; // 写入合法lane mask。
                        units_bank0[shadow_index] <= i_shadow_service_units; // 写入合法service-unit数量。
                        mode_bank0[shadow_index] <= i_station_active_mode; // 保存entry所属Station模式供四slot一致性检查。
                    end // 结束bank0合法字段更新。
                end // 结束identity shadow bank选择。
                if (!write_map_legal) o_illegal_map_error <= 1'b1; // 任何非法active映射留下粘滞RAS证据。
            end else if (i_shadow_write) begin // 越界GlobalPortID同样属于非法管理映射。
                o_illegal_map_error <= 1'b1; // 越界写不访问数组且记录失败关闭错误。
                if (!active_bank_q) oob_illegal_bank1 <= 1'b1; // bank0 active时污染的是bank1 shadow。
                else oob_illegal_bank0 <= 1'b1; // bank1 active时污染的是bank0 shadow。
            end // 结束shadow write合法性处理。
            if (i_commit) active_bank_q <= !active_bank_q; // commit FSM单拍同步切换完整identity image。
        end // 结束正常identity状态更新。
    end // 结束Port identity table时序过程。
endmodule // 结束Port identity table实现。
`default_nettype wire // 恢复后续编译单元的默认网络规则。
