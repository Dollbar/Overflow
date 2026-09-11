# 完整 Read 在途统一复位集成验证

基线生产版本 `013c9fd805669b33a10bc51ef7c27256b7ff304a`。仅新增本测试、runner 和此文档，不修改 RTL。两个真实 Endpoint 开启 TRANSACTION_MODE / WRITE_ENABLE / FULL_READ_ENABLE，经真实 Switch 和数字链路执行；无预制 Response。

每侧旧轮先实际 WriteFull256 建立非零内存，再发 Read256（Tag1024、地址0）。三个独立窗口：1）两端后端都接纳 Read，尚未返回；2）两端实际 receiver→Tag 握手已收到 1..3 个响应 Beat，未收齐4；3）完整 Read complete_valid 被应用稳定背压至少8周期。旧 Write 已完成，旧 Read 不允许应用退休。

同步统一拉低 Endpoint / Switch / 传输 / 后端 pending reset 三个上升沿，保留内存和累计执行数。随后120周期不发新请求检查旧结果/完成泄漏，再用相同Tag/地址Read256，并检查跨Beat稀疏mask、LEN0零BE、完整4Beat错误状态响应。新轮每侧4个Read必须完成。所有数据期望由独立Python字节内存oracle生成；BFM只处理真实内存命令和实际Write数据/BE。

BANK_DEPTH1/3各覆盖三窗口。实际漏side0 Endpoint reset与漏backend pending cancel接线变异各需要被检出。窗口由公开实际握手判断；反馈DUT的cycle/requested/索引使用NBA，reset/start/epoch在negedge改变。每个新label保留完整源码/依赖/fixtures/日志/返回码/hash。下列实际结果验证此契约；不将统一网络复位扩大为独立LinkDown或协议epoch恢复。

## 实际连接和独立判据

Endpoint 本地 ID 为17 / 513、物理 port0、Tag / Read / Write completer 容量各4，Switch 为2口静态路由、545位本地数字记录，RX_DEPTH160、每信用类别容量4、DL_DEPTH3。记录额外携带显式 CRC 正确状态，未构造标准线上 CRC 或 A19 位序。Auth=0，没有预制 Response；Response Header / Data 都由真实 completer 在真实内存结果后发送。

BFM 复用既有 `read_endpoint_switch_tb.sv` 的实际字节内存行为，保存在本次新 TB 内：Write 只按实际收到的 Data / 区域 BE 修改内存，延迟17周期执行；Read 保存实际地址 / 长度 / slot，延迟70周期返回自然对齐的 N 个完整 Beat。未使用返回区域填非零 `D7`；BFM 不读取数据期望、不共享 pending / due 给 scoreboard。相对既有 BFM 的复位适配是只在 initial 初始化内存和累计 Write 执行数，运行 reset 只取消请求、结果及槽所有权。

独立 Python oracle 逐字节产生旧轮真实 Write 的源数据与保留内存期望，按 ATTR 生成 Read mask 与 masked 完成数据。旧 Read 为 Tag1024 / 地址0 / LEN63 / ATTRff；新轮同Tag和地址改为ATTR5a，可区分旧完整完成和新掩码结果。其余新 Read 为 Tag1792 地址60长8字节跨Beat、Tag31地址124长4字节零BE、Tag2047地址0长256字节状态3。正常与错误 Read 都必须收齐预约的全部 Beat，错误结果 `data_valid=0` 且 data / mask全零。

观察点分别为实际应用请求接纳、`u_tx.o_header_taken[0]` 的真实发送、公开后端命令、实际 Write 执行脉冲 / 返回、完整 Read 结果握手、receiver→Tag 的完整512位响应握手、首次与被背压的 complete_valid。每次完成必须满足同轮真实请求已发送、对端真实结果和最终响应 Beat 均在更早周期发生；全部Tag / kind / status / data / mask及低512位兼容视图独立核对。部分接收窗口按实际 receiver→Tag 握手统计，不按预估延迟或 BFM pending 触发，也不把源capture当发送。

复位在negedge拉低，三个posedge后解除；Endpoint、Switch、传输寄存器及正常BFM共用rstn。每个复位沿在NBA后检查公开origin / completer / DL计数及有效输出清零、Switch无有效输出、内存全2048位仍等于保留期望。解除后120周期不启动链路新请求，且持续检查无旧后端结果 / 命令 / 完成 / Tag占用 / 响应交付。最后重新启动后仍保留全部因果和唯一退休检查，排空后再观察80周期。

影响DUT的cycle、requested、memory_issue和传输寄存器均以NBA更新；epoch、reset、start及allow_requests只在negedge改变。blocking的cursor / owner / coverage仅用于scoreboard；BFM状态注入使用独立NBA memory_issue，避免同沿cursor更新改变所采样状态。

## 实测结果

证据根为 `build/verification/endpoint_transaction/<label>/`，每个 stage 留存独立编译 / 运行日志。正常case均compile0 / run0：

| label | bank | stage1：后端待结果 | stage2：部分响应 | stage3：完成背压 |
|---|---:|---|---|---|
| `read_reset_release` | 3 | cycle111：两端Read结果0、响应0Beat；cycle734排空 | cycle195：两端实际各收1/4Beat；cycle818排空 | cycle247：各收4/4Beat、背压8周期；cycle864排空 |
| `read_reset_release_minimum` | 1 | 同窗口与结果，734周期 | 同窗口与结果，818周期 | 同窗口与结果，864周期 |

新增部分响应边界同样以最终统一源码运行，全部compile0 / run0：

| label | bank | 窗口2精确计数 | 触发 / 最后排空周期 |
|---|---:|---:|---|
| `read_reset_release_partial2` | 3 | 两端各2/4Beat | 208 / 832 |
| `read_reset_release_partial2_minimum` | 1 | 两端各2/4Beat | 208 / 842 |
| `read_reset_release_partial3` | 3 | 两端各3/4Beat | 225 / 842 |
| `read_reset_release_partial3_minimum` | 1 | 两端各3/4Beat | 225 / 842 |

每窗实际先完成2笔种子Write，取消2笔旧Read的应用完成，复位后完成8笔新Read / 22个Read响应Beat；所有新Read身份只退休一次，最高实际预约达到4。十个正常case合计20笔Write已执行并保留、20笔旧Read被取消、80笔新Read完成。窗口2以显式 `--partial-beats 1/2/3` 配置，并要求两端实际计数精确等于目标才触发；每种计数在bank1/3均覆盖。窗口1取消的是尚未返回的后端Read；窗口2/3后端已返回，取消的是后续响应 / Tag / 应用完成所有权，不能统称三窗都取消未返回的backend结果。

实际接线故障只改变side0，初始power reset仍正常，遗漏的是在途那次reset：

| label | bank / stage | 实际改动 | compile / run | 检出 |
|---|---|---|---|---|
| `read_reset_release_endpoint_fault` | 3 / 2（3Beat） | Endpoint接power_rstn，漏在途reset | 0 / 1 | 部分Read已到达后，复位沿 `READ_RESET_STATE` |
| `read_reset_release_endpoint_fault_minimum` | 1 / 2（3Beat） | 同上 | 0 / 1 | 同上 |
| `read_reset_release_backend_fault` | 3 / 1 | BFM接power_rstn，漏pending取消 | 0 / 1 | cycle158静默期出现旧结果，`READ_RESET_OLD_BACKEND` |
| `read_reset_release_backend_fault_minimum` | 1 / 1 | 同上 | 0 / 1 | 同上 |

这些fault的passed=true要求先实际命中指定窗口，再编译成功、运行exit1并命中对应诊断；不是修改expected或直接制造fatal。它们证明检查器能发现集成取消边界被破坏，不声称Endpoint在合法backend接口上能自动识别外部漏取消的epoch。

早期 `read_reset_first`、`read_reset_final`、`read_reset_minimum`及旧fault结果完整保留。最终追加partial-beats配置后，统一源码重新跑10正常配置及4故障；最终证据以上表release labels为准。未发现需修改生产RTL的问题，也未遇主线开发期间短暂parity壳接口窗口。

## 来源身份和重现

每个label记录212个实际source映射，包括全生产RTL、5份通过dependency manifest校验的KD28功能模型、TB、runner与manifest。两个三窗正常label各251份声明制品，四个单窗正常label和四个fault各225份；十个label共2302份制品及全部source副本已逐项SHA256复核，零缺失、零差异，且审阅时所有源与工作区一致。见 `read_reset_release/audit.json`。源码读入的同一份bytes同时用于写副本和计算hash，实际编译只读取留存副本。

冻结TB SHA256：`fb35eb8d19062f8be541f8421c280d4f742c20dae62cf7b5202e73764ff09341`。
冻结runner SHA256：`f7819e2563c58e4d595848d56ae720e0d20bd43d4b7e14d480014638e997f732`。
本轮生产未修改，基线为 `013c9fd805669b33a10bc51ef7c27256b7ff304a`；准确逐文件身份保存在result的sources，后续生产变化不自动继承本结果。

独立工程根目录：

```sh
python3 verification/endpoint_transaction/run_read_reset.py --label NEW_READ_RESET --kd28-root /path/to/authorized/Overflow
python3 verification/endpoint_transaction/run_read_reset.py --label NEW_READ_RESET_MIN --kd28-root /path/to/authorized/Overflow --bank-depth 1
python3 verification/endpoint_transaction/run_read_reset.py --label NEW_READ_RESET_PARTIAL2 --kd28-root /path/to/authorized/Overflow --stage 2 --partial-beats 2
python3 verification/endpoint_transaction/run_read_reset.py --label NEW_READ_RESET_PARTIAL3 --kd28-root /path/to/authorized/Overflow --stage 2 --partial-beats 3
python3 verification/endpoint_transaction/run_read_reset.py --label NEW_READ_RESET_EP_FAULT --kd28-root /path/to/authorized/Overflow --stage 2 --partial-beats 3 --fault endpoint_reset
python3 verification/endpoint_transaction/run_read_reset.py --label NEW_READ_RESET_BACKEND_FAULT --kd28-root /path/to/authorized/Overflow --stage 1 --fault backend_cancel
```

partial2 / partial3及fault命令追加 `--bank-depth 1`、使用全新label，可重现全部最小bank配置。Overflow发布布局先 `cd verification/UAlink2.0/project`，`--kd28-root` 改为 `../../..`。label必须全新，输出源快照、fixtures、stage compile / run日志和result.json。下一步随主线发布复核本轮新三文件；生产修改后应按新label重跑对应边界。

局限：只覆盖单时钟统一网络reset、规定保留内存/取消pending的test-only后端策略；没有单端独立reset、LinkDown协商、协议epoch、异步CDC / RDC、Auth、安全上下文、实际串行CRC、PCS / FEC / SerDes或任意后端系统的副作用回滚保证。没有新增本次之外的Read几何矩阵、完整multi响应模式或完整双IP交付声明。
