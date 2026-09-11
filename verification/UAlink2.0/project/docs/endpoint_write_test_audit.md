# Write 集成测试独立审查

本审查只读检查两个新 runner、对应 SystemVerilog TB 及已有回归记录；没有修改生产 RTL 或测试，也没有重复运行其他代理正在执行的仿真。结论适用于下表源码身份，不能外推为完整 UALink 协议或形式证明。

## Oracle 与实际完成

双 core 测试的 Python 参考直接按应用字节、区域 BE 和操作顺序更新独立内存，预先生成每次 Read 和最终内存预期。SV 后端先核对 RTL 实际提交的字段、2048 位数据及 256 位 BE，再保存实际输入，直到真实 result 握手才更新内存。它检查每条命令、result、完成的身份和次数、完成反压保持、最终两个完整 4096-byte 内存以及容量排空。零 BE 和错误状态仍计一次执行；错误状态不修改内存。两侧使用不同字节模式，避免方向交叉仍偶然匹配。

ESE 测试的预期 Read 来自运行前的 Python 内存；SV 后端不读取预期 fixture，而用实际接收的地址、数据和 BE 更新自己的内存。实际执行脉冲、slot 所属请求、后端 result、发出的 TL Header、应用完成相互核对；每个 Write 只能执行一次，完成必须晚于实际后端 result。恢复场景还检查两方向均发生丢槽、CRC 状态失败与重放，而 Write 执行次数仍等于应用 Write 次数。

这不是同一个函数既回送 DUT 输出又生成预期。刺激和预期自然共享应用数据及操作列表，故测试本身仍不能独立证明列表生成器涵盖所有规范几何。ESE `--all-lengths` 覆盖全部 64 种普通 LEN 的各一个代表起点及 10 种合法 Full 几何，不是全部 2080 种普通合法起点/LEN 组合。全几何检查由独立模块/模型测试承担。

## 发现与修正跟踪

初审发现 ESE TB 在 `posedge` 内 blocking 更新 `cycle`、`requested` 和 `originals`。这些变量反馈组合 ready、应用候选请求，以及 drop/CRC 选择和 link ready，可能使当沿 DUT 与 scoreboard 对握手采样不一致；更新 originals 后再读取 drop/bad 也可能记错故障事件。已直接通知 ESE 作者及主代理。最终 TB 将这些反馈变量以及 dropped/corrupted 改为 NBA 更新，检查仍读取同一采样沿的旧值；只服务 scoreboard 的计数继续 blocking，不反馈 DUT。独立复核确认上述竞态已修正。

双 core TB 在负沿准备输入、沿前保存 fire 与完成值、正沿后处理 scoreboard；未发现上述同类竞态。ESE runner 初审还存在复制源后再读取原文件计算 source hash 的窗口；并发编辑可能令原文件 hash 与实际受测副本不一致。最终 runner 已按同一份读取字节生成副本和身份，包含 runner 与依赖 manifest；独立复核确认此窗口已关闭。

修正后作者重跑四个正向及两个故障标签。独立审查读取实际退出码与日志：basic 为 20 次完成/6 次 Write 执行，lengths 为 566/154；minimum_recovery 为 20/6，lengths_minimum_recovery 为 566/154，两个恢复场景均每方向 4 次重放。两个故障均 compile 0、run 1，分别命中 READ_DATA 与 EXECUTION_CAUSALITY。六标签合计 1326 份 artifact 已重算 SHA256，零缺失、零差异；所有 source hash 与实际编译快照逐项相符。

## 故障与边界

- core 的 BE 断开、Write Data 清零、dispatch 提前释放，均修改隔离的实际 core 源码，编译后由具体字段/顺序检查检出。
- ESE 的 `drop_write_be` 在实际后端 BFM 接线处强制 BE 为零，以后续 Read 字节检查检出；不是生产 RTL 修改。
- ESE 的 `early_write_result` 让后端在真实执行前返回 result，执行因果检查检出。它验证测试能发现错误后端行为，不能证明 RTL 能识别一个接口格式合法但语义虚假的后端结果。
- core 的错误状态由测试后端按操作表注入，覆盖状态传递及无副作用；不证明后端自行实现地址权限或错误检测。core 桥是 prepared/receive 记录模型，ESE 才使用真实 TL/DL 路径。
- ESE Switch 使用显式目的路由 sideband，CRC 由链路状态注入；不证明协议路由解析或 CRC 多项式实现。TL Header 起点观察复用了实际 control decoder，不能替代独立编码 literal 检查。
- 本轮 ESE 以成功状态、单区域内存和固定容量为主；完整错误恢复、在途混合 Write 复位、压缩/poison、性能及物理签核均不能由这些结果推出。

## 审查源码身份

| 文件 | SHA256 |
|---|---|
| `verification/endpoint_transaction/run_write_core.py` | `9f982e4187227fc21795bc361c00211e5673f160e778f2909d4d712cc017e0cf` |
| `verification/endpoint_transaction/write_core_tb.sv` | `7bb1b883b27d9dcc976bce31cd62e9715904f5a740c93bad877bfd27df48a870` |
| `verification/endpoint_transaction/run_write_endpoint_switch.py` | `fc0cd501e9e6966e729047e0dc06e37b241f2684dfdaa2b1b32f8ed992a93cf3` |
| `verification/endpoint_transaction/write_endpoint_switch_tb.sv` | `1a9773480e08f2f018ddeb131603800e09ea159d4ecff2c46d97d7222fa8d9f2` |

core 现有证据为 `write_core_review_c1/c2/c3/c4` 及 `write_core_review_be/data/dispatch`；这七个通过标签及旧接口红测的 238 份 artifact 已只读重算 SHA256，零缺失、零差异。审查范围与执行细节见 [core 报告](endpoint_write_core_review.md)。ESE 固定标签为 `write_ese_final_basic`、`write_ese_final_lengths`、`write_ese_final_minimum_recovery`、`write_ese_final_lengths_minimum_recovery`、`write_ese_final_be_fault`、`write_ese_final_completion_fault`。本审查未发现仍需阻止该功能增量发布的测试缺陷；上述边界仍须保留，不将有限测试称为完整协议验证。
