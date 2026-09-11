# 实际半Flit发送打包审查

新增 `rtl/tl/tl_tx_packer.v`，通过独立 Control、Data/BE、AuthTags 和 FC 输入组合真实 Flit，再由 `tl_credit_admitted_port` 的实际发送事件确认相应队首。旧尾部不再依赖下一头部取得信用才能排空。完整双IP目标保持开放。

## 规范与接口

核对私有 Common 2.0 §5.1.1/§5.1.2：非NOP Control 只能在下半；最后一个旧 Data/BE 半 Flit 交换到上半。启用 Auth 时旧尾上半已被占用，下半不能再放需要 AuthTags 的新头。普通 FC 仍可以与旧尾共存，初始完成消息因占用上半而先等待旧尾排空。未创造新的线消息或物理 ready。

§5.7 的 catch预算按实际 TL Flit 推进，所以在信用充足而catch预算不足时发送完整NOP；单纯等时钟不能恢复该预算。§5.8 的信用需求仍由现有整段准入解码，发送侧不提前重复扣除未来Data信用。

接口约束和输出语义见 `config/tl_tx_packer_contract.json`：

- `i_pending`、对端共享模式与物理信用、Tx catch预算来自同一个实际端口。回归从真实Tx验证状态的 [9:7]/[6:3] 取得请求/响应catch预算。
- 头部、标签、有序 Data/BE 和 FC 各自保持未确认队首。选择状态在停顿时锁定；来源可能在另一个来源等待时到达，而不改写已提出的 Flit。
- 只有真实端口 `o_tx_taken` 能触发输入确认。一个 Flit 可以同时确认头部+旧尾或FC+旧尾；不会因确认整个 Flit 而错误地同时弹出所有输入。
- Data tenure大于1时必须有两个有序半Flit才能发送，本接口要求源最终提供这两个半Flit；最后一半只需一条数据。实际Tx Data缓存、任意供给停顿以及缓存深度的持续前进性证明尚未集成。
- 在合法Control机会中，FC与当前可发的准备好头部交替优先。此仲裁不等于独立Request/Response队列仲裁；后者仍在准备好Control输入的上游。

## 实测与独立核对

16组实际组合为 WIDTH 8/16 × Auth 0/1 × Shared 0/1 × 数字链路延迟1/3。每端有56个准备好的Control队首，包含连续三Beat压力、五类已确认字段、Data/BE、无Data响应批次；使用真实接收600位SRAM以及真实FC发布器，消费停顿和发送停顿均实际发生。

- 合计9,648次测试循环；1,792个Control队首和7,840个Data/BE半Flit实际消费。
- 5,680个实际SRAM字完成消费；3,738次FC或初始化完成消息转移。
- 3,072个CMD信用、3,648个Data信用由实际退休归还。
- 70次新头+旧尾，522次FC+旧尾，182次NOP+旧尾；Auth配置没有新头+旧尾。
- 186次显式catch预算NOP；1,398个已提出候选但尚未发送的边沿，跨停顿内容保持。

独立 Python 审计直接解析实际线上两个半Flit，重建接收存储字和释放所有权，并与每一个实际消费的600位字精确比较。还核对数字链路延迟、输入字序及确认数量、真实队列深度、头部整段信用、FC不早于实际消费和最后的信用守恒。返回信用不由消费模型驱动RTL。正常Python和`-O`均审计通过。

单位级时序比较为3,170个实际RTL周期向量，包含初始化、最大pending=73、缺数据、旧尾被新头信用阻挡、Auth冲突、FC完成消息、catch NOP、停顿中另一来源到达以及公平轮换。Python模型在RTL前生成；补强完成消息优先测试时曾真实失败，修正后通过。缺失模型/RTL和失败日志保留。

8类实际单位RTL故障各跑两宽度，共16次检出：删除旧尾兜底、旧尾放错半边、错误确认头部、丢失配对FC确认、取消停顿锁定、固定FC优先、允许Auth头尾冲突、删除catch NOP。另将旧尾放错半边和错误确认头部注入完整双端16配置，共32次实际负向运行全部失败。所有故障均使用健康测试向量/夹具，不仅修改期望值。

严格 Verilator lint 两宽度通过。Yosys 通用综合分别31,665/32,345 cells、4个FF位，寄存器均为输入时钟上的同步复位类型。数据MUX为组合，4位仅是轮换偏好和停顿来源锁定；这些数字只属于packer及其解码/准入依赖，不含实际信用端口或SRAM，也不是工艺面积/STA。

干净导出的 `make test` 与 `make rtl-smoke` 均实际返回0，包含新增8项模型测试和3,170个packer向量；RTL与Makefile逐文件对照当前源码一致。

Artifact技能检查零错误、11项建议，保留工程既有分区/历史头风格与参数声明；技能包全局自检仍实际失败于外部缺失 `agents-md-generator/scripts/manage_docs.py`。两者没有合并成通过声明。

## 未完成项

每类只有一个Data信用的同一多Beat输入实际运行6,000次测试循环后仍超时：头/数据消费为0/0，tenure和FIFO为0/0，两端容量不足诊断为1/1。输入未被确认、未丢弃，也没有通过提高信用掩盖问题。此阶段解决旧尾打包，尚未解决超容量事务。

下一步必须补独立Request/Response队列、规范允许的容量感知UPLI处理、真实Tx数据缓存、Data Poison及其余TL消息。当前AuthTags全零为分类夹具，不是密码认证实现；字段只覆盖现有确认tenure，不是全部opcode/address/LEN正确性。数字链路延迟不是DL/PHY。完整在线容量归纳、完整参考归纳、跨层顶层、工艺STA和最终两套IP交付仍未完成。

## 复跑

```sh
python3 verification/tl_tx_packer/test_model.py
python3 verification/tl_tx_packer/run_rtl.py
python3 verification/tl_tx_packer/run_peers.py --kd28-root /authorized/Overflow --label peers_final
python3 verification/tl_tx_packer/run_peers.py --kd28-root /authorized/Overflow --label small_credit --single --data-credits 1
python3 verification/tl_tx_packer/run_checks.py --kd28-root /authorized/Overflow
python3 verification/tl_tx_packer/run_skill_gate.py --skill-root /path/to/verilog-generator
python3 verification/tl_tx_packer/check_evidence.py --label peers_final
make test rtl-smoke
```

`small_credit`预期非零，其余要求通过。输出在 `build/verification/tl_tx_packer/`，同名运行目录不覆盖；最终证据文件为 `evidence.json`，原始/中间运行也保留。所有运行时钟计数仅在指定测试范围内，不继承此前其他模块的签核成绩。
