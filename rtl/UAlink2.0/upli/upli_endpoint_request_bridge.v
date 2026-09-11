`timescale 1ps/1ps // 与实际有序接收SRAM共用同步时钟，不引入仿真延迟。
`default_nettype none // 禁止隐式网络隐藏字段或所有权接线错误。
module upli_endpoint_request_bridge #( // 模块将两个可信有序接收头组装为完整普通请求描述符。
    parameter integer C_NUM_PORTS = 1 // 保留一、二、四端口身份，单holding为保守吞吐选择。
)( // 本地head-transfer与最终request-fire分别释放不同层级的所有权。
    input wire i_clk,i_rstn, // 共同上升沿时钟及同步低有效复位。
    input wire [1:0] i_select_port, // 仅holding空闲时选择下一个请求的物理端口。
    output wire [1:0] o_req_consumer_port, // 接收顺序队列据此选择该端口最早Request。
    input wire i_req_head_valid,i_req_consume_valid, // 实际SRAM头可见与原账户信用归还空间资格。
    input wire [183:0] i_req_payload, // 完整ASI/Auth/Src/Dst/Tag/Num/Addr/Cmd/Len/Attr/Meta容器。
    input wire [1:0] i_req_vc,input wire i_req_pool, // Request原始VC和信用类型不得绑定或覆盖。
    output wire o_req_consumer_ready, // 仅完整holding已预留且请求合法时允许一次原子转移。
    output wire [1:0] o_data_consumer_port, // 已保存Request拥有其全部OrigData尾部端口。
    input wire i_data_head_valid,i_data_consume_valid, // 数据头及其原账户归还预约资格。
    input wire [579:0] i_data_payload, // 完整Data512/ByteEn64/Offset2/Last/Error。
    input wire [1:0] i_data_vc,input wire i_data_pool, // 数据VC必须匹配所有者，Pool允许逐拍变化。
    output wire o_data_consumer_ready, // 每次完整复制一个头才释放该OrigData账户。
    output wire o_request_valid,input wire i_request_ready, // 下一级完整请求接受只释放本地holding。
    output wire [1:0] o_request_port,o_request_vc, // 保存的完整端口与请求VC。
    output wire o_request_pool, // 保存的原UPLI Request信用类型，不等于未来TL Pool。
    output wire [183:0] o_request_payload, // 原始请求身份和所有属性不被重新编码或截断。
    output wire [2047:0] o_request_data, // 低512位为相对首个自然对齐Beat，未声明尾部为零。
    output wire [255:0] o_request_be, // 四个相对Beat的完整ByteEn，不在此改成区域BE。
    output wire [3:0] o_request_poison,o_request_data_pools, // 逐拍保存poison与原账户类型，包括Full无意义BE的原字段。
    output wire o_busy,o_error // busy是容量背压，error是局部非法头诊断而非标准RAS状态码。
); // 结束单holding请求组装模块的完整接口。
    reg r_busy,r_complete,r_fault; // 已预约、整笔齐套及局部协议停用状态。
    reg [1:0] r_port,r_vc;reg r_pool; // 原Request的端口与账户字段。
    reg [183:0] r_request; // 任何后续输入噪声都不能改写保存的身份。
    reg [2047:0] r_data;reg [255:0] r_be; // 完整最大普通请求数据与相对ByteEn容量。
    reg [3:0] r_poison,r_pools; // 每拍Error与Pool逐位保存，不合并成整笔Status。
    reg [2:0] r_expected,r_received; // 一至四拍的预期数及已经实际复制的拍数。
    wire [5:0] command,length;wire [7:0] address_offset; // 只从冻结Request容器解析普通几何字段。
    wire [8:0] byte_count,region_end;wire [2:0] beat_count;wire [5:0] unused_rounding; // 显式扩宽避免256字节和跨Beat计算截断。
    wire has_data,request_legal,data_legal,request_bad,data_bad; // 几何校验与当前所有者的尾部校验相互独立。
    wire req_transfer,data_transfer,request_fire; // 三种事件不共用信用返还路径。
    assign command=i_req_payload[27:22]; // 低28位依次为命令、长度、属性和元数据。
    assign length=i_req_payload[21:16]; // LEN是四字节数量减一。
    assign address_offset=i_req_payload[35:28]; // 几何仅检查低八位，完整57位地址仍由r_request原样保存。
    assign byte_count=({3'd0,length}+9'd1)<<2; // 长度范围为四至二百五十六字节。
    assign region_end={1'b0,address_offset[7:0]}+byte_count; // 普通请求不能跨越自然256字节区域。
    assign {beat_count,unused_rounding}={3'd0,address_offset[5:0]}+byte_count+9'd63; // 自然64字节Beat覆盖数采用向上取整。
    assign has_data=(command==6'h28)||(command==6'h29); // 仅普通Write与WriteFull使用此模块数据组装路径。
    assign request_legal=({30'd0,i_select_port}<C_NUM_PORTS)&&(address_offset[1:0]==2'd0)&&(region_end<=9'd256)&& // 端口和普通请求几何必须同时合法。
        (((command==6'h03)&&(i_req_payload[86:85]==2'd0))|| // Read的NumBeats是零，不表示其未来Response只有一拍。
        (has_data&&({1'b0,i_req_payload[86:85]}+3'd1==beat_count)&& // 带数据请求显式Num必须与地址覆盖拍数一致。
        ((command!=6'h29)||((address_offset[5:0]==6'd0)&&(byte_count[5:0]==6'd0))))); // Full仅允许完整自然64字节倍数。
    assign data_legal=(i_data_vc==r_vc)&&(i_data_payload[3:2]==r_received[1:0])&& // 原VC及升序Offset共同确认当前请求所有者。
        (i_data_payload[1]==(r_received+3'd1==r_expected)); // Last恰好出现在预期最终拍，不将poison当结束条件。
    assign request_bad=!r_busy&&i_req_head_valid&&!request_legal; // 空闲时非法可见头停用，不因缺返还空间丢诊断。
    assign data_bad=r_busy&&!r_complete&&i_data_head_valid&&!data_legal; // 仅已有带数据Request拥有当前数据头的检查职责。
    assign o_error=i_rstn&&(r_fault||request_bad||data_bad); // 局部停用保持至共同reset，由外层负责真实Drop策略。
    assign o_req_consumer_port=r_busy?r_port:i_select_port; // 忙碌时外部选择变化不能影响保存上下文。
    assign o_data_consumer_port=r_port; // Data永远取已经保存的Request端口。
    assign o_req_consumer_ready=i_rstn&&!r_fault&&!r_busy&&i_req_head_valid&&request_legal; // 一次Request转移预留整笔最大holding容量。
    assign o_data_consumer_ready=i_rstn&&!r_fault&&r_busy&&!r_complete&&i_data_head_valid&&data_legal; // 仅接纳尚未保存且合法的下一拍。
    assign req_transfer=o_req_consumer_ready&&i_req_consume_valid; // 实际SRAM与归还记录同沿退休，不能仅凭head-valid。
    assign data_transfer=o_data_consumer_ready&&i_data_consume_valid; // 完整复制一拍后允许底层原账户返还。
    assign o_request_valid=i_rstn&&!r_fault&&r_complete; // 整笔齐套前下一级不可看到有效事务。
    assign request_fire=o_request_valid&&i_request_ready; // 最终下一级接受没有第二次信用返还。
    assign o_request_port=r_port;assign o_request_vc=r_vc;assign o_request_pool=r_pool; // 完整保存原本地身份与账户字段。
    assign o_request_payload = r_request; // 字段保持到实际下一级请求接纳。
    assign o_request_data = r_data; // 原字节位置与所有无效lane保留，不按BE遮蔽数据。
    assign o_request_be=r_be;assign o_request_poison=r_poison;assign o_request_data_pools=r_pools; // 相对Beat元数据随全部数据共同保持。
    assign o_busy=i_rstn&&r_busy; // 同步状态在reset期间不发布旧有效容量承诺。
    always @(posedge i_clk) begin // 所有本地holding状态只在真实所有权转移沿更新。
        if(!i_rstn)begin // 同步reset取消未提交事务而不制造任何完成。
            r_busy<=1'b0; // reset_busy：取消已经复制但尚未下游接纳的Request。
            r_complete <= 1'b0; // reset_complete：取消背压中的完整descriptor。
            r_fault<=1'b0;r_port<=2'd0;r_vc<=2'd0;r_pool<=1'b0; // 新epoch没有旧身份或局部错误状态。
            r_request<=184'd0;r_data<=2048'd0;r_be<=256'd0;r_poison<=4'd0;r_pools<=4'd0; // 防止无效输出残留被误用为新请求内容。
            r_expected<=3'd0;r_received<=3'd0; // 新epoch没有旧数据尾部计数。
        end else begin // 正常周期保留未发生实际转移的全部内容。
            if(request_bad||data_bad)r_fault<=1'b1; // 无法处理的本地协议错误禁止继续误配队列。
            if(req_transfer)begin // 整个Request头及其账户一次保存，预留完整后续数据空间。
                r_busy<=1'b1;r_complete<=!has_data; // Read立即齐套，Write等待全部真实Data转移。
                r_port<=i_select_port;r_vc<=i_req_vc;r_pool<=i_req_pool;r_request<=i_req_payload; // 不从后来的Request或selector重新取得身份。
                r_data<=2048'd0;r_be<=256'd0;r_poison<=4'd0;r_pools<=4'd0; // 未声明尾部始终为零，不继承上笔事务的数据。
                if(has_data)r_expected<=beat_count; // Write保存完整预计拍数，后续只能逐拍消费。
                else r_expected<=3'd0; // Read没有OrigData，不预约虚构空拍。
                r_received<=3'd0; // 新Request的实际数据转移计数从零开始。
            end // 结束完整Request原子保存。
            if(data_transfer)begin // 只修改当前已验证Offset对应的一份完整Beat。
                r_data[r_received[1:0]*512 +: 512]<=i_data_payload[579:68]; // 保留全部512位，包括被ByteEn屏蔽的lane。
                r_be[r_received[1:0]*64 +: 64]<=i_data_payload[67:4]; // ByteEn低64位始终属于相对Beat0。
                r_poison[r_received[1:0]]<=i_data_payload[0];r_pools[r_received[1:0]]<=i_data_pool; // poison和pool允许各拍不同。
                r_received<=r_received+3'd1;r_complete<=(r_received+3'd1==r_expected); // 只有最后真实转移才能公开完整descriptor。
            end // 结束完整数据头原子复制。
            if(request_fire)begin // 仅释放本地holding，不再消费输入头或归还任何信用。
                r_busy<=1'b0;r_complete<=1'b0; // 保守下一沿才接受新Request，不依赖同沿未来空间。
            end // 结束下游所有权转交。
        end // 结束共同reset与正常行为分支。
    end // 结束唯一时序状态更新过程。
    generate if((C_NUM_PORTS!=1)&&(C_NUM_PORTS!=2)&&(C_NUM_PORTS!=4))begin:gen_invalid // 不允许非法端口配置静默别名。
        upli_endpoint_request_bridge_invalid_ports Invalid_Inst(); // 未定义模块使非法参数在elaboration明确失败。
    end endgenerate // 结束参数有效性保护。
endmodule // 结束原生有序接收至完整请求holding的桥接模块。
`default_nettype wire // 恢复编译单元外部默认网络类型。
