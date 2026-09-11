`timescale 1ns/1ps // 仿真时间单位。
// 本地出口包调度；容量预约和归还完全由上游队列负责。
module switch_egress_scheduler #( // 独立物理出口调度模块。
 parameter integer PORTS=4, // 独立物理出口数。
 parameter integer VCS=4, // 每类虚拟通道数。
 parameter integer DATA_WIDTH=544, // 每拍完整数据宽度。
 parameter integer TOKEN_WIDTH=8, // 透明传递的队列标签宽度。
 parameter integer RSP_BURST_MAX=2 // 连续响应包配额；请求可见时达到配额须服务请求。
)( // 结束当前声明或控制作用域。
 input wire i_clk,input wire i_rstn, // 所有权状态在上升沿更新。
 input wire [2*VCS*PORTS-1:0] i_valid, // 独立物理出口数。
 input wire [2*VCS*PORTS*DATA_WIDTH-1:0] i_data, // 独立物理出口数。
 input wire [2*VCS*PORTS-1:0] i_last, // 独立物理出口数。
 input wire [2*VCS*PORTS*TOKEN_WIDTH-1:0] i_token, // 独立物理出口数。
 input wire [PORTS-1:0] i_ready, // 独立物理出口数。
 output wire [2*VCS*PORTS-1:0] o_ready, // 独立物理出口数。
 output wire [PORTS-1:0] o_valid, // 独立物理出口数。
 output wire [PORTS*DATA_WIDTH-1:0] o_data, // 独立物理出口数。
 output wire [PORTS-1:0] o_last, // 独立物理出口数。
 output wire [PORTS*TOKEN_WIDTH-1:0] o_token, // 独立物理出口数。
 output wire [PORTS*2-1:0] o_vc, // 独立物理出口数。
 output wire [PORTS-1:0] o_response, // 独立物理出口数。
 output wire [2*VCS*PORTS-1:0] o_selected, // 独立物理出口数。
 output wire [PORTS-1:0] o_owned // 独立物理出口数。
); // 结束当前声明或控制作用域。
 localparam [31:0] C_PORTS=PORTS; // 物理出口数作为展开常量。
 localparam [31:0] C_DOMAINS=2*VCS; // 两类虚拟通道的总数。
 localparam [31:0] C_VCS=VCS; // 扫描边界明确为常量。
 localparam [3:0] C_LIMIT=RSP_BURST_MAX[3:0]; // 饱和配额。
 generate // 结束当前声明或控制作用域。
 if((PORTS!=1&&PORTS!=2&&PORTS!=4)||(VCS!=1&&VCS!=2&&VCS!=4)||DATA_WIDTH<1||TOKEN_WIDTH<1||RSP_BURST_MAX<1||RSP_BURST_MAX>15)begin:gen_bad // 显式限定受支持的参数范围。
  INVALID_SCHEDULER_PARAMETERS invalid_parameters(); // 非法参数令展开失败，禁止静默使用。
 end // 结束当前声明或控制作用域。
 endgenerate // 结束当前声明或控制作用域。
 genvar ge,gs; // 静态展开出口及候选槽位。
 generate for(ge=0;ge<C_PORTS;ge=ge+1)begin:gen_egress // 各物理出口独立保存调度状态。
  reg reg_owned,reg_response; // 首次阻塞即锁定，不等待首拍接纳。
  reg [1:0] reg_vc,reg_req_next,reg_rsp_next; // 保存包所属VC和两类下一轮询起点。
  reg [3:0] reg_rsp_run; // 已完成响应包数采用饱和计数。
  reg found_req,found_rsp,chosen,chosen_response; // 组合扫描结果与最终候选。
  reg [1:0] req_vc,rsp_vc,chosen_vc; // 组合扫描结果与最终候选。
  integer scan,index,slot; // 仅用于有限组合扫描和扁平索引。
  wire selected_valid,selected_last; // 选中队头的有效和包末信号。
  always @* begin // 组合选择不依赖下游ready，避免仲裁反馈。
   found_req=1'b0;found_rsp=1'b0;req_vc=2'd0;rsp_vc=2'd0; // 扫描输出先赋默认值，避免锁存器。
   index=0;slot=0; // 从轮询指针计算当前类的候选位置。
   for(scan=0;scan<C_VCS;scan=scan+1)begin // 从类内轮询起点扫描所有虚拟通道。
    index=({30'd0,reg_req_next}+scan)%VCS; // 从轮询指针计算当前类的候选位置。
    if(!found_req&&i_valid[index*PORTS+ge])begin found_req=1'b1;req_vc=index[1:0];end // 保存首个有效请求VC。
    index=({30'd0,reg_rsp_next}+scan)%VCS; // 从轮询指针计算当前类的候选位置。
    if(!found_rsp&&i_valid[(VCS+index)*PORTS+ge])begin found_rsp=1'b1;rsp_vc=index[1:0];end // 保存首个有效响应VC。
   end // 结束当前声明或控制作用域。
   chosen=1'b0;chosen_response=1'b0;chosen_vc=2'd0; // 无候选时不选择任何队列。
   if(reg_owned)begin chosen=1'b1;chosen_response=reg_response;chosen_vc=reg_vc;end // 在包内始终使用保存的类别与VC。
   else if(found_rsp&&(!found_req||reg_rsp_run<C_LIMIT))begin chosen=1'b1;chosen_response=1'b1;chosen_vc=rsp_vc;end // 有界响应优先，不允许请求长期饥饿。
   else if(found_req)begin chosen=1'b1;chosen_vc=req_vc;end // 响应配额耗尽或无响应时选择请求。
   slot=((chosen_response?VCS:0)+{30'd0,chosen_vc})*PORTS+ge; // 转换为类别、VC、出口顺序的输入索引。
  end // 结束当前声明或控制作用域。
  assign selected_valid=i_rstn&&chosen&&i_valid[slot]; // 统一复位屏蔽有效输出。
  assign selected_last=i_last[slot]; // 仅有效握手时解释包末。
  assign o_valid[ge]=selected_valid; // 透传选中队头；无有效数据时公共字段清零。
  assign o_data[ge*DATA_WIDTH+:DATA_WIDTH]=selected_valid?i_data[slot*DATA_WIDTH+:DATA_WIDTH]:{DATA_WIDTH{1'b0}}; // 透传选中队头；无有效数据时公共字段清零。
  assign o_token[ge*TOKEN_WIDTH+:TOKEN_WIDTH]=selected_valid?i_token[slot*TOKEN_WIDTH+:TOKEN_WIDTH]:{TOKEN_WIDTH{1'b0}}; // 透传选中队头；无有效数据时公共字段清零。
  assign o_last[ge]=selected_valid&&selected_last; // 透传选中队头；无有效数据时公共字段清零。
  assign o_vc[ge*2+:2]=selected_valid?chosen_vc:2'd0; // 透传选中队头；无有效数据时公共字段清零。
  assign o_response[ge]=selected_valid&&chosen_response; // 透传选中队头；无有效数据时公共字段清零。
  assign o_owned[ge]=i_rstn&&reg_owned; // 透传选中队头；无有效数据时公共字段清零。
  for(gs=0;gs<C_DOMAINS;gs=gs+1)begin:gen_slot // 将唯一选择展开回队列顺序。
   localparam integer SLOT_INDEX=gs%VCS; // 固定槽位身份用于组合选择。
   localparam [1:0] SLOT_VC=SLOT_INDEX[1:0]; // 固定槽位身份用于组合选择。
   localparam SLOT_RESPONSE=(gs>=VCS); // 固定槽位身份用于组合选择。
   assign o_selected[gs*PORTS+ge]=i_rstn&&chosen&&(chosen_vc==SLOT_VC)&&(chosen_response==SLOT_RESPONSE); // 唯一选中槽位获得ready，气泡仍保持选择。
   assign o_ready[gs*PORTS+ge]=o_selected[gs*PORTS+ge]&&i_ready[ge]; // 唯一选中槽位获得ready，气泡仍保持选择。
  end // 结束当前声明或控制作用域。
  always @(posedge i_clk)begin // 同步维护包所有权及公平性状态。
   if(!i_rstn)begin // 共同复位开始新队列及调度纪元。
    reg_owned<=1'b0;reg_response<=1'b0;reg_vc<=2'd0; // 清除旧包身份。
    reg_req_next<=2'd0;reg_rsp_next<=2'd0;reg_rsp_run<=4'd0; // 复位轮询起点与响应配额。
   end else if(selected_valid)begin // 气泡不更新任何包所有权。
    if(i_ready[ge]&&selected_last)begin // 只有真实末拍握手结束整包。
     reg_owned<=1'b0; // 释放物理出口所有权，不生成容量事件。
     if(chosen_response)begin // 完成响应包后维护响应轮询和配额。
      reg_rsp_next<=({30'd0,chosen_vc}==C_VCS-32'd1)?2'd0:chosen_vc+2'd1; // 响应VC轮询仅在实际包末推进。
      if(reg_rsp_run<C_LIMIT)reg_rsp_run<=reg_rsp_run+4'd1; // 响应计数饱和，不发生回绕。
     end else begin // 非完成分支保持或建立包锁。
      reg_req_next<=({30'd0,chosen_vc}==C_VCS-32'd1)?2'd0:chosen_vc+2'd1; // 请求VC轮询仅在实际包末推进。
      reg_rsp_run<=4'd0; // 完成请求包重新开放响应配额。
     end // 结束当前声明或控制作用域。
    end else begin // 非完成分支保持或建立包锁。
     reg_owned<=1'b1;reg_response<=chosen_response;reg_vc<=chosen_vc; // 首拍阻塞或接受非末拍均锁定整包。
    end // 结束当前声明或控制作用域。
   end // 结束当前声明或控制作用域。
  end // 结束当前声明或控制作用域。
 end endgenerate // 结束当前声明或控制作用域。
endmodule // 结束当前声明或控制作用域。
