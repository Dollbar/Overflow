# 原生 Read Response/Data 发送字段层实施契约

本契约依据本地授权的 UALink Common Specification Rev 2.0 正文，以自主释义记录实施边界。当前库存 `upli_read_response_channel` 仍为 planned，其原职责还包括完整接收和传输管理；本轮候选仅实现完整原生字段的组合TX输出与公共parity接线，不能据此宣称完整库存职责、station或IP已完成。

## 来源与字段

§2.7.5、Table 2-15（pp.62–64）明确Read Response/Data每个有效Beat同时携带响应控制和**512bit数据**，不是只有响应header的通道。有效信息合计624bit，其中AuthTag64、Data512、控制48；另有valid1及11个发送parity位。

| 原生字段 | 位宽 | 候选i_/o_后缀 |
|---|---:|---|
| RdRspVld | 1 | valid |
| RdRspPortID | 2 | port |
| RdRspAuthTag | 64 | auth_tag |
| RdRspSrcPhysAccID | 10 | src |
| RdRspDstPhysAccID | 10 | dst |
| RdRspTag | 11 | tag |
| RdRspNumBeats | 2 | num_beats |
| RdRspData | 512 | data |
| RdRspStatus | 4 | status |
| RdRspOffset | 2 | offset |
| RdRspLast | 1 | last |
| RdRspDataError | 1 | data_error |
| RdRspTypeInfo | 2 | type_info |
| RdRspVC | 2 | vc |
| RdRspPool | 1 | pool |

候选`upli_read_response_channel`不含clk、参数或内部状态，保留`i_rstn`组合屏蔽和上述全部typed字段。`o_valid = i_rstn && i_valid`；valid为0时所有字段及发送parity输出确定为零。有效字段不因status、data_error、type_info、offset或num_beats而丢弃、截断或重写。没有原生ByteEn、Address或ready端口；接收侧的信用返回不是附加在这个TX字段层中的数据字段。

本地测试打包按高到低`{port,auth_tag,src,dst,tag,num_beats,data,status,offset,last,data_error,type_info,vc,pool}`，共624bit。该顺序是测试容器约定，非规范序列化格式。未来若传输控制器把port/VC/Pool独立管理，其payload可明确采用其余619bit；本轮不擅自冻结未来helper接口。

## 真实parity接线

使用既有公共`upli_parity`、`CHANNEL_KIND=1`，不再复制parity算法。原语低48个control bit严格按高到低`{type_info2,tag11,status4,offset2,last1,num_beats2,vc2,src10,dst10,port2,data_error1,pool1}`放置，高20bit清零；auth输入接实际输出AuthTag64，data输入接实际输出Data512。

| 本层输出 | 保护内容 | 公共原语位 |
|---|---|---|
| o_valid_parity | valid；每周期接收方应检查 | 0 |
| o_auth_tag_parity | 完整AuthTag64 | 3 |
| o_data_parity[7:0] | 每64bit一组，bit0对应Data[63:0] | 11:4 |
| o_control_parity | 完整48bit控制组 | 1 |

Table 2-15（p.64）和§3.1.1（pp.85–86）要求即使数据lane因请求地址/长度不被应用使用，或本Beat已带DataError，实际驱动的全部512bit仍受对应parity保护。字段层不能将poison数据或错误status数据从校验输入清零。接收校验只在对应valid条件下解释其他parity；valid保护自身每周期有效。本TX叶模块将公共原语check_enable绑0，只生成发送保护，不把没有接收parity接口的输出伪称为已检查通过。

**正文待澄清项：**Table 2-15 p.62将RdRspAuthTag列为Completer驱动，p.64的RdRspAuthTagParity行却将Driver列写为Originator。保护内容和有效条件明确，但驱动方标注不一致。当前本地TX层按父任务确认生成所驱动AuthTag的偶校验，供实际发送连接使用；这属于明确实现选择，不声称已获得规范勘误或解决该表的方向矛盾。

## 传输与事务管理边界

§2.5（pp.41–42）：Read Response自身首次有效Beat建立TDM相位，支持1/2/4端口，并持续轮转；该相位独立于Req/OrigData和Write Response。字段层不得另建相位或自行发Beat；`i_valid`只能来自真实发送准入事件。

§2.6（pp.43–45）、§4.3（pp.103–104）：双向连接齐备及已有足够本通道信用才可发Beat。Read Response/Data每实际Beat消耗一次RdRsp的原port/VC或pool信用，其数据不另扣OrigData信用。初始化和返回信用由既有独立bank/initializer/return组件管理；信用归还四端口valid与字段不按TDM，且原VC/Pool须被接收存储保存到归还。返回valid4的parity每周期检查；另一个parity覆盖完整Pool4/VC8/Num8，在任意valid时检查，InitDone4不包含在此集合。本TX叶不实现这条反向接收路径。

§2.7.8（pp.71–72）：Multi-Beat模式具有固定NumBeats=N-1、offset从0递增到N-1、同port的数据Beat连续占有效TDM时隙，last仅最后Beat有效。为了履行无间断多拍承诺，调度器须在开始前确保整个burst所需资源；字段层不提供FIFO或尾拍预约。Single-Beat模式NumBeats=0，offset可乱序、不同事务可交错并有间隙，last标记该事务最后实际发出的Beat。不得通过本字段层去推断或重组Tag状态。

§2.7.5.1（pp.64–65）：普通预定义请求状态包括0/2/3/6/8；INC还有Switch专用14，Vendor Defined命令的非零状态有供应商语义。错误2/3/6/8也须返回全部请求数据Beat及last，必要时制造数据；推荐的全一模式不是字段层强制改写规则。status同一响应各Beat一致；DataError可逐Beat变化，属于数据poison，不等于失败status。§2.7.5.2–.3（p.65）定义逐Beat数据错误与地址序号。这些约束由上游响应构建/发送控制和接收收集检查，本leaf透传完整字段，不把任意4bit状态判为已支持的合法业务。

Table 2-15 p.62：dst回指原ReqSrc，Tag保留完整原ReqTag；src推荐保留原ReqDst作为debug，若不准确可为0，不能用于功能路由判断。VC应保持原ReqVC，Pool由本次实际信用账户决定。授权未启用时AuthTag必须为0；上游根据显式授权配置准备正确值，本层不能从其它字段猜测授权状态。字段层不隐藏源/目的交换，也不重新分配Tag。

§4.1–4.2（pp.101–102）：同一UPLI时钟域与共同同步reset；本层i_rstn必须和信用/TDM发送控制使用同一reset，不能在上游已扣账后单独屏蔽字段有效。无效周期除valid保护外字段不承载有效事务信息；本实现统一清零属于本地确定性行为。

## 已有模块与本轮验证

现有`model/ualink/upli_tdm.py`已经把rd_rsp列为独立相位组；`upli_credit.py`区分req/orig_data/rd_rsp/wr_rsp账户。`upli_receive.py`及实际`upli_receive_channel`保存opaque payload与原VC/Pool，不包含本次完整Read Response语义检查；`upli_burst.py`和实际`upli_burst_sender`目前描述Req/OrigData，不能直接冒充Read Response调度器。本次复用真实公共parity，不复制这些已有状态机。

先在实际旧壳获得编译成功、能力失败的红测，再实现typed叶模块。测试范围为逐字段全624bit、valid/idle/reset、全部八个Data parity组、每个Data bit在DataError=0/1下的保护、全部status/type/offset/num/last/poison组合、随机完整元组、实际RTL接线故障。含保留编码或不合法跨Beat组合的单拍向量仅用于字段透明性检查，不把它们算合法事务功能。候选目录`build/development/upli_read_response_channel/`保存源码、独立参考、TB及证据；生产安装、完整Read Response sender/RX、station总装、RAS、安全认证、TL/DL一致性及PPA/STA不在本任务完成声明内。
