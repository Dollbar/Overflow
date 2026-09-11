# UPLI 基础控制模型契约

范围与依据见 执行计划（历史文档已清理）。本契约为 WP02 的明确子集，不表示完整 UPLI/RTL、CDC/RDC 或时序签核。

## 时钟、复位和错误处理

模型 step 代表上升沿；无 step 就无周期推进，不把 Python 执行耗时当 UPLI 时间。连接 `step` 输出沿后的稳定控制电平，账本的 `connection` 参数必须是消费沿前的稳定电平。寄存器式 ACK、禁止同拍新信用旁路是本模型的保守微架构选择，不是额外协议 SHALL。同步复位每沿清理内部状态；`min_reset_cycles` 明确控制最小低电平保持，默认 1。连接模型须先看到至少一个复位沿，撤销沿不能发新 ClkReq；下一沿可发。事务/Tx 压缩缓存状态不归这几个类所有，不能据此宣称已经实现 R016/R018 的跨模块清理。

非法类型/参数为 `TypeError`/`ValueError`，协议时序/资源前提违反为 `ValueError`；无线上新错误码。拒绝的 step 不改变有效状态或推进 TDM（方便回放诊断；不是实际硬件遇错后的 RAS 处置）。复位优先清理，忽略同拍业务事件。

## 连接控制

`ConnectionSignals(orig_req, comp_ack, comp_req, orig_ack)` 是不可变的四电平快照；`orig_connected = orig_req && comp_ack`，`comp_connected = comp_req && orig_ack`。

- `UpliConnection.step(reset_n, orig_ready, comp_ready)` 生成两端控制：Originator 准备好就请求，不能依赖 Completer 先建连；ACK 是对先前周期请求的注册应答。各信号断言后保持至 reset。
- `completer_waits=True` 允许 Completer 在 Originator→Completer 建连之后再请求；默认两端独立请求。ready 下降不会撤销已有连接，调用方必须继续保证已经承诺的收发能力；真正断电恢复另审。
- Originator→Completer 建连后，允许 Originator 返回 rd_rsp/wr_rsp 信用。Completer→Originator 建连后，允许 Completer 返回 req/orig_data 信用。beat 必须四电平均为高，外加相应初始化/信用/事务约束。
- 同一 UPLI 两端共享时钟；本控制不是 DVFS 关钟握手，不改变 PHY 线速。

## TDM

`UpliTdm(num_ports)` 支持 1/2/4，`step(beats=(), reset=False)` 的 beat 仅含 `(channel, port)`。第一次 req 学到 req/orig_data 共用相位；orig_data 不得在尚无首个 req 时单独建相位。rd_rsp 和 wr_rsp 各自在自己的首个 valid beat 独立建相位。空周期仍推进已经建立的相位，未建立相位的通道保持未知，不根据无效 PortID 学习。每 channel 每周期最多一个 beat。

此 TDM 监视器自身不验证 write data 与具体 Request 的依赖/长度/连续 burst；新增的 UpliBurstMonitor 在它之上检查正常 burst，范围见后文。信用返回根本不输入 TDM 监视器。

## 信用账本与初始化

- 一个 ledger 是一实例 UPLI 的四个 channel，port 范围 0..num_ports-1。容量为 `Account(port, channel, vc)`→非负整数；`vc=0..3` 是专用 VC，`vc=None` 是一个跨 VC 共享 pool。未列出的账户容量视为零，不预置任何信用。
- `CreditReturn` 有效时数量为 `encoded_count+1`，编码 0..3；pool 选择共享账户但保留输入 VC 合法性校验。valid=0 时内容全部忽略，不能因无效 port/channel/num 影响账本。相同 channel/port 一个周期最多一条有效返回，不限制其它端口同时返回。
- `Beat` 消费一个信用。每 channel 每周期最多一个；TDM 与事务检查由相邻监视器负责。必须已双向连接、对应 port/channel 的 init-done 已确认，且**沿前**余额足够。同沿返回随后与消费合并更新，容量限制检查更新后结果。没有隐式饱和/截断，也不因正常发送暂停拒绝合法返回。
- `init_done` 是本周期为高的 `(port, channel)` 集合。达到 `init_stable_cycles >= 2` 个连续高采样后保持 initialized；达标沿本身还不允许依赖新标志发送。短高后低会重计数；已达标后忽略该输入的低脉冲。不同 channel/port 独立确认。
- `CreditInitMonitor` 检查正常接收方的高电平保持规则和首次 done 不与最后初始 credit 同拍；其报错与发送方抗毛刺行为分开。首次 done 之后可出现正常返还，不应被误判为初始释放冲突。
- `UpliCreditLedger` 只检查发送账本，不生成接收资源凭证/归还队列；单独使用时不能检查伪造返回来源、二次归还或共享 pool 的逐 beat VC 回显。后续增加的 R012 接收子模型和 R013 正常 burst 模型见下文；账本的资源上界测试不能替代这些机制。

## 接收凭证与正常信用归还

`UpliReceiptQueue(capacities, num_ports)` 使用同样的 Account 容量表示。`step(connection, beats=(), retire=(), batches=(), reset=False)` 返回 `ReceiptEvents(receipts, returns)`；输入 beats 为 Beat，输出 receipts 为不可变、按对象身份区分的 Receipt，保存原始 Beat。`retire` 是资源使用方已完成的 Receipt 集合；`batches` 中每组包含 1..4 个沿前已 retired 且 port/channel/VC/Pool 全相同的凭证，输出 CreditReturn 数量编码为组长减一，字段取自原始保存值。

`occupancy(Account)` 统计已收未归还数量；`returnable` 按接收顺序暴露可选凭证，仲裁策略在调用方。一通道每拍最多一个输入 beat，一 port/channel 每拍最多一个输出 batch；不同 port 的信用可同时返回，与 TDM 相位无关。beat 要两方向连通，返回仅要求归还方方向连通。

复位丢弃全部凭证；旧、跨实例、字段相同的新对象或重复凭证会被拒绝。非法沿不部分更新。满容量不能用同拍返回立即复用，retire 也不旁路同拍归还，是保守实现选择，非额外协议 SHALL。容量不是已发布信用；初始化发布、发送方已获信用/过滤器、TDM、事务/突发合法性仍必须由相邻模型检查。本模型 token 不是线上 Tag 或安全认证凭证，没有实现物理 FIFO/缓存和完整 RAS。范围证据见接收模型审查（历史文档已清理）。

## 正常 burst 调度与被动序列监视

`UpliBurstSender` 拥有发送账本，启动请求前按整笔 `data_pools` 检查沿前信用；预约只锁定尚未发出的分配，实际扣减发生在每拍数据发出时。`available + reserved = balance`；新返回信用和 init 确认沿没有旁路。同 port 前笔 burst 未结束不能启动后笔带数据请求，即使该沿为最后数据；read-class 可同拍叠加。每 port 独立连续发出，各 port 按固定 TDM 相位交织，空周期不停止相位。

`BurstRequest(port, vc, pool=False, num_beats=None, data_pools=())` 和 `BurstData(port, vc, pool, offset, last)` 只是内部/监视元信息；None 标记无 OrigData 的 read-class，整数 num_beats=0..3 对应实际 1..4 拍。它们不是完整 UPLI 字段包，不推断命令、地址、原子或 ByteEn 合法性；提交前 payload 已全部暂存是调用方前提。`step` 输出 `BurstEvents(request, data)`，accepted 表示候选已实际发送，beats 可直接给信用/接收账本消费。

`UpliBurstMonitor(num_ports).step(request=None, data=None, reset=False)` 独立使用剩余 offset 和绝对到期周期检查首拍、连续 slot、VC/offset/Last，再独立调用 TDM 检查。它不读取 sender 状态或其 allocation，不限制合法的每 beat pool 变化。正常 burst 遇非法沿原子拒绝；reset 清空 pending/phase/credit。本包不检查 Drop/Isolation 所允许的异常截断，也不实现响应调度、payload FIFO 或全信用 RTL。接口和源条文见burst 计划（历史文档已清理），实测边界见burst 自审（历史文档已清理）。

## Parity

- `even_parity(value,width)` 返回 value 的归约异或；所有位串为明确宽度的非负整数，不自动截断。
- `check_orig_data` 的 valid parity 每周期检查；其余字段仅 valid=1 检查。data 为 512 bits，data_parity 为 8 bits，每一位保护对应连续 64 bits，**不依 ByteEn 遮掉数据**。byte_en 为 64 bits，独立一个 parity。fields 为 9-bit 打包控制：bit0 Last、bit1 Error、bits3:2 Offset、bits5:4 PortID、bits7:6 VC、bit8 Pool；此打包只是检查函数输入约定，非线上新增字段。
- `check_credit` 中 valid_mask=4 bits，每周期校验 valid parity；vcs=8 bits、nums=8 bits、pool_mask=4 bits，低端位组对应 port0。只要任一 valid bit 为 1，就校验**全部四个端口**的 VC/Num/Pool，不对 inactive port 控制位做掩码。
- 返回错误集合元素 `valid`、`control`、`byte_enable`、`data0`…`data7` 用于模型诊断。这里只执行已确认 UPLI 检查，不选取 A17 中未决 Switch Core ByteEn poison/drop 路径。四个通道其它精确控制字段、ReqAddr 分组和完整 RAS 升级仍须逐表补齐。
