# UPLI 信用校验与返回保护适配契约

本轮范围为 `upli_credit_guard`、`upli_credit_return_adapter` 两个组合候选，开发目录 `build/development/upli_credit_adapter/`；不改生产 RTL、公共 parity、receive_channel 或库存。Common Rev 2.0 §2.6、各原生通道返回信用表与 §3.1.1，及 `docs/upli_station_integration_execution.md`、`docs/upli_model_contract.md` 的信用/parity 小节是依据；这里只记录自主释义，不复制私有正文。

每个通道的原生返回字段为 CreditVld4、CreditPool4、CreditVC8、CreditNum8、CreditInitDone4，低两位组对应 port0。Valid parity 每周期保护全部4个 valid；只要任一 valid 为1，control parity 就检查完整 Pool4/VC8/Num8 共20位，包括本沿没有返回的 port 字段。InitDone 不属于这两组保护。数量解释、账户容量、初始化过滤、归还凭证与错误处置归既有 bank/RX 或 station 策略。

`upli_credit_guard` 无 clk/reset/内部状态，输入 `i_check_enable`、`i_credit_valid[3:0]`、`i_credit_pool[3:0]`、`i_credit_vc[7:0]`、`i_credit_num[7:0]`、`i_credit_valid_parity`、`i_credit_parity`；输出 `o_valid_error`、`o_control_error`、`o_error`、`o_integrity_ok`。它不接 InitDone，也不输出过滤后的信用。check_enable=0 时 errors=0、integrity_ok=1，表示检查使能限定下未报告失配，不能解释成信用、账户、初始化或连接许可。Valid=0 而 valid parity 错仍须报错；control 组只按任一真实输入 valid 使能。

`upli_credit_return_adapter` 无 clk/reset/enable/ready；输入 `i_credit_valid/pool/vc/num/init_done`，输出对应同宽 `o_credit_*`，全周期逐位直接透传，并新增 `o_credit_valid_parity`、`o_credit_parity`。不增加寄存器、延迟或TDM过滤，不按valid屏蔽原字段，不把InitDone混入parity。实际RX同步reset后驱动的注册返回总线直接经过此模块；适配器不自行取消已驱动的信用。

两个模块各真实实例化一次公共 `upli_parity`，固定 CHANNEL_KIND=0，非信用 valid/control/address/auth/data/BE 全零。guard 的 received_parity[14:13] 接收到的两保护位，低13位0；primitive check_enable 取本地输入；只解释 errors[14:13]。adapter 关闭检查、received全零，由 primitive parity[13]/[14] 直接驱动两输出。不得重复 leaf XOR，也不能用误接非信用输入制造伪通道错误。

验收先保留接口一致但无能力的本地红测，随后独立 Python population-count oracle 检查每个控制位、所有 valid 组合、enable/received parity、InitDone任意变化和 idle 原始字段。真实 `upli_receive_channel`、`upli_credit_bank` 和授权 KD28 SRAM 参与返回集成，以实际接收/消费事件的独立 journal 检查初始化、原VC/Pool正常归还和已保存payload；不以DUT pending队列或内部计数构造期望。1/2/4端口、两轮reset、实际wire故障、g2001/严格lint/Yosys与源码hash单列证据。

故障输出只证明检出；本轮不选择坏信用丢弃、银行冻结、尾部截断、Isolation、认证或LinkDown恢复策略。未执行的测试不标通过，最终证据与可发布入口追加于本文件。

## 已执行结果与冻结材料

候选已完成，生产文件和库存仍未修改。可安装文件在 `build/development/upli_credit_adapter/release/rtl/upli/`，可发布验证文件在该 release 的 `verification/upli_channels/`。`freeze.json` 记录全部六份交付文件与公共依赖 SHA256，并逐份核对最后八个证据目录的210个产物，零缺失、零 hash 差异。两个 RTL 与发布副本逐字节相同。

| 文件 | SHA256 |
|---|---|
| `upli_credit_guard.v` | `2acb855aafc6a3570675ad8a103ac99a999ca97ce31b1447cfb3390447ae8bc6` |
| `upli_credit_return_adapter.v` | `a18cd146b85824cb4f375e86ab832a5b0e451d2b0cdc32669be2dc91a0083199` |
| `run_credit_adapter.py` | `cb082ae4a11c5b0cfa003533c1d76b4e97b54f191e9471694d769b6458fd8a7c` |
| `credit_adapter_tb.sv` | `a77b5e28704db4d0cc1177732b05024539c31622479519fd3f1540ddd91038a0` |
| `credit_adapter_receive_tb.sv` | `256d6c22706c25e811d1fc81e9f9208012cde438e9a7643d217b3336c155ca2f` |
| `credit_adapter_reference.py` | `79f7654130175f116991021fbc1a9a75e400cb5a11387cedd62a353a98ca90bb` |
| 已有公共 `upli_parity.v` | `9e12e67c72e50616d5298616d0cabf3e551c8fd7df360ed7c00c722266c32c94` |

红测 `guard_red` 和 `adapter_red` 使用本地新建、端口一致的无能力壳，分别编译0/运行1，在实现前被对应字段 checker 检出；这不是已有生产模块的功能缺陷。正常单位测试3418行：20个控制位逐位×16种valid×2种check_enable×4种收到的保护位翻转，共2560行；16种valid×16种InitDone共256行；600行固定种子随机与2行固定边界。独立 Python 用 population-count，不调用生产模型或公共 parity。此覆盖是逐位与规定交叉，不宣称穷举20bit全部取值。

最终实际标签位于候选 `release/build/verification/upli_channels/credit_adapter/`：

| 标签 | 实际结果 |
|---|---|
| `credit_adapter_release_p1` | unit3418通过；1port、两轮各15次接收/消费/返回，总30；每轮60周期 |
| `credit_adapter_release_p2` | unit3418通过；2port、两轮各30，总60；每轮94周期 |
| `credit_adapter_release_p4` | unit3418通过；4port、两轮各60，总120；每轮162周期 |
| `credit_adapter_release_guard_valid` | 实际把guard检查enable错误依赖任一valid；编译0/运行1，row1 idle valid保护错误被 `CREDIT_GUARD_COMPARE` 检出 |
| `credit_adapter_release_guard_mask` | 实际 primitive Pool 输入按valid遮蔽；编译0/运行1，row318未激活端口控制保护差异被检出 |
| `credit_adapter_release_init_fault` | 实际把InitDone异或入 primitive Pool；unit编译0/运行1；1port真实RX链路编译0/运行1，cycle9 `CREDIT_RETURN_PARITY` 检出 |
| `credit_adapter_release_gate_fault` | 实际把返回valid按InitDone门控；unit编译0/运行1；4port真实RX链路编译0/运行1，cycle4 `CREDIT_RETURN_DIRECT` 检出初始信用被取消 |

每个正常配置均实际编译运行现有 receive_channel、storage/FIFO、initializer、return_queue、credit_bank 与五份外部 KD28 SRAM/model 文件。每账户逻辑容量3，四个专用VC和共享Pool都接收实际payload；Pool字按原始VC0/1/2归还。TB从原生send、实际consumer握手和返回事件建立独立队列，完整比较SRAM读头payload/VC/Pool、先前退休凭证、初始化总量、bank注册余额、最终排空。返回检查先于当沿退休journal追加，不能用同沿退休凭证伪造归还；sender也不能借同沿新返回。raw注册返回与adapter输出在采样沿前、RX NBA更新后均核对。所有驱动在负沿准备；周期/计数不在组合ready或候选路径反馈，正常背压周期7与5/10/20账户扫描互素，避免遗漏账户。

历史 `receive_first` 保留一次TB排空失败：旧4周期ready与20账户扫描同余，使部分账户永久被背压，只消费45/60。改为上述7周期后 `receive_second` 及最终三配置通过；未为此改动RTL。两轮reset均在前一轮排空后执行，证明重新初始化、payload更新和资源重建，**不宣称本任务验证了在途reset/独立LinkDown**。

每个正常配置对两新增RTL单独执行 Icarus `-g2001`、Verilator `--Wall --language 1364-2001`（无豁免）、Yosys `hierarchy -check; proc; check -assert`，全部exit0。保存的Yosys结构逐项确认每个leaf只有一个实际公共primitive、无leaf `$reduce_xor`/寄存器/锁存器/存储、所有非信用输入及received低13位为零；guard错误输出直接接errors[13]/[14]，adapter保护直接接parity[13]/[14]且全部五组返回字段net ID与输入相同。完整SRAM集成执行的是Icarus仿真；这里不冒称完成其新的全路径STA、物理综合或无条件吞吐证明。

技能静态检查 `skill/final_comment_fixed` 两leaf均0 errors/9模板样式warnings，注释门禁分别36/36与39/39通过。第一次artifact检查要求模块声明注释明确写“模块”，修正两条注释后重跑，功能代码未改。安装级 `validate_verilog_skill.py` 实际exit1，仍在进入后续清理前因缺少 `/home/ljy/.codex/skills/agents-md-generator/scripts/manage_docs.py` 失败；单独记录安装门禁HOLD，不将它计为RTL或仿真通过。

安装后可从任意cwd调用脚本，默认工程根为runner自身 `parents[2]`：

```sh
python3 verification/upli_channels/run_credit_adapter.py --label NEW
python3 verification/upli_channels/run_credit_adapter.py --label NEW_RX --integration --ports 4 --kd28-root /path/to/authorized/checkout
python3 verification/upli_channels/run_credit_adapter.py --label NEW_FAULT --fault adapter_gate --integration --ports 4 --kd28-root /path/to/authorized/checkout
```

输出为工程 `build/verification/upli_channels/credit_adapter/LABEL/`。runner与两个TB、独立reference均必须安装；不安装 `__pycache__`、开发证据或未实现红测壳。公共parity以及真实RX依赖沿用已有生产文件；可通过显式 `--rtl-dir`、`--project-root` 覆盖来源用于候选验证，默认路径不依赖development。

最终从 `/tmp` 调用独立 `portable_project/verification/upli_channels/run_credit_adapter.py --label portable_release --integration --ports 4 --kd28-root /home/ljy/work/IC/OverFlow`，未提供候选路径覆盖：unit3418、全部外部静态检查和真实RX两轮120次返回均通过。该验证工程只包含公开工程源副本及依赖清单，五份KD28外部源始终直接只读使用，按 `third_party/kd28_dependency.json` 在运行前后核对一致，不复制发布外部模型。

下一步由root安装两模块和验证材料，并在station TX总装接真实返回组及诊断；是否屏蔽失配信用、停止新候选或处理已预约尾部仍由后续明确错误策略决定，本增量不自动选择。
