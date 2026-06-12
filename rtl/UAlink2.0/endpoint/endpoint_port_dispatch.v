`timescale 1ns/1ps // 定义端口分派模块仿真时间精度。
`default_nettype none // 禁止隐式网络隐藏端口连接错误。
module endpoint_port_dispatch #( // 对应用请求做独热分派并公平合并每端口完成。
 parameter integer PORTS=1 // 当前Endpoint合同允许一、二或四个逻辑端口。
)( // 开始同步ready/valid接口定义。
 input wire i_clk, // 所有完成所有权状态使用同一上升沿时钟。
 input wire i_rstn, // 同步低有效复位清除完成owner和轮询位置。
 input wire i_request_valid, // 应用声明当前请求及端口身份有效。
 input wire [1:0] i_request_port, // 应用提供最大四端口的稳定逻辑端口号。
 input wire [PORTS-1:0] i_port_active, // 配置所有者声明实际活动逻辑端口。
 input wire [PORTS-1:0] i_port_ready, // 各逻辑端口声明本沿真实接纳能力。
 output wire o_request_ready, // 只有合法活动目标真实ready时允许应用握手。
 output wire [PORTS-1:0] o_port_valid, // 请求只向选定逻辑端口产生独热valid。
 output wire [1:0] o_selected_port, // 合法候选导出原完整逻辑端口身份。
 output wire o_request_error, // 有效请求使用非法或inactive端口时立即诊断。
 input wire [PORTS-1:0] i_completion_valid, // 每逻辑端口提供独立完成候选。
 output wire [PORTS-1:0] o_completion_ready, // 只有当前winner收到应用ready反馈。
 output wire o_completion_valid, // 合并输出声明当前选定完成有效。
 input wire i_completion_ready, // 应用接纳当前合并完成。
 output wire [1:0] o_completion_port, // 合并输出显式携带winner端口身份。
 output wire o_completion_error, // inactive候选或锁定源丢失时立即诊断。
 output wire o_completion_owned // 反压后声明已锁定的完成源。
); // 结束模块端口定义。
localparam integer PORT_WIDTH=2; // 最大四端口使用固定两位内部身份。
localparam CONFIG_LEGAL=(PORTS==1)||(PORTS==2)||(PORTS==4); // 只允许冻结合同中的逻辑端口数量。
wire request_in_range=({30'd0,i_request_port}<PORTS); // 扩展比较避免截断非活动端口编码。
wire request_eligible=i_request_valid&&request_in_range&&i_port_active[i_request_port]; // 请求必须同时满足范围和活动位。
wire [PORTS-1:0] request_onehot={{(PORTS-1){1'b0}},1'b1}<<i_request_port; // 合法端口转换为参数宽独热选择。
assign o_port_valid=(i_rstn&&CONFIG_LEGAL&&request_eligible)?request_onehot:{PORTS{1'b0}}; // 非法或复位请求不能进入任何端口。
assign o_request_ready=i_rstn&&CONFIG_LEGAL&&request_eligible&&i_port_ready[i_request_port]; // ready只来自选定活动端口。
assign o_selected_port=(i_rstn&&CONFIG_LEGAL&&request_eligible)?i_request_port:2'd0; // 无合法请求时输出确定零。
assign o_request_error=i_rstn&&i_request_valid&&(!CONFIG_LEGAL||!request_in_range||(request_in_range&&!i_port_active[i_request_port])); // 非法端口不分配资源且产生诊断。
reg completion_owner_valid; // 保存反压期间唯一完成winner有效状态。
reg [PORT_WIDTH-1:0] completion_owner; // 保存反压期间唯一完成winner端口。
reg [PORT_WIDTH-1:0] completion_rr; // 保存下一次无owner搜索的轮询起点。
reg [PORT_WIDTH-1:0] completion_selected; // 组合计算当前完成winner端口。
reg completion_found; // 组合声明是否找到合法活动完成。
integer completion_offset; // 遍历全部参数端口的静态循环变量。
integer completion_candidate; // 保存轮询后的有界候选索引。
always @(*)begin // 组合选择owner或从轮询起点寻找首个合法候选。
 completion_offset=0; // 循环索引仅为组合临时量；owner分支也给确定值，禁止综合为无意义锁存器。
 completion_selected=completion_owner; // 默认保持已锁定owner身份。
 completion_found=completion_owner_valid; // owner有效时不允许其它端口替换。
 completion_candidate=0; // 默认候选防止仿真残留值。
 if(!completion_owner_valid)begin // 仅无owner时执行新一轮公平搜索。
  completion_selected={PORT_WIDTH{1'b0}}; // 无候选时输出端口零。
  completion_found=1'b0; // 无owner起始时尚未选中候选。
  for(completion_offset=0;completion_offset<PORTS;completion_offset=completion_offset+1)begin // 最多检查每个端口一次。
   completion_candidate={30'd0,completion_rr}+completion_offset; // 从保存的轮询起点依序搜索。
   if(completion_candidate>=PORTS)completion_candidate=completion_candidate-PORTS; // 一次回绕足以覆盖最多四个候选。
   if(!completion_found&&i_completion_valid[completion_candidate]&&i_port_active[completion_candidate])begin // 只选择有效活动端口。
    completion_selected=completion_candidate[PORT_WIDTH-1:0]; // 保存首个合格候选身份。
    completion_found=1'b1; // 阻止后续候选覆盖winner。
   end // 结束候选命中处理。
  end // 结束全部端口轮询。
 end // 结束无owner选择。
end // 结束完成组合选择。
wire completion_source_valid=completion_found&&i_completion_valid[completion_selected]&&i_port_active[completion_selected]; // 当前winner必须持续保持有效活动状态。
wire completion_fire=i_rstn&&CONFIG_LEGAL&&completion_source_valid&&i_completion_ready; // 合并完成只在真实应用握手时退休。
assign o_completion_valid=i_rstn&&CONFIG_LEGAL&&completion_source_valid; // 非法配置或复位时禁止完成发布。
assign o_completion_port=o_completion_valid?completion_selected:2'd0; // 完成有效时导出对应逻辑端口。
assign o_completion_ready=completion_fire?({{(PORTS-1){1'b0}},1'b1}<<completion_selected):{PORTS{1'b0}}; // 只有winner得到一次退休反馈。
assign o_completion_error=i_rstn&&(!CONFIG_LEGAL||(|(i_completion_valid&~i_port_active))||(completion_owner_valid&&!i_completion_valid[completion_owner])); // inactive伪完成和owner丢失均显式诊断。
assign o_completion_owned=i_rstn&&completion_owner_valid; // 复位期间不发布旧owner状态。
always @(posedge i_clk)begin // 保存反压owner和公平轮询位置。
 if(!i_rstn)begin // 同步复位全部控制状态。
  completion_owner_valid<=1'b0; // 复位不得残留完成所有权。
  completion_owner<={PORT_WIDTH{1'b0}}; // 复位owner身份为端口零。
  completion_rr<={PORT_WIDTH{1'b0}}; // 首次仲裁从端口零开始。
 end else begin // 正常运行更新所有权和轮询位置。
  if(completion_owner_valid)begin // 已锁定winner只等待其真实握手。
   if(completion_fire)begin // 最后一拍应用接纳后释放owner。
    completion_owner_valid<=1'b0; // 当前完成已退休允许下一次仲裁。
    completion_rr<=completion_selected+{{(PORT_WIDTH-1){1'b0}},1'b1}; // 下一次从当前winner后一端口开始。
   end // 结束owner退休处理。
  end else begin // 无owner时处理新候选或即时握手。
   if(completion_fire)begin // 无反压时完成可在本轮直接退休。
    completion_rr<=completion_selected+{{(PORT_WIDTH-1){1'b0}},1'b1}; // 即时握手同样推进公平起点。
   end else if(!completion_owner_valid&&completion_found&&!i_completion_ready)begin // 有效完成遭遇反压时建立owner。
    completion_owner_valid<=1'b1; // 锁定当前winner直到真实握手。
    completion_owner<=completion_selected; // 保存当前winner端口身份。
   end // 结束新候选状态处理。
  end // 结束无owner分支。
 end // 结束正常运行分支。
end // 结束同步状态更新。
endmodule // 结束端口分派模块。
`default_nettype wire // 恢复后续编译单元默认网络规则。
