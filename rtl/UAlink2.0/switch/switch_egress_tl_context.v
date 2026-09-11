`timescale 1ns/1ps // 同一时钟域内的分类提交和整记录交接。
`default_nettype none // 禁止字段或握手漏接。
module switch_egress_tl_context #( // 只提供真实分类与显式后续assembler边界。
 parameter integer PORTS=4,VCS=4,TOKEN_WIDTH=8 // 完整物理端口、VC和透明身份宽度。
)( // 不提供伪造的prepared源输出或信用端口。
 input wire i_clk,i_rstn, // 同步低有效共同reset。
 input wire [PORTS-1:0] i_auth,i_valid,i_response,i_last,i_ready, // auth在reset epoch内稳定，下游ready独立。
 input wire [PORTS*544-1:0] i_record, // 完整原始header24/aux6/msg2/flit512。
 input wire [PORTS*TOKEN_WIDTH-1:0] i_token, // 原本地包身份完整保存。
 input wire [PORTS*2-1:0] i_vc, // 本地资源VC不代替Control字段解码。
 output wire [PORTS-1:0] o_ready,o_valid,o_error,o_error_sticky,o_captured,o_retired, // 记录捕获、分类提交和下游退休明确分离。
 output wire [PORTS*544-1:0] o_record, // 与本记录同沿保存的完整字段或上下文观察。
 output wire [PORTS*TOKEN_WIDTH-1:0] o_token, // 与本记录同沿保存的完整字段或上下文观察。
 output wire [PORTS*2-1:0] o_vc, // 与本记录同沿保存的完整字段或上下文观察。
 output wire [PORTS*1-1:0] o_response, // 与本记录同沿保存的完整字段或上下文观察。
 output wire [PORTS*1-1:0] o_last, // 与本记录同沿保存的完整字段或上下文观察。
 output wire [PORTS*6-1:0] o_classes, // 与本记录同沿保存的完整字段或上下文观察。
 output wire [PORTS*7-1:0] o_pending_before, // 与本记录同沿保存的完整字段或上下文观察。
 output wire [PORTS*73-1:0] o_be_before, // 与本记录同沿保存的完整字段或上下文观察。
 output wire [PORTS*584-1:0] o_metadata_before, // 与本记录同沿保存的完整字段或上下文观察。
 output wire [PORTS*80-1:0] o_demands, // 与本记录同沿保存的完整字段或上下文观察。
 output wire [PORTS*80-1:0] o_releases, // 与本记录同沿保存的完整字段或上下文观察。
 output wire [PORTS*1-1:0] o_store // 与本记录同沿保存的完整字段或上下文观察。
 ); // 结束不含prepared/TL/DL实际发送功能的边界接口。
 localparam [31:0] C_PORTS=PORTS; // 常量展开全部物理端口。
 localparam [2:0] C_VCS=VCS[2:0]; // 两位VC零扩展比较。
 genvar p; // 各端口的TL上下文互相独立。
 generate // 配置保护和真实上下文实例。
 if((PORTS!=1&&PORTS!=2&&PORTS!=4)||(VCS!=1&&VCS!=2&&VCS!=4)||TOKEN_WIDTH<1)begin:gen_invalid // 非法配置不默认截短。
  switch_egress_tl_context_invalid_parameters Invalid_Inst(); // 明确展开失败。
 end // 结束参数检查。
 for(p=0;p<C_PORTS;p=p+1)begin:gen_port // 每port一个holding和一个既有TL上下文。
  reg reg_valid,reg_error; // 旧可信holding允许排空，错误只阻止新的捕获。
  wire ctx_allowed,ctx_store; // 现有真实分类准入及store观察。
  wire [2:0] ctx_lower,ctx_upper; // 两半类别来自实际TL classifier。
  wire [6:0] ctx_pending; // 当前记录之前的待处理半flit数。
  wire [72:0] ctx_be; // 当前序列中BE位置。
  wire [583:0] ctx_metadata; // 原字段Data/BE关联的既有队列元数据。
  wire [79:0] ctx_demands,ctx_releases; // 仅保留提议，不连接任何信用银行。
  wire unused_ctx_taken,unused_ctx_rejected; // 实例反馈只作一致性观察，不创建另一握手。
  wire legal; // 既有TL profile和配置VC同时合法。
  reg [544-1:0] reg_record; // 与完整记录一同捕获，反压期间保持。
  reg [TOKEN_WIDTH-1:0] reg_token; // 与完整记录一同捕获，反压期间保持。
  reg [2-1:0] reg_vc; // 与完整记录一同捕获，反压期间保持。
  reg [1-1:0] reg_response; // 与完整记录一同捕获，反压期间保持。
  reg [1-1:0] reg_last; // 与完整记录一同捕获，反压期间保持。
  reg [6-1:0] reg_classes; // 与完整记录一同捕获，反压期间保持。
  reg [7-1:0] reg_pending_before; // 与完整记录一同捕获，反压期间保持。
  reg [73-1:0] reg_be_before; // 与完整记录一同捕获，反压期间保持。
  reg [584-1:0] reg_metadata_before; // 与完整记录一同捕获，反压期间保持。
  reg [80-1:0] reg_demands; // 与完整记录一同捕获，反压期间保持。
  reg [80-1:0] reg_releases; // 与完整记录一同捕获，反压期间保持。
  reg [1-1:0] reg_store; // 与完整记录一同捕获，反压期间保持。
  assign legal=ctx_allowed&&({1'b0,i_vc[p*2+:2]}<C_VCS); // 不从packet类别推断标准字段含义。
  assign o_error[p]=i_rstn&&!reg_error&&i_valid[p]&&!legal; // 当前拒绝不部分提交context。
  assign o_error_sticky[p]=i_rstn&&reg_error; // 共同reset之前不自动恢复分类。
  assign o_ready[p]=i_rstn&&!reg_error&&(!reg_valid||i_ready[p])&&(!i_valid[p]||legal); // 一个完整holding容量，非法记录不捕获。
  assign o_captured[p]=i_valid[p]&&o_ready[p]; // 唯一TL context提交事件。
  assign o_valid[p]=i_rstn&&reg_valid; // 新非法输入不撤销旧可信输出。
  assign o_retired[p]=o_valid[p]&&i_ready[p]; // 下游退休不再次推进分类或返还信用。
  tl_receive_context u_context( // 复用已有真实tenure、sequence和元数据逻辑。
   .i_clk(i_clk),.i_rstn(i_rstn),.i_commit(o_captured[p]),.i_auth(i_auth[p]), // 只有本holding实际保存原记录才推进。
   .i_lower(i_record[p*544+:256]),.i_msg(i_record[p*544+512+:2]), // 原record的明确TL切片。
   .i_type0(i_record[p*544+:8]),.i_type1(i_record[p*544+256+:8]), // Message类型来自各半最低八位。
   .o_allowed(ctx_allowed),.o_taken(unused_ctx_taken),.o_rejected(unused_ctx_rejected), // 非法分类仅本地诊断，不生成Drop。
   .o_lower(ctx_lower),.o_upper(ctx_upper),.o_demands(ctx_demands),.o_releases(ctx_releases), // 保存两半的真实上下文提议。
   .o_store(ctx_store),.o_pending(ctx_pending),.o_be(ctx_be),.o_metadata(ctx_metadata)); // 未重建完整prepared Control/Data/Auth。
  assign o_record[p*544+:544]=reg_record&{544{o_valid[p]}}; // 无效时确定为零，合法输出完整保存。
  assign o_token[p*TOKEN_WIDTH+:TOKEN_WIDTH]=reg_token&{TOKEN_WIDTH{o_valid[p]}}; // 无效时确定为零，合法输出完整保存。
  assign o_vc[p*2+:2]=reg_vc&{2{o_valid[p]}}; // 无效时确定为零，合法输出完整保存。
  assign o_response[p*1+:1]=reg_response&{1{o_valid[p]}}; // 无效时确定为零，合法输出完整保存。
  assign o_last[p*1+:1]=reg_last&{1{o_valid[p]}}; // 无效时确定为零，合法输出完整保存。
  assign o_classes[p*6+:6]=reg_classes&{6{o_valid[p]}}; // 无效时确定为零，合法输出完整保存。
  assign o_pending_before[p*7+:7]=reg_pending_before&{7{o_valid[p]}}; // 无效时确定为零，合法输出完整保存。
  assign o_be_before[p*73+:73]=reg_be_before&{73{o_valid[p]}}; // 无效时确定为零，合法输出完整保存。
  assign o_metadata_before[p*584+:584]=reg_metadata_before&{584{o_valid[p]}}; // 无效时确定为零，合法输出完整保存。
  assign o_demands[p*80+:80]=reg_demands&{80{o_valid[p]}}; // 无效时确定为零，合法输出完整保存。
  assign o_releases[p*80+:80]=reg_releases&{80{o_valid[p]}}; // 无效时确定为零，合法输出完整保存。
  assign o_store[p*1+:1]=reg_store&{1{o_valid[p]}}; // 无效时确定为零，合法输出完整保存。
  always @(posedge i_clk)begin // 记录和所有观察元数据原子更新。
   if(!i_rstn)begin // 清除所有旧epoch的holding和错误。
    reg_valid<=1'b0;reg_error<=1'b0; // reset取消不是退休。
    reg_record<= {544{1'b0}}; // 不向下一epoch暴露旧字段。
    reg_token<= {TOKEN_WIDTH{1'b0}}; // 不向下一epoch暴露旧字段。
    reg_vc<= {2{1'b0}}; // 不向下一epoch暴露旧字段。
    reg_response<= {1{1'b0}}; // 不向下一epoch暴露旧字段。
    reg_last<= {1{1'b0}}; // 不向下一epoch暴露旧字段。
    reg_classes<= {6{1'b0}}; // 不向下一epoch暴露旧字段。
    reg_pending_before<= {7{1'b0}}; // 不向下一epoch暴露旧字段。
    reg_be_before<= {73{1'b0}}; // 不向下一epoch暴露旧字段。
    reg_metadata_before<= {584{1'b0}}; // 不向下一epoch暴露旧字段。
    reg_demands<= {80{1'b0}}; // 不向下一epoch暴露旧字段。
    reg_releases<= {80{1'b0}}; // 不向下一epoch暴露旧字段。
    reg_store<= {1{1'b0}}; // 不向下一epoch暴露旧字段。
   end else begin // 旧holding可正常排空，错误不能重新接纳。
    if(o_error[p])reg_error<=1'b1; // 第一拒绝后保持本地fail-stop。
    if(o_retired[p])reg_valid<=1'b0; // 只释放本地一项存储。
    if(o_captured[p])begin // 同拍出入允许完整新记录替换。
     reg_valid<=1'b1; // 本次真实存储已取得record所有权。
     reg_record<= i_record[p*544+:544]; // 保存沿前提议，不使用更新后的上下文。
     reg_token<= i_token[p*TOKEN_WIDTH+:TOKEN_WIDTH]; // 保存沿前提议，不使用更新后的上下文。
     reg_vc<= i_vc[p*2+:2]; // 保存沿前提议，不使用更新后的上下文。
     reg_response<= i_response[p]; // 保存沿前提议，不使用更新后的上下文。
     reg_last<= i_last[p]; // 保存沿前提议，不使用更新后的上下文。
     reg_classes<= {ctx_upper,ctx_lower}; // 保存沿前提议，不使用更新后的上下文。
     reg_pending_before<= ctx_pending; // 保存沿前提议，不使用更新后的上下文。
     reg_be_before<= ctx_be; // 保存沿前提议，不使用更新后的上下文。
     reg_metadata_before<= ctx_metadata; // 保存沿前提议，不使用更新后的上下文。
     reg_demands<= ctx_demands; // 保存沿前提议，不使用更新后的上下文。
     reg_releases<= ctx_releases; // 保存沿前提议，不使用更新后的上下文。
     reg_store<= ctx_store; // 保存沿前提议，不使用更新后的上下文。
    end // 结束实际捕获。
   end // 结束正常更新。
  end // 结束同步寄存。
 end // 结束全部独立端口。
 endgenerate // 结束有限配置。
endmodule // 结束显式未完成prepared重建的可执行分类边界。
`default_nettype wire // 恢复后续编译单元默认规则。
