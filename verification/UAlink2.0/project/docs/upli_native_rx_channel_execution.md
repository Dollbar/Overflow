# 原生 RX 保护、poison 与外部 Drop 候选

本候选落实 `docs/upli_native_rx_execution.md` 第4A的四种通道保护接收路径。依据 Common Rev2 §2.6、§3.1.1–3.1.4 及 §4.1–4.3 的已审查条款，复用现有 `upli_ordered_receive_channel`、其内部唯一 `upli_receive_channel`、真实 KD28 SRAM 和 `upli_credit_return_adapter`；不复制私有正文，不把独立角色恢复或完整 RX 事务组装声明为完成。

## 接口和作用域

`upli_native_rx_channel` 的 `CHANNEL_KIND=0/1/2/3` 分别是 Request184、ReadResponse619、WriteResponse101、OrigData580；字段布局沿用上级执行契约，不改变原生线字段。`C_PAYLOAD_WIDTH` 默认按 kind 推导，错误显式宽度拒绝展开。`C_NUM_PORTS` 仅1/2/4；信用宽度/逐账户容量/return深度/pending宽度/order宽度直接传递到已有真实存储所有者。

`i_clk/i_rstn` 是同域时钟及同步低有效共同 reset。原生 `i_valid/i_port/i_vc/i_pool/i_payload/i_received_parity[12:0]` 没有 ready。`o_receive_accepted` 沿用底层上一沿真实写入观察语义，不能拿来当沿前准入资格。`i_consumer_port/i_consumer_ready` 只选择端口；账户由本端口最早接纳项的 journal 决定。公开 `o_consume_valid && i_consumer_ready` 与底层 SRAM、journal 及原信用记录的退休是同一事件。

`i_auth_enabled` 为本地 profile 配置，在仍有存储所有权期间须稳定。未启用且 Auth 非零产生独立 `o_auth_profile_error`；启用后完整 Auth 可以保存/投递，仍检查 Auth parity，**不表示密码学认证已通过**。非零 Auth 没有被永久禁止，也没有转成 DataError 或某个 Response Status。

`i_drop` 必须来自唯一角色/TL故障所有者，本模块没有另一份 Drop latch。入口或头部 control/Auth/profile 错误、头元数据错配、顺序错误、注册存储诊断会请求 `o_fault_stop_request`；其当前组合结果和 i_drop 同时禁止本通道新保存和业务退休。`o_control_error/o_data_error/o_auth_error` 保留原始分类，额外 profile/metadata/storage 条件不伪装成标准错误编码。注册 `o_storage_diagnostic` 参与门控不会形成组合环。

## 真实保护路径和信用边界

每侧实际实例化 `upli_native_rx_protection`：先用公共 primitive 检查收到的13位码，再将 data/BE 错误 OR 到本拍 poison，最后用第二个公共 primitive 建立归一化后保护。入口错误诊断不因没有成功接纳而消失。valid=0仍检查valid parity；control/address属于控制错误；完整512位的八个组及OrigData完整BE64属于数据错误。已有poison、零BE、未选lane、错误Status不能屏蔽检查，Status也不自动生成poison。

真实 SRAM 保存 `{port2,vc2,pool1,parity13,normalized_payloadW}`，共W+18位；底层原有VC/Pool仍保存。出队按封套重新检查原码，交叉核对封套port/VC/pool、所选账户与真实FIFO元数据。控制/Auth坏头保持所有权，不能退休或归还；头data/BE错误保留实际数据并置本拍poison、重新生成完整保护后可投递。首阶段无 poison 写后端适配器，不能直接把这份poison写请求作为普通写执行。

Drop 阻止新保存/业务退休，既有可信返回队列自然排空；坏拍不制造信用，也不根据不可靠Port/VC/Pool补还。初始化器和返回适配器的真实已登记输出直接保留，没有借Drop伪造connection断开或reset。本次Drop试验发生在初始化完成后；初始化未完成即Drop的角色政策尚未闭合，不能据此声称完整Drop恢复。Isolation的继续收返信用、watchdog、dummy CMPTO、ISOLATE通知、未完burst处理、TL双角色故障范围及管理恢复均未实现，须由后续角色所有者落实。

存储封套不证明地址、FIFO指针/计数/valid/选择控制的全部保护；这些既有控制路径RAS仍开放。Parity也不等于ECC或认证。共同reset清除有效所有权和归还记录，保留宏内部旧数据不产生旧完成；它不是独立LinkDown恢复。

## 独立验证与结果

Python参考不导入RTL helper或旧模型，按不重叠字段逐位计算parity并产生完整期望payload。TB负沿驱动、沿前检查诊断、NBA后核对真实accepted；独立整数归还账本检查初始容量及实际退休的原VC/pool数量。四kind × 1/2/4共12配置，实际每账户容量3、信用宽度4、返回深度4；不把这组容量配置当作全部继承参数覆盖。

| kind | 每配置向量数 | P1/P2/P4 实际向量接纳与退休 |
|---|---:|---|
| Request | 500 | 387 / 384 / 388 |
| ReadResponse | 1386 | 1281 / 1274 / 1282 |
| WriteResponse | 334 | 229 / 218 / 223 |
| OrigData | 1308 | 1265 / 1268 / 1270 |

每次最终矩阵共10584输入向量、152957采样沿；9469向量被实际接纳并退休。额外定向测试共60次接纳：48次退休，12次由reset取消。覆盖完整payload逐bit、启用/未启用Auth、各parity位及valid闲置规则、八组数据错误、零BE/已有poison、全VC/pool、背压、真实三项容量满与第四项拒绝、未配置Port拒绝、外部Drop阻断及可信旧归还排空。

头故障在**真实已排队项的SRAM读出封套路径**施加定向瞬态force：注入值从外部已知零记录构造，不读取DUT存储作为oracle。控制/Auth坏头不投递不退休；同时更新控制parity的Port错配仍由元数据核对发现；data/BE坏头逐拍置poison并输出正确新码。该试验是存储读出路径故障，不冒称真实宏位翻转物理注入。

另有六类隔离源码注错：忽略control gate、清掉poison、BE保护输入接零、返回pool错误、绕过坏头退休gate、绕过Drop gate。全部只改源码快照，compile返回0、VVP返回1，并由明确RX checker检出。`fault_matrix.json` 保存每条实际命令，最终结果为 `frozen_control_gate/frozen_poison/frozen_byte_enable/frozen_credit_pool/frozen_head_retire/frozen_drop_gate`，没有把工具失败当注错成功。

最终 `frozen_final` 与 `frozen_optimized` 普通/-O矩阵均通过且向量逐字节一致。每次12配置的g2001、无豁免Verilator `--lint-only -Wall`、完整实际层级Yosys检查全部通过；网表确认唯一ordered/receive/return队列、两个保护helper、五个公共parity实例及真实KD28模型，零latch。外部 `kd28_sram_cells.v` 含多个模块，其原始文件触发DECLFILENAME；仅lint把原模块正文连同相同header/footer分成对应文件名，未改任何HDL语句或外部源、未加警告豁免，`lint_split_manifest.json`记录原文及派生hash。仿真/g2001/Yosys仍使用原始完整外部文件。

技能artifact检查：保护leaf通过；纯层级wrapper初次套叶模块时钟/复位敏感表规则失败，随后以“无本地寄存状态”的真实wrapper职责检查通过，实际子模块clock/reset由全层工具和reset试验验证。两模块最终0error/0warning。整套技能仓库自检会修改候选目录外状态，本轮未运行，不声明该门限通过。缺模块红测、初轮外部文件名lint失败、错误KD28路径导致的 `fault_be` 编译失败都保留；后者不计注错检出，正确路径重放及最终byte_enable注错才计通过。

## 冻结和复跑

候选两RTL SHA256：

- `upli_native_rx_channel.v`：`6a900513d14504a887795ddd1d8acc25d187642ed52d6fe30e55debe7a366b12`
- `upli_native_rx_protection.v`：`c7535c9fa049ac502f082dda8b37be79638db6673fd6ca2a5d46469edc76afbd`

候选根 `build/development/upli_native_rx_channel/freeze.json` 列出全部六个可安装文件及SHA。仅复制 `release/rtl/upli/` 两RTL、`release/verification/upli_channels/` 三脚本/TB文件以及本文。不要复制测试build证据或历史生成脚本到生产。

实际最终命令在项目根执行：

```sh
python3 build/development/upli_native_rx_channel/release/verification/upli_channels/run_native_rx.py --label frozen_final --kd28-root /home/ljy/work/IC/OverFlow --project-root /home/ljy/work/IC/UALink --candidate-dir build/development/upli_native_rx_channel --static
```

`python3 -O` 使用label `frozen_optimized`。再次复跑须使用未存在的新label。生产入口 `ROOT=Path(__file__).resolve().parents[2]`，安装后的正常命令：

```sh
python3 verification/upli_channels/run_native_rx.py --label NEW --kd28-root /path/to/authorized/kd28/root --static
python3 verification/upli_channels/run_native_rx.py --label NEW_FAULT --kd28-root /path/to/authorized/kd28/root --kind 3 --ports 4 --fault poison
```

生产产物在 `build/verification/upli_channels/native_rx/LABEL`。源码先读同一份bytes后快照/计算hash，保留实际编译命令和run码。下一步由主线接唯一角色Drop所有者，再实现Req/OrigData关联；本交付不是端到端事务桥、完整Isolation、标准认证或STA。
