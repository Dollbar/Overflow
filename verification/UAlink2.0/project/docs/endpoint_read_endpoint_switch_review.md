# 完整普通 Read / Write 经 Switch 的实际端点验证

本次新增 `verification/endpoint_transaction/run_read_endpoint_switch.py`、`read_endpoint_switch_tb.sv`；没有修改生产 RTL、既有 Write ESE 或公共 VIP。冻结契约为 `docs/endpoint_read_execution.md`，规范来源由 `docs/endpoint_read_contract_review.md` 逐项说明。Icarus 实测三个正常场景、两个实际故障场景通过预定判据；没有发现阻断本 profile 的生产问题。

## 实际连接与独立检查

两个 `ualink_endpoint_top` 均开启 `TRANSACTION_MODE=1, WRITE_ENABLE=1, FULL_READ_ENABLE=1`，分别以本地 ID 17 / 513 接真实 `ualink_switch_top`。每端统一 Tag 容量 4、Read/Write completer 容量各 4；`RX_DEPTH=160`，20 类信用容量各 4，`BANK_DEPTH=3/1`。Switch 中传输的 545 位记录是本地数字接口 `{显式CRC状态,544位DL记录}`，不是标准串行线格式；没有构造 A19 CRC 位序。

请求由实际应用握手预约，经真实 TL/DL 发出。检查器观察实际 `u_tx.o_header_taken[0]` 和解码后的 Tag / 57 位地址，接着分别观察公开的 Read / Write 内存命令、实际字节执行脉冲、延迟结果握手、receiver 向 Tag 表交付的每个完整 512 位响应 Beat，以及应用端首次 `complete_valid`。没有预生成 Response，也没有把 `source_captured` 当成实际发送。

测试内存只保存实际收到的命令、2048 位 Write 数据与区域 BE，17 个本地周期后按字节更新 256 字节内存。Read 命令保存后延迟 9 个周期返回实际内存的 N 个自然对齐 Beat；其余返回位置填 `D7`，N 个 Beat 中未选择的字节也保留实际非零内存值。Read 状态是明确的测试注入，按独立 NBA 更新的 `memory_issue` 选择并在命令握手时保存。BFM 不读取任何期望数据文件，不共享 pending / due 状态给 scoreboard。

Python oracle 用独立 `bytearray` 累积程序的写入，按首末 DWORD ATTR 构造区域 BE 和相对 Beat 掩码，生成未掩码原始返回与应用 masked 结果。检查完整后端 2048 位数据及状态；成功响应的每个有效字节；应用完整 2048 位结果、256 位 mask、低 512 位兼容视图及 `data_valid`。未选应用字节和错误完成的全部数据 / mask 必须为零。成功零 BE 的 Read 仍必须完成一次且 `data_valid=1`。

每个 Read 的 single 模式响应均要求 LEN=0、OFFSET 从 0 到 N−1、仅最终 Beat LAST=1、状态一致。首次和被背压保持的每个 `complete_valid` 都要求：实际后端结果已在更早周期握手，N 个响应 Beat 全部交付，最后 Beat 也发生在更早周期。每个原始请求只允许一个后端结果和一次应用退休；Write 还要求真实执行恰好一次。有限反压后所有 Tag / completer / DL outstanding 与 scheduled 计数排空。

会影响 DUT 输入的 cycle、requested、memory_issue、originals、drop / CRC 标志均以 NBA 更新；初始 reset / start 在 negedge 驱动。blocking 的 owner / cursor / coverage 变量只供观察，不反馈组合 ready 或 BFM 注入状态。独立只读审查见 `docs/endpoint_read_reset_test_audit.md`。

## 覆盖和实测证据

基本程序每侧 14 个事务：WriteFull256 后不同起点、长度、ATTR 的 Read；普通五状态 0 / 2 / 3 / 6 / 8 各一个完整 256 字节 Read；普通 Write 在地址 60 跨 Beat 稀疏更新后再次 Read 校验。两侧实际写入不同数据，不能交换方向误通过。

矩阵每侧 406 个事务，在基本程序上增加：64 个合法 Read 长度 4..256 字节；64 个 DWORD 起点的代表性合法长度；LEN0 的全部 256 个 ATTR；132 字节跨 Beat Read 的 8 种首末稀疏 ATTR。它覆盖 64 长度和 64 起点的代表组合，不是 2080 个全部合法几何的 ESE 全交叉，也不是每个长度的全部 256 ATTR。五状态测试都需要收到 4 个 Beat，错误不能提前完成。

所有结果位于 `build/verification/endpoint_transaction/<label>/`：

| label | 配置 | compile / run | 实测 |
|---|---|---|---|
| `read_ese_legacy_profile_red` | 默认 FULL_READ_ENABLE=0、实际 core 收 Read4 | 0 / 1 | `READ_FULL_UNIMPLEMENTED`，旧兼容 profile 明确拒绝该新请求 |
| `read_ese_first` | 基本、bank 3 | 0 / 0 | 28 请求 / 28 完成；Read 每侧 34 Beat；Write 每侧执行 2；1380 周期 |
| `read_ese_matrix_first` | 矩阵、bank 3 | 0 / 0 | 812 / 812；Read 每侧 619 Beat；Write 每侧执行 2；21571 周期 |
| `read_ese_minimum_first` | 矩阵、bank 1、drop / CRC 注入 | 0 / 0 | 812 / 812；Read 每侧 619 Beat；Write 每侧执行 2；双向 replay 各 4；21658 周期 |
| `read_ese_mask_fault_first` | 实际 Tag RTL 副本移除逐字节 mask 条件 | 0 / 1 | 首个 4 字节 Read 的应用 `READ_ESE_COMPLETE_DATA` 检出未清零字节 |
| `read_ese_upper_fault_first` | 实际后端结果接线清零高 1536 位 | 0 / 1 | 跨 Beat Read 的实际 receiver 数据比较检出 `READ_ESE_COMPLETE_DATA` |

故障样本 `passed=true` 表示编译成功且真实运行按指定诊断失败，不表示变异设计正确。mask 故障只修改留存副本，result 中记录原始哈希与变异原因；生产文件未修改。红测运行的是新增完整能力仍关闭的实际兼容分支，不把它描述为新 RTL 尚未存在的 Git 历史版本。更早 `read_ese_legacy_red` 因 runner 向无参数 baseline TB 传参数而 compile=5，仅保留失败排查证据，不计为功能红测。

每个正常 / fault 场景留存 212 个 source 映射、225 个制品哈希，包括实际编译的 RTL、5 份 KD28 依赖模型、TB、runner、逐字节 fixtures、日志和 vvp。依赖先验证 `third_party/kd28_dependency.json` 的固定哈希；每个源从同一份读取 bytes 写副本并求哈希。6 个正式 label 的已声明全部制品与 source 映射复核零差异，见 `read_ese_matrix_first/audit.json`。汇报时三个正常场景和 upper 接线故障的原始源均与工作区相同；mask 故障只有刻意修改的 Tag 副本不同。

冻结 TB SHA256：`583a8ebce3c5ac31b7ac634d7a1be56dd81aa70c21cb2c178775141cc9a5782b`。
冻结 runner SHA256：`aca85e57097b7329acbde25f5af90a542eb78b6aa777fa32d13801fde7a9cd74`。
本轮 core / top SHA256：`653ac977dd76d7ad37a2252a22e2a232fecc74638f36f3b304c77a4f2911eeec` / `7d825d1bf95addc1004605469cb38e563e4c2d9487bef9a61474e9e974b16a9a`；其余准确 RTL 身份见每个 result 的 sources。

## 可重现命令与边界

独立工程根目录：

```sh
python3 verification/endpoint_transaction/run_read_endpoint_switch.py --label NEW_READ_MATRIX --kd28-root /home/ljy/work/IC/OverFlow --matrix
python3 verification/endpoint_transaction/run_read_endpoint_switch.py --label NEW_READ_RECOVERY --kd28-root /home/ljy/work/IC/OverFlow --matrix --inject --bank-depth 1
python3 verification/endpoint_transaction/run_read_endpoint_switch.py --label NEW_READ_MASK_FAULT --kd28-root /home/ljy/work/IC/OverFlow --fault mask_ignored
python3 verification/endpoint_transaction/run_read_endpoint_switch.py --label NEW_READ_UPPER_FAULT --kd28-root /home/ljy/work/IC/OverFlow --fault upper_data_lost
```

Overflow 发布布局先 `cd verification/UAlink2.0/project`，同一命令的 `--kd28-root` 改成 `../../..`。label 必须全新，runner 不覆盖旧证据。下一步应结合完整 Read 的 encoder / completer / Tag / receiver 单元结果和历史兼容回归审核；生产代码若再变动，以上快照不自动证明新版本。

本次只证明默认 4 槽、固定本地端口 0、两个 ID、低 256 字节测试内存及普通 Read / Write、Auth=0 的已定义数字边界。single 响应 TX 的真实回环不代替 multi 响应 RX、跨 Tag 乱序等独立验证。没有覆盖高地址后端映射、原生 UPLI、poison、独立 LinkDown / epoch、认证、实际 CRC 算法 / PCS / FEC / SerDes、PPA 或形式证明，也不把这个集成结论扩大为完整 Endpoint / Switch IP 已交付。
