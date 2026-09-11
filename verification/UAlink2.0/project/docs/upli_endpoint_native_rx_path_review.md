# Endpoint native RX path 隔离候选审查

本候选把实际 native 事件连接到受保护 SRAM、有序 head 和完整请求 descriptor。没有修改生产 RTL、规范契约、库存或现有验证器；没有提交。最终可安装源码是同目录 `upli_endpoint_native_rx_path.v`，完整端口在 `interface.json`。本轮依据仓库 `upli_native_rx_execution.md`、`upli_endpoint_context_execution.md` 的已冻结字段和所有权；Common 2.0 §2.5、§2.6、§2.7.8、§3.1.1–4、§4 的适用范围仍沿这些文档保留，不复制私有正文。

## 真实层级与接口

Yosys 从候选 top 实际递归展开：4×`upli_native_rx_channel`、8×`upli_native_rx_protection`、4×`upli_ordered_receive_channel`、4×`upli_receive_channel`、4×initializer/return queue/return adapter、20×receive storage/FIFO、20×公共parity、1×三相位 `upli_receive_tdm_monitor`、1×`upli_endpoint_request_bridge`。PORTS1真实数据存储映射到250个KD28 SRAM单元实例；这是功能映射计数，不是PPA或面积结论。检查无latch，全部实际依赖参与编译和展开。

输入payload分别Req184/OrigData580/RdRsp619/WrRsp101，另有Port2、VC2、Pool1、实际收到parity13。保留全部Auth、Src/Dst、11位Tag、57位地址、Data、BE和逐拍poison，未将接口收窄为VC0/Pool0/Port0。四套独立账户容量向量沿用真实接收层参数。Req/Data消费者由单holding bridge拥有；Rd/Wr公开完整可信 `head_valid/consume_valid/payload/parity/vc/pool/account`，外部只选择port及ready。Req/Data也公开只读head与实际taken事件，便于逐层对照。

Originator角色连接/Drop作用响应RX，Completer角色连接/Drop作用Req/Data RX。接收信用发布资格直接接外部连接控制器的对应TX-connected，而发送器的信用入站资格接RX-connected；两个方向没有交换或创建第二套状态。三相位monitor观察校验前原始native事件，只诊断，不过滤信用。四通道保护错误、完整入口/head错误向量、存储/顺序错误和TDM状态全部公开。

共同reset连接全部RX和TDM。bridge单独使用 `i_rstn && !i_completer_drop`：Drop当沿屏蔽其有效/消费，下一同步沿取消部分或完整holding。RX仍用共同reset，已经登记的可信返回继续按原账户排空。最终 `request_valid && request_ready` 只释放holding，不再次返还信用。Drop不在本候选生成dummy completion。

## 独立测试和结果

TB实际实例化已安装 `upli_station_tx`、Originator/Completer两个 `upli_connection_side` 及候选中真实KD28 SRAM接收路径。没有使用预生成Response替代completer的声明；本TB的Rd/Wr是显式独立构造的响应传输流。其完整错误状态数据、单拍乱序offset/last、多拍尾部及Auth只是接收透明保存测试。

独立账本以实际发送候选accepted时的完整源字段为根：先逐位比较真实native输出，再逐port记录native到达顺序并比较可信SRAM head；descriptor期望单独由源Request和源Data构造，不能从DUT已组装结果倒推。信用journal仅在真实head transfer建立，检查返回必须对应更早transfer、原pool/VC及数量。初始容量发布与正常返还分开，四通道五账户分别计账。首次descriptor valid即检查完整tuple与已退休Req/Data数量，整个长背压期间稳定，最终fire不消耗额外头。

驱动在negedge（必要时后移1ns）改变；周期和selector也在negedge更新。posedge只采样/更新不反馈组合输入的账本；registered accepted在posedge后1ns与该沿预先保存且按Drop资格限定的native事件比较，避免重取变化的输入。

红测 `red_first`：只有全部输出零的接口壳，compile=0/run=1，第110周期 `PATH_MISMATCH id=210`，初始信用未建立。该失败在实现实际连接前取得。中间源码和全部历史label保留。

最终 `release_matrix`：

| ports | 真实descriptor接纳 | head transfers | 原账户returns | descriptor背压周期 | Drop丢弃native拍 | 检查次数 | 周期 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | 72 | 447 | 447 | 995 | 37 | 21808 | 1724 |
| 2 | 72 | 447 | 447 | 971 | 57 | 22000 | 1727 |
| 4 | 72 | 447 | 447 | 971 | 60 | 22312 | 1733 |

各配置compile/run/g2001/Verilator `-Wall`/Yosys返回码均0。三轮正常流每轮24请求，包括8 Read、8普通Write、8 WriteFull；每轮实际OrigData40拍、RdRsp60拍、WrRsp24拍。请求Tag从1024开始、高地址bit56为1，Src/Dst及完整Auth高位非零；四VC与pool变化、逐拍DataPool/BE/poison分别保存。当前矩阵普通Write覆盖64/192B，Full覆盖128/256B，Read示例LEN63；不冒称全部4..256B合法几何。完整几何的既有bridge单位测试是另一组证据。

除三轮正常流外，在完整descriptor受背压且其他native拍已入RX时统一reset，取消旧holding与存储；新轮同Tag恢复。另在仅有一笔已退休Read holding时施加Completer Drop，确认取消后解除Drop也不重新公开该descriptor，原账户信用仍恢复到容量。再对两个角色施加Drop，让真实对端四通道继续发出已有信用允许的拍：所有新拍均不被接受，不建立新返回记录；统一reset取消对端/接收epoch后再运行第三轮。447次head/return包含正常444次、reset前已经退休的Req+Data两次及Drop取消Read一次；没有把丢弃的入站拍算成已接纳事务。

实际源码/接线fault，均compile=0/run=1且runner确认预期失败：

| label | 实改内容 | 首次检出 |
|---|---|---|
| `release_tag` | bridge完整Request输出断接并置零 | id22，cycle26，descriptor全字段不符 |
| `release_credit_pool` | native返回适配器在initdone后错误清pool，同时由真实公共parity重新生成保护 | id11，cycle243，正常返回账户不符 |
| `release_tdm` | monitor的真实Rd port错接零 | id3，cycle29，三相位诊断异常（ports4） |
| `release_drop_reset` | bridge漏接Completer Drop取消资格 | id26，cycle1191，旧holding仍有效（ports4） |

历史 `final_credit_pool` 只把返回pool输出清零，因此首先由credit parity id5检出；这不是独立账本故障检出证据，最终改进fault才是。所有mutant仅改各label快照，未修改生产或候选基线。

## 重放、证据与技能边界

从工程根执行：

```sh
python3 build/development/upli_endpoint_native_rx_path/run.py --label NEW --kd28-root /explicit/OverFlow --static
python3 build/development/upli_endpoint_native_rx_path/run.py --label NEW_FAULT --kd28-root /explicit/OverFlow --ports 1 --fault credit_pool
```

输出为候选 `evidence/LABEL/`，已有label拒绝覆盖。runner按自身位置解析工程根，KD28必须显式传入且与既有manifest五份功能源SHA匹配。source快照、TB、runner、完整command/返回码、log及逐artifact SHA均保留。strictlint只把外部多模块cells文件按原module body拆分为同名文件，记录body/source SHA，没有RTL修改或新增warning waiver。不要发布外部KD28快照作为项目自有源码。

`skill/structural` 的本模块artifact静态检查0 errors/10 template/style warnings；本top没有新always或pipeline，因此该单文件检查显式按无新增时序状态的连接层建模。实际clock/reset及子层状态由上面的EDA全层级与动态测试验证。初次沿用时序leaf配置产生三个不适用的always/reset/pipeline要求及一条模块说明关键字错误，保留于 `skill/frozen`；随后修正验证范围及模块说明，不添加虚构寄存器。全局skill安装gate仍exit1：缺少既有伴随文件 `/home/ljy/.codex/skills/agents-md-generator/scripts/manage_docs.py`。这不是已通过的全局技能签核，也不是本次EDA失败。

## 待集成风险

本候选仅完成受保护接收至完整请求holding及可信响应head。仍无实际Endpoint TL formatter/context/backend连接、Response collector/Tag归属和退休、Auth验证、安全上下文、role范围Drop保持/Isolation/dummy完成/恢复epoch策略。响应Src保持透明，不把其作为功能Tag匹配条件。三相位诊断不能替代非法对端首Data同沿、整个burst连续性等完整原生接收协议检查。

Drop只取消bridge holding，不清四RX中更早存储的未退休头；测试中解除Drop前该定向场景已确保队列空。对一般有积压的Drop恢复，外部必须执行已定义的新epoch/reset/隔离策略，不能直接撤销Drop便宣称旧事务都已清理。已丢弃未知/不可信拍不凭空返还信用。统一reset不能冒称独立LinkDown或端到端epoch协议。后续优先接真正请求context/executor和raw响应collector，维持已有三种事件独立所有权，再实现唯一role RAS策略。
