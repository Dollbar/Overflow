# 原生 Read Response sender 实施契约

实现范围是Common Rev2 §2.5（pp.41–42）、§2.6（pp.43–45）、Table2-15（pp.62–65）、§2.7.8（pp.71–72）、§4.1–4.3（pp.101–104）约束下的本地完整staged发送器。只在候选目录开发，复用生产`upli_credit_bank`、`upli_read_response_channel`与公共parity；不修改其RTL，不声明接收或完整station完成。

参数和接口见候选`interface.json`。候选低619bit为Beat0，其后依次Beat1..3。每Beat高到低固定`{AuthTag64,Src10,Dst10,Tag11,NumBeats2,Data512,Status4,Offset2,Last1,DataError1,TypeInfo2}`；Port2/VC2为整个候选共同上下文，pools[3:0]逐Beat选择信用账户。NumBeats恰为每619bit payload的[523:522]。

首NumBeats=0仅发一个single Beat，完全保留任意Offset/Last；Last=0不表示本模块仍欠尾部，之后可以发送另一Tag，再回到原Tag。本发送器不是Tag事务收集器，不推断single模式总长或退休Tag。

首NumBeats=1..3时发送N=NumBeats+1个staged Beat。所有有效Beat的NumBeats/Tag/Dst/TypeInfo/Status须相同，Offset按0..N-1，只有末Beat的Last=1。未声明尾部的字段与pool位不参加几何或预约判断。AuthTag/Data/DataError逐Beat保存。**Src不参加任何准入比较**：Table2-15 p62明确其为不可用于功能目的的debug字段；各Beat可有不同Src并完整保留，这修正早期station计划中的Src固定profile。

候选格式检查不限制保留状态或供应商命令的业务合法性；上游事务资格负责这些规则、授权inactive时AuthTag=0、请求/响应身份以及跨single Beat的统一status等。普通错误2/3/6/8仍需完整N拍，DataError与status不互相推导，全部数据及parity由实际typed leaf保留。

每个port有VC0..3及pool五账户，恰好一个真实RdRsp bank。开始前按有效pools位分别统计N拍对原VC/pool的需求，与**沿前**余额和初始化确认比较；同沿刚返回信用或刚完成初始化不能旁路。开始只是预约尾部，bank在每个实际原生Beat发出时恰好扣一次。整个有效尾部、VC与pool计划原子保存，接受后候选立即变化不能污染旧响应。

RdRsp有自己的TDM相位，首次实际首Beat可以选择任一合法port，随后每周期按1/2/4port轮转，包括idle。各port可交织独立burst；某port有尾部时该port后续TDM slot必须发送旧尾部且不能接纳新候选。最后尾部当沿保守不接纳同port下一候选，不引入跨port全局busy。

`o_candidate_accepted`表示首Beat真实发出；`o_candidate_error`为组合诊断，条件是reset撤销且candidate_valid且非法port或不合法multi几何。非本时隙、busy、未初始化、余额不足是正常背压，不产生候选错误。非法候选不建立相位、不扣其信用；无关既有尾部照常前进。无原生ready信号；上游候选保持到accepted，完整已接受payload随后可立即变化。

连接由外部真实connection_side提供，credit_connected为本侧rx_connected，beats_connected为双方握手齐备。接口reset必须同域并共同清除银行、TDM、尾部状态和字段输出。`o_credit_error`保留bank注册诊断，`o_credit_error_sticky`在该错误后保持到reset；错误开始可见后关闭新发送及旧尾部，要求上层处理故障并共同reset。本策略不承诺已受损信用事件的撤销、连续性恢复或完整RAS/Isolation；合法返回信用路径才属于本正常发送器功能。信用parity检查在前级guard，不由本模块重新生成后洗掉错误。

验证只用输入刺激、公开原生输出/accepted和公开余额/状态，独立Python账户日志及原始字段队列构成期望，不读取内部DUT寄存器。覆盖1/2/4端口、全部1..4拍/pool计划、错误完整响应、single跨Tag与低Offset Last、差一信用禁止、初始相位与idle、候选噪声、非法multi原子拒绝、reset取消尾部，以及真实尾部/扣账/相位故障。源快照、命令、日志、结果和哈希保存在候选目录，不进行PPA或STA。

候选交付和验证：`build/development/upli_read_response_sender/release/` 提供可安装 RTL 及四个独立测试/参考文件。生产布局命令为 `python3 verification/upli_channels/run_read_response_sender.py --label LABEL --faults`（另以 `python3 -O` 复跑），产物在 `build/verification/upli_channels/read_response_sender/LABEL`。候选 review/freeze 记录最终源码身份、正常与故障矩阵、Yosys 检查以及未覆盖范围；下一步是由主线完成 station TX 集成，不在本候选变更生产接线。
