# 实际发送SRAM缓存阶段审查

新增 `tl_tx_data_fifo` 和 `tl_tx_buffered`，在实际 Request/Response 选择器之前接入两类独立的头部/标签 SRAM FIFO 及 Data/BE SRAM FIFO。输入入队与线上发送消费分开确认，Data FIFO 中的旧尾仍由已接纳头部所属类别提供。当前输入仍是准备好的 Control、标签和按类排序的半 Flit，尚非完整 UPLI 事务格式转换器。

## 容量与接口

每类头部和其标签一起保存为512位字，每个数据 bank 保存256位半Flit；两bank交替存放有序半Flit，支持每拍提供或消费一项、两项。所有SRAM、在途读取和输出缓存都计入精确逻辑容量。头部深度与每个数据bank深度范围1至65535；两类容量独立，不借用同拍消费刚释放的空间。

实际最小深度测试发现初版原子两项入队会死锁：总容量2、已有1项，生产者等待两个空位，而发送器等待两项负载。最终接口增加 `o_write_taken` / `o_data_accepted`，按当前空位允许只接纳提议中的第一项，上游必须保留剩余项并按实际接纳数量推进。`o_data_ready`只表示至少能接纳一项，**不能据此丢弃整个两项提议**。总容量保持2；没有提高默认信用或丢弃事务来掩盖问题。

`o_header_taken/o_data_taken`仍观察线上实际消费；它们不能代替上游入队确认。Auth开启时，头部入队同时要求标签有效，并与头部原子保存。Auth关闭时标签值不参与线上发送。配置与FIFO/端口必须共享复位时期；复位丢弃旧本地缓存所有权，物理SRAM内容无需复位。

## 实际验证及失败记录

| 模式 | 配置数 | 头部消费 Request / Response | SRAM接收字消费 | FC及初始完成消息 | 循环数 |
|---|---:|---:|---:|---:|---:|
| 头部深度2、每bank深度3，正常 | 16 | 960 / 960 | 5,960 | 3,572 | 8,356 |
| 同深度，Request队首超容量 | 16 | 0 / 960 | 2,616 | 2,380 | 6,836 |
| 同深度，Response队首超容量 | 16 | 960 / 0 | 3,328 | 2,630 | 7,320 |
| 头部深度1、每bank深度1 | 16 | 960 / 960 | 5,962 | 3,428 | 12,548 |
| 头部深度3、每bank深度5 | 16 | 960 / 960 | 5,966 | 3,544 | 7,832 |

每组配置为 WIDTH8/16 × Auth0/1 × Shared0/1 × 数字链路延迟1/3；生产者插入有界供给间隙，消费端和线上发送端也有停顿。最小和较大深度使用带端点/类别/头部索引的非零标签；未使用标签槽保持零，不代表实现密码认证。原非零标签夹具填充了未使用槽而被实际端口拒绝，按 Common 2.0 §5.1.1修正，失败证据保留。

独立审计从实际线上字段重建各类头部、Data/BE所有权和信用释放，与真实600位接收SRAM逐字比较；再将独立队列观察与线上观察关联，逐拍验证入队/消费索引、`入队数－实际发送数＝实际占用`、精确深度、部分入队数量、停顿保持和最终信用守恒。两类阻塞场景保留满头部/数据缓存，被阻塞类从未确认线上消费；相反类别完全排空。这只证明对向类别在该负载下独立前进，被超容量阻塞的事务仍未完成。

FIFO另有6种每bank深度1、2、3、5、129、257，真实KD28 SDP模型参与读延迟、非二次幂回绕、满队列、非法消费、复位和持续两半Flit带宽测试。每种有9000次混合刺激循环及额外定向填充/排空，不能把循环数当作完整原始时钟沿统计。深度5观察连续56拍双消费，深度129/257分别310/574拍；这不是完整链路性能或工艺频率签核。

6种FIFO故障各6深度，共36次实际负例：写bank相位丢失、读bank相位丢失、bank数据错序、部分入队丢失、非法消费仍释放和遗漏bank计数。首轮有4个配置未检出故障，补入“仅余一个空位时提议两项”和“有效缓存上非法消费”定向场景后全部检出，未更改RTL或期望值放宽判据。另有40次双端负例：提前弹出头部16配置、确认错误类数据16配置、绕过已保存标签8个Auth配置。原始失败、通过和未检出记录均保留。

严格Verilator lint两宽度通过。默认头部深度2、每bank深度3的Yosys通用综合为101,243/102,043 cells，均4,174 FF位及64个KD28 SRAM宏实例。该数量包含缓存/选择器/packer依赖，不含实际信用端口与接收SRAM；所有FF与SRAM读写端口使用i_clk，无锁存器或新增异步控制复位。SRAM宏是获授权行为模型及对应黑盒映射，仍非真实工艺宏签核，未执行此新顶层工艺STA。

Artifact技能门零错误、10项风格建议，使用现有紧凑分组与原生本地接口，并非AXI。全局技能自检实际失败于外部缺失 `agents-md-generator/scripts/manage_docs.py`。初版检查在接口修正时被主动终止；最终检查复用相同源码哈希的已完成综合/双端负例。汇总脚本曾因复用结果变量与变异字符串重名报错，修复后从已结束、源码哈希一致的负例记录恢复汇总，无需重跑已完成EDA。误在工作根目录启动的一次兼容回归被明确终止，日志保留，兼容声明以干净导出作业为准。

干净导出中的 `make test rtl-smoke tx-sram-smoke` 已实际完成，退出码0；当前全部RTL与Makefile逐字节匹配导出副本。FIFO新增定向覆盖在导出中单独复跑，最终审计脚本普通Python与 `-O` 均通过。

初版两份RTL已从保留的编辑差异重建，并逐份与初轮实际编译记录的SHA256精确匹配，保存在本地 `initial_sources/`。所有作业结束后删除345份编译字节码，约1.63GiB，保留失败/通过日志、TB、输入、追踪与综合图。

## 复跑与完整目标

```sh
python3 verification/tl_tx_buffered/test_model.py
python3 verification/tl_tx_buffered/run_fifo.py --kd28-root /authorized/Overflow
python3 verification/tl_tx_buffered/run_peers.py --kd28-root /authorized/Overflow --label none_final
python3 verification/tl_tx_buffered/run_peers.py --kd28-root /authorized/Overflow --blocked request --label request_final
python3 verification/tl_tx_buffered/run_peers.py --kd28-root /authorized/Overflow --blocked response --label response_final
python3 verification/tl_tx_buffered/run_peers.py --kd28-root /authorized/Overflow --bank-depth 1 --header-depth 1 --tag-pattern --label minimum_final
python3 verification/tl_tx_buffered/run_peers.py --kd28-root /authorized/Overflow --bank-depth 5 --header-depth 3 --tag-pattern --label deeper_final
python3 verification/tl_tx_buffered/run_checks.py --kd28-root /authorized/Overflow
python3 verification/tl_tx_buffered/run_skill_gate.py --skill-root /path/to/verilog-generator
python3 verification/tl_tx_buffered/check_evidence.py
make test rtl-smoke tx-sram-smoke KD28_ROOT=/authorized/Overflow
```

输出位于 `build/verification/tl_tx_buffered/`。完整复跑与smoke各自使用干净导出，已有结果目录默认拒绝覆盖；`--reuse-checks`及`--resume-fifo`仅用于源码身份验证后的明确恢复。下一步仍需容量感知UPLI处理、每VC独立性、超容量事务完成、Poison及其余消息、完整参考/在线资源归纳、新顶层工艺STA和完整Endpoint/Switch其余模块。该阶段不缩减完整双IP目标。
