# Station TX 总装独立审查

审查结论：在当前本地 normal-path TX profile 内，未发现角色接线交叉、字段截断、额外 bypass 或信用诊断被消除。此结论限定为三个真实 sender 的四通道聚合及其测试；它没有关闭完整 station RX、Endpoint native 事务桥或错误恢复策略。

## 固定连接与层级

对冻结 RTL 进行独立 Yosys 展开、`proc; check -assert` 和逐 net-bit 连接核对，覆盖端口数 1、2、4。顶层恰有七个直接实例：Request/OrigData 共用 sender、Read Response sender、Write Response sender，以及四个 credit guard。实际后代中恰有四个 credit bank；Request/OrigData 共用一个 burst control，Read Response 与 Write Response 各自拥有独立相位状态。没有为 OrigData 再加相位或第二套 Request bank。

| 通道 | sender 的信用资格 / 发送资格 | guard 索引 |
|---|---|---|
| Request / OrigData | Originator credit-connected / beats-connected | 0 / 1 |
| Read Response | Completer credit-connected / beats-connected | 2 |
| Write Response | Completer credit-connected / beats-connected | 3 |

所有 sender 使用同一 clock/reset。独立检查规则按模块端口名建立映射，逐位比较 candidate、完整 native 输出、信用输入、诊断及连接资格；1/2/4 端口分别检查 7809 / 7889 / 8049 个连接位。进一步将 Req/Data/Rd/Wr 容量分别设为 1/4/3/2，检查四个实际 bank 的展开参数，均落入正确子层级。该不等容量项是结构核对，没有宣称该组合已完成动态流量测试。

四个 guard 都接真实通道的完整 Valid[3:0]、Pool[3:0]、VC[7:0]、Num[7:0] 与两组 parity，check-enable 接 rstn。错误、valid-error、control-error、integrity-ok 均按通道暴露。错误标志不擅自屏蔽信用或在途尾拍；integrity-ok 仅表示 enable 限定的 no-detected-error，不是建连许可。return adapter 位于测试的真实接收返回路径，并非虚称集成在此 TX 顶层内。

复现独立结构检查：

```sh
python3 build/development/upli_station_tx_audit/check.py \
  --snapshot build/verification/upli_channels/station_tx/station_release \
  --label NEW --distinct-capacities
```

实际完成标签为审查目录下 `installed_distinct`；其十三份 RTL 的 SHA-256 与三个最终正常 release 快照逐份相同。输出含每个逐位映射、四个 bank 路径、容量、命令、返回码和展开 JSON。`first` 保留了审查脚本未归一化 Yosys 转义 hdlname 的自身失败，不能当作 RTL 缺陷；修正后的 `second`、`installed_distinct` 通过。

## 仿真 oracle 与调度核对

测试使用两个真实 connection-side，以外部交叉 req/ack 建连，四个真实 receive-channel 和 SRAM 存储/返回。Originator/Completer 发送信用、发拍资格，以及对应接收侧的反向信用资格一致，没有伪造 peer acknowledgment。接收 payload 宽度为 Req184、OrigData580、RdRsp619、WrRsp101；Port、VC、Pool 另行保留和比较。

独立队列在 candidate-accepted 时从原始输入保存所有拍，native 事件先与该队列完整逐位比较，随后真实 SRAM 退休再与已经核对的 native 事件比较。队列没有读取 DUT tail、bank 余额或 SRAM 内部状态。单独对实际输出重新求 parity 并非完整数据 oracle；这里原始 candidate 到完整输出的比较补足其身份约束。驱动在 negedge 后准备，candidate-accepted 计数在 posedge 后被驱动任务观察；本次审查未发现同沿反馈改变 DUT 输入的竞态。

最终 TB 已关闭此次发现的三个具体测试缺口：四通道 control parity 注错同时比较各自 control-error，idle valid parity 注错同时比较各自 valid-error；single Read Response 的 Offset/Last 有变化；带数据普通 Write 使用命令 0x28、自然对齐地址及 Len={NumBeats,4'hf}，Read 使用命令 3、Len63、NumBeats0。所有 typed 字段仍由完整输入队列校验。

响应由测试独立构造，并不由收到 Request 后的 backend 产生。single 模式 Offset/Last 的字段变化不等于同一 Tag 的完整乱序重组；错误 status 和 data-error 的传输也不等于后端执行语义验证。测试检查独立相位、排空、队列次序和信用耗尽后的返回，但没有独立逐周期重算所有 bank 余额，也没有为所有尾拍逐一建立连续 slot 到期断言；更强的 sender 预约/连续性验证应结合各 sender 单元证据。

## 最终证据

证据目录前缀为 `build/verification/upli_channels/station_tx/`。

| label | 配置 | 实际结果 |
|---|---|---|
| station_release | ports1/2/4，CW4，cap4 | 三配置各 compile0/run0；g2001、严格 lint、Yosys 均 exit0 |
| station_release_wide | ports4，CW16，cap5 | compile0/run0；三项静态检查 exit0 |
| station_release_minimum | ports1，CW3，cap5 | compile0/run0；三项静态检查 exit0 |
| station_release_rd_tag | ports4，实际断开 Rd Tag 输出并置零 | compile0/run1，mismatch104，cycle58 |
| station_release_wr_tag | ports4，实际断开 Wr Tag 输出并置零 | compile0/run1，mismatch143，cycle62 |
| station_release_guard_bypass | ports4，四 guard check-enable 置零 | compile0/run1，mismatch191，cycle12 |

五个正常配置各运行两个完整轮次，每轮实际发送并排空 24 Request、40 OrigData、60 Read Response、24 Write Response。两轮之间额外注入流量，观察四类 RX pending 后统一 reset，并在静默窗口检查无旧事件，再运行新轮。仅宣称统一同步取消，不宣称单端 LinkDown/独立 epoch 恢复。三个 fault 是故障检出，因此 run1 为期望结果；其余十二份 RTL 与正常快照相同，只有故障注入的 aggregate 快照不同。

独立重算六份最终结果中全部 1357 项 artifact 的 SHA-256，零缺失、零差异；十三份 RTL 与结构审查快照的身份绑定同样通过（fault 中只排除有意修改的 aggregate）。清单与逐配置日志摘要保存在 `build/development/upli_station_tx_audit/release_evidence.json`。历史 `station_installed` 的严格 lint 曾因 CLI 未定宽 capacity 触发 WIDTHTRUNC；最终 runner 使用 CW'dCAP，未用 waiver 掩盖。

冻结身份：

```text
upli_station_tx.v        46e3c8f810d714fcfea296e8cd87b5ea0219558843a5493be985a11b457950da
upli_read_response_sender.v
                        4ec11412689f2daddf1f10afc77193898b4314ce0b3574109a37c0a0a5cc7e5f
station_tx_tb.sv         03f03ce0625beb6718d24438e37f3e45396a751c5e03b94473b375eb054d6ae3
run_station_tx.py        9e76b5f6667d242b877b9873880efe485bac29e809f9c2a9a4fdad9d0567ab2c
```

## 未关闭边界

完整 native RX 字段/语义检查、与 Endpoint 事务上下文的双向适配、最后 OrigData 接收之后下一周期才可 Response 的执行因果、Auth 上下文与表内方向疑点、parity 错误处置/隔离/恢复、独立 LinkDown，仍需后续工作。实际 SRAM 返回验证不构成完整 station，当前总装也不是单侧物理 station。这里没有新增 PPA、形式等价、互操作或规范全面一致性结论。
