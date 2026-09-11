# Write 在途统一同步复位与内存保留检查

新增真实双Endpoint → Switch → Endpoint混合Write/Read复位验证。三个窗口分别在Data bank深度3和1下通过；漏复位Endpoint与漏取消后端pending两类故障也分别在两个bank配置下检出。只新增 `write_reset_tb.sv`、`run_write_reset.py` 和本文，未修改生产RTL、既有ESE、VIP或pkg。

## 复位和副作用边界

两个实际 `ualink_endpoint_top(TRANSACTION_MODE=1, WRITE_ENABLE=1)`、实际Switch、后端服务控制及传输流水采用统一同步低有效reset，持续三个上升沿。Auth关闭、port0、默认四槽，信用容量各4、RX_DEPTH160。

测试专用 `write_reset_memory` 从已验证ESE后端复制后独立保存：256-byte数组只在initial清零，**网络reset不清内存，也不清累计执行计数**。reset只取消已接纳但未执行的pending、结果valid和服务控制状态。实际Write握手先保存完整Data/区域BE及slot，70周期延迟后才逐字节写入、累计一次执行并提供结果。Read同样在延迟后读取实际字节数组。这里明确选择本地测试后端的“保留已执行字节、取消未执行请求”策略，不将其冒充标准LinkDown或外部内存系统普遍保证。

旧轮次每端发送一个普通Write256，使用Tag1024和稀疏区域BE；因此在线上需要8个Data半字和最后一个BE半字。旧轮次应用始终背压完成。三个触发窗口均来自实际接口观察，不读取BFM的pending/due私有调度状态：

| 窗口 | 两端实际观察 | reset触发周期 | 正常通过周期 bank3 / bank1 |
| --- | --- | ---: | ---: |
| 1：部分OrigData，尚未BE | 真实600-bit退休握手已交付5/3个Data半字，BE=0/0，后端命令=0/0 | 56 | 696 / 696 |
| 2：组装完成、后端执行前 | Data=8/8、BE=1/1，后端已接纳1/1笔，实际执行=0/0 | 73 | 714 / 714 |
| 3：已执行，应用完成被背压 | 已实际执行1/1笔，两端complete_valid连续背压8周期 | 170 | 818 / 818 |

窗口1/2执行前持续检查字节数组没有副作用。窗口3的旧Write已经修改字节，复位不会撤销这些字节。每个复位沿后检查端点事务/DL占用和有效输出清空、Switch输出清空，同时完整2048-bit内存快照必须等于该窗口的独立保留期望。

## 新轮次因果检查

复位后保留120周期静默窗口，超过后端执行延迟；期间禁止旧完成、旧命令、旧执行和旧结果泄漏，保留字节必须稳定。随后重新启动信用初始化，每端执行9笔请求：

1. 四个真实64B Read读取整个区域：窗口1/2应全零，窗口3应保留旧稀疏Write结果。
2. 再次使用旧Tag1024，发送新的WriteFull256；新数据逐字节与旧模式不同。
3. 四个真实Read检查新Write的完整256-byte结果。

测试只接受来自实际接收器/completer的Response。独立Python字节oracle从应用描述符、数据和BE生成保留内存及逐Read结果fixture；SV后端只执行实际收到的Data/BE，不读取fixture或共享oracle状态。scoreboard观察实际应用预约、真实header_taken、600-bit接收握手、内存命令、执行事件、结果握手和每个complete_valid。Read全512位对照期望，Write完成Data/data_valid必须零，完整Tag/kind/状态关联正确，背压期间整个完成保持稳定。

发送到DUT的请求索引和周期背压计数采用posedge NBA更新，控制reset/start/epoch的激励位于negedge；仅独立观察状态采用blocking更新，避免同沿反馈竞态。这里的epoch只是测试标签，没有写入线协议或生产RTL。

每个正常case：旧轮次2笔预约、0次应用完成，两份旧完成所有权取消；新轮次18笔预约和18次完成。窗口1/2旧Write执行0次，窗口3旧Write执行2次；所有case新Write均实际执行2次。六个正常case合计：旧12预约取消、新108完成、旧实际写4次、新实际写12次，总后端执行16次。`cancelled_results=2`日志字段表示取消的旧完成预约，不表示窗口1/2已经产生过两个结果。

## 正向与反例证据

| label | 配置 | compile/run | 结果 |
| --- | --- | --- | --- |
| `write_reset_first` | bank3，窗口1/2/3 | 各0/0 | 三个 `WRITE_RESET_PASS` |
| `write_reset_minimum` | bank1，窗口1/2/3 | 各0/0 | 三个 `WRITE_RESET_PASS` |
| `write_reset_endpoint_fault` | bank3，窗口3，端点0漏接在途reset | 0/1 | `WRITE_RESET_STATE` |
| `write_reset_endpoint_fault_minimum` | bank1，同上 | 0/1 | `WRITE_RESET_STATE` |
| `write_reset_backend_fault` | bank3，窗口2，后端0漏取消pending | 0/1 | `WRITE_RESET_OLD_BACKEND` |
| `write_reset_backend_fault_minimum` | bank1，同上 | 0/1 | `WRITE_RESET_OLD_BACKEND` |

故障实际把所选模块复位连到仅上电生效的power_rstn：先正常初始化并达到目标窗口，再遗漏统一在途reset。Endpoint故障保留旧完成/预约状态；后端故障让旧请求在静默期执行并产生旧结果。只有编译成功、仿真失败、目标窗口达成且出现指定诊断才算检出，不把启动X或编译错误算功能证据。

## 复现和冻结范围

```sh
python3 verification/endpoint_transaction/run_write_reset.py --label write_reset_new --kd28-root /home/ljy/work/IC/OverFlow
python3 verification/endpoint_transaction/run_write_reset.py --label write_reset_min_new --kd28-root /home/ljy/work/IC/OverFlow --bank-depth 1
python3 verification/endpoint_transaction/run_write_reset.py --label write_reset_ep_fault_new --kd28-root /home/ljy/work/IC/OverFlow --stage 3 --fault endpoint_reset
python3 verification/endpoint_transaction/run_write_reset.py --label write_reset_backend_fault_new --kd28-root /home/ljy/work/IC/OverFlow --stage 2 --fault backend_cancel
```

故障命令可追加 `--bank-depth 1`。所有路径从脚本所在工程解析，KD28五个依赖文件先按manifest核对后使用同一份已读bytes保存快照。每个label输出完整源码/runner/manifest快照、各窗口fixture、compile/run日志、命令及result.json；目录已存在即拒绝覆盖。

六个label的212份源码快照分别与记录一致；正常label各239份制品，fault label各221份制品全部哈希核对通过，审计文件为 `write_reset_first/audit.json`。核对时另一并行任务已扩展Read相关生产文件：read_completer、read_encode、response_encode、tag_table与部分早期快照存在差异。因此本报告结论严格对应各result.json所列实际仿真快照，不声称已验证尚在修改的最新完整Read总装；该总装冻结后应复跑此兼容矩阵。

| 本次新增源文件 | SHA-256 |
| --- | --- |
| `verification/endpoint_transaction/write_reset_tb.sv` | `af4b29812e3f97d9abae463198dc6044c3ecbf6fc38b033ae756cccdcd45e94c` |
| `verification/endpoint_transaction/run_write_reset.py` | `6a722dfd40f88336ac65500156233ce6ba372485af8923f743be54caf79a5952` |

测试只覆盖上述Write256/WriteFull256与既有Read64混合、规定窗口和有限静默观察期；不穷举全部长度、错误状态或所有复位相位。已执行字节不rollback是测试后端的明确策略，不能据此推导外部多拍内存的原子性或断电持久性。统一清除所有网络参与方不等于单端独立LinkDown、迟到旧包隔离或标准epoch协议。链路仍为本地数字DL记录和显式CRC状态，不补写A19、framing、PHY或认证能力。
