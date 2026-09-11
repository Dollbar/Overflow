# Endpoint request context 候选执行与审查

本模块已实现完整descriptor上下文保存与有序交付，尚未连接backend执行器或网络响应退休。生产布局文件均在候选release下；不修改生产。接口源为 `docs/upli_endpoint_context_execution.md`、`docs/upli_endpoint_ip_top_execution.md` 与真实 `rtl/upli/upli_endpoint_request_bridge.v`。本次没有新增规范字段或协议码。


仅保存已有普通请求descriptor的上下文表，不接backend、不重新分配网络Tag。依据生产 `docs/upli_endpoint_context_execution.md` 的Source Accelerator本地station/port共享Tag域，以及 `upli_endpoint_ip_top_execution.md` 的request_context建议。本地station是opaque配置身份，默认8位，不声称为新UPLI线字段；多远端Src经同一port混流不在首轮唯一性声明中。

参数：CAPACITY=4，C_NUM_PORTS=1/2/4，C_STATION_WIDTH=8；本地slot位宽由CAPACITY派生。输入是完整bridge descriptor：station、port、VC、pool、Request184、Data2048、relativeBE256、poison4、data_pools4。Tag为原Request[97:87]，仅参与station/port/Tag查重，Src/VC/pool/命令变化不能绕过该本地唯一域。

request valid/ready实际fire才保存全部字段。FIFO只保存slot索引，确保issue按实际接纳顺序交付；issue valid/ready只标记已交付，仍保持表项到外部合法release。issue输出完整原始descriptor及本地token，网络Tag不得被token替代。无同沿释放槽借用：满表为正常背压，已issue表项仍计占用。统一同步reset取消所有未完成上下文。

release只是外部可信所有权完成事件；本表不能证明backend执行或响应尾部真正完成。未知/未issue/重复release不得释放或修改其它槽。冻结采用{generation,slot}本地token，generation默认8位且按槽分配递增、模2^width回绕。它仅拒绝通常的旧代次事件，不提供回绕后的无限ABA保证；调用方必须在最终release后不再产生旧事件。统一reset同时取消上下游旧epoch，不能单独重置本表后接纳旧完成。不会把有限本地token误称完整LinkDown/epoch协议。

TDD先独立生命周期向量+接口壳失败，再实现RTL；1/2/4port、全字段高位/随机值、station隔离/Tag高位/跨kind冲突、满表/issue背压/同沿事件、reset和实际bridge→context联动。桥的完整holding与context表是两个真实容量所有者：bridge仅在表实际ready时转交，不因issue或release重复消费原head。


接口采用 `i_request_* / o_request_ready / o_request_token` 接纳、`o_issue_* / i_issue_ready` 交付、`i_release_valid/token / o_release_ready` 最终所有权释放。Request184完整保留Meta[7:0]、Attr[15:8]、Len[21:16]、Cmd[27:22]、Address[84:28]、Num[86:85]、Tag[97:87]、Dst[107:98]、Src[117:108]、Auth[181:118]、ASI[183:182]。伴随字段station/port/VC/pool、2048位Data、256位relative BE、4位poison与各Beat pool均原样保存。随机字段保留测试不证明所有随机编码都是合法请求。

CAPACITY可配置1..16、默认4；本次功能/静态矩阵固定CAPACITY4、ports1/2/4。station宽默认8、generation默认8，可配置宽度1..32及1..16，额外宽度未做全矩阵证明。派生slot/count宽度禁止错误覆盖。local token不作为网络Tag，有限代次回绕和共同reset都不能保证旧事件永久不可重现。

## 实测

`red_first`：1/2/4端口占位RTL均compile0/run1，独立ready期望检出尚未实现。`final_matrix`：三端口unit分别297/299/299行，每行16项全部输出，4752/4784/4784项比较通过；三配置g2001、Verilator -Wall、Yosys hierarchy/proc/check均退出0。参考模型用dictionary/deque维护独立生命周期，不读RTL状态或用RTL编码器产生期望。

同标签真实request_bridge联动各9次descriptor接纳、8次issue、7次release；另2条（1条已issue、1条未issue）共同reset取消。各配置9个Req head与9个Data head实际转移、675项独立检查、73个issue背压周期。覆盖满4表、第五条真实bridge holding、issue不归还容量、FIFO顺序、反序release、同Tag新token、旧token拒绝及共同reset后恢复。trusted head BFM直接驱动真实bridge，此处没有SRAM、connection或信用初始化器，不能把head计数称实际credit return，也不声称原生Endpoint/backend因果闭环。该层无原账户信用输出，issue和release无法产生额外原head信用事件。

五个实际RTL fault为Tag高位翻转、issue错误释放active、删除generation核对、删除station查重限定、错误FIFO读指针。`final_tag_fault` 同时被unit与真实bridge检查器检出，其他 `fault_issue_release/token/station/order` 均compile0/run1。首次 `fault_tag` 已实际触发bridge MISMATCH，但runner错误匹配FAIL令整包false；证据保留，修正marker后重新运行final_tag_fault，未将未激活故障计为有效。

局部技能报告 `skill/final` 为2 errors/13 warnings，不能声称技能全绿：SEQ_BLOCKING_ASSIGN定位时序块内reset for循环的整数索引赋值，实际状态寄存器全为非阻塞；ASSIGN_WIDTH将184位数组读的条件输出误推为1位，三种EDA均确认合法且全位仿真通过。全局技能安装检查因缺少agents-md-generator/scripts/manage_docs.py退出1，保留HOLD。未修改技能或添加例外消除报告。

## 可复现命令及后续边界

独立候选：`python3 build/development/upli_endpoint_request_context/run.py --label NEW --integration --static`。
安装release后：`python3 verification/upli_channels/run_request_context.py --label NEW --integration --static`。故障例：追加 `--ports 4 --fault tag`。需要本机Icarus/vvp、Verilator、Yosys；真实bridge联动依赖同工程生产request_bridge，明确不需KD28。结果写 `build/verification/upli_channels/request_context/NEW`，含完整源快照、vectors、命令/退出码/log/hash与result.json。独立release_replay已实际运行正常及Tag故障，布局无候选路径运行时依赖。

后续接入前必须由系统确定release的实际响应尾部/执行完成所有者；不能用issue替代完成。单Source Accelerator本地station/port/Tag域之外的远端Src混流必须重新评审唯一域，不应静默套用当前查重。Auth/poison只是可信字段保存，无认证、恢复或错误执行决策。全表使用寄存器；没有KD28映射、PPA或形式证明。请先审核freeze.json精确文件再安装，历史RED/static误报保持可见。
