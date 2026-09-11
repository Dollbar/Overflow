# 首批独立模型契约

本契约用于 G1 模型研究，尚不是 RTL 接口冻结或完整 profile 接受条件。依据与任务顺序见 执行计划（历史文档已清理）。源代码和测试只用 Python 标准库，运行环境最低 Python 3.10，实测版本另记于 阶段记录（历史文档已清理）。

## WP01：配置算术子集

- `StationLayout(num_stations, bifurcation)` 是不可变的单设备、选定模式、全部 station 全量配置描述；不是最终 Endpoint/Switch 参数包，未定义任何线上/CSR 枚举。
- `num_stations` 必须为正整数，明确拒绝 Python bool/float；三种模式均按 C §2.4 p37 的四 lane station 派生数量。超过 M §1.4 p16 的 1024 配置端口立即抛出 `ValueError`，不能通过隐藏 down ports 绕过。
- `ports_per_station`、`lanes_per_port`、`num_ports`、`num_lanes`、`station_index_width` 只读派生；单 station 索引宽度为 1 是工程接口选择，非协议新位宽。
- `split_port_index(index)` 对内部稠密索引作除法/取余；返回 `(station, local_port)`，不代表 PortNum/安全身份映射。非二次幂未用索引抛错，不能截断。
- `lane_assignment(index)` 使用本模型的连续 lane 编号约定；返回 `(station, local_port, port_lane)`。外部 SerDes 的 lane reversal、swizzle/物理引脚映射仍由 PHY 集成契约处理。
- `validate_pod(accelerators, switches)` 对显式设备列表检查 M §1.4 的设备数量和 C §2.4 的相同模式、相等 Accelerator 端口数、各 Physical Switch 端口数不少于 Accelerator 数。要求非空列表仅是该交换 Pod 测试夹具的前提。它不证明路由连通性、角色必选模式能力、安全身份、动态重配置或硬件资源成立。
- 配置替换不是在线模式切换；实际停发/排空/恢复、信用与密钥上下文迁移仍在 WP05 和管理状态机中实现。

追溯：R001、R003、R004、R045 的相关数量/一致性子集；每条整体状态不因这些检查通过自动完成。R002 的交换实例全模式能力不由静态计数验证替代；WP01 的公共命令/字段定义与 RTL 生成/消费接口仍未实现。

## WP03：DL CRC 多项式算术子集

- `dl_crc_polynomial(flit)` 输入 `bytes` 或 `bytearray`，恰好 640 octets。输入是数字 DL 的已布局字节，不包含 RS/PCS 的 64b/66b sync header、scrambling 或 FEC。
- 数组顺序为 L Figure 2-4 p19 的实际排列，从 S0.B0 开始；每个 octet 的 bit 0 先进入计算（Figure 2-9 p23）。测试示例的 FH0/FH1/FH2 在偏移 624/625/626，值为 `00 ff 4f`。函数本身不负责构造 TL/SH/FH。
- 最后四个 octets，即偏移 636–639，在计算时置零。长度检查包含这四个 octets，不能计算 636-byte 后直接 append。
- 返回一个 32-bit 整数，bit `i` 明确定义为补码余式的 `x^i` 系数。输入不被修改，错误类型/长度分别抛 `TypeError`/`ValueError`。
- 参考模型使用串行 LFSR；测试侧独立使用完整消息的 GF(2) 多项式长除法，并以显式反射的 `zlib.crc32` 作第三路径。没有共用 LUT、CRC helper 或 DUT packer。
- **不提供 `encode/check_wire_crc` 接口**：正文 `x0→x31` 与 informative Appendix A 示例打印发送序列的复现分歧记录在 位序诊断（历史文档已清理）。数学子集通过不意味着该分歧已关闭。
- 无时钟周期、流水吞吐、复位残片或背压语义。宽度、流水级、DL/PL chunk、FIFO 及 RTL compare 点须在 RTL 契约单独冻结，不能由这个无状态函数推断。

追溯：R101 中计算覆盖/数学及非 CRC bit 敏感性子集；线上 CRC bit 翻转检测、互操作和全部 R101 仍未签核。
