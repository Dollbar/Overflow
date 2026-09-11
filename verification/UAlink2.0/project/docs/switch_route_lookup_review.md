# Switch 唯一目标查表实现复核

`rtl/switch/switch_route_lookup.v` 已从拒绝服务壳替换为真实可综合组合模块，`ualink_switch_top` 已实际实例化它，并用输出 onehot 矩阵决定仲裁资格和已锁 owner 的合法目的。顶层原有整数目标/匹配数量译码已移除；轮询起点、首拍停顿锁定、包 owner、末拍释放与同步复位过程保持原样。

## 接口契约

`PORTS` 默认为 4，至少为 1。输入 `i_valid[PORTS]`、`i_dst[PORTS*10]`、`i_route_ids[PORTS*10]`、`i_port_enable[PORTS]`；输出 `o_match[PORTS*PORTS]` 与 `o_error[PORTS]`。无时钟、复位、内部路由表副本或协议报文解析。

源 s 的目标是 `i_dst[s*10 +:10]`，目的 t 的表项是 `i_route_ids[t*10 +:10]`。输出采用 **source-major** 布局：`o_match[s*PORTS+t]` 表示源 s 唯一匹配目的 t。只统计 enabled 表项；恰好一个匹配则输出该行 onehot，没有匹配或重复 enabled 匹配则整行清零。disabled 重复项不参与计数，允许 self-route。

`o_match` **不受 i_valid 门控**；`o_error[s] = i_valid[s] && 没有唯一enabled匹配`。这保留提取前 Switch 在已锁 owner 的 valid 气泡期间仍可反馈 ready 的行为。顶层只依赖公开 onehot/error 接口，不访问 lookup 内部状态。路由表在正常包转发期间保持稳定的原顶层契约不变。

这仍是内部 10 位目标 sideband 路由，未增加标准 TL 目的解析、动态路由提交、vPod 过滤、完整管理或完整 UALink Switch 符合性声明。

## 独立验证与执行

```sh
python3 verification/ip_tops/run_route_lookup.py --label route_check
```

需要 Python 3、Icarus Verilog/VVP。入口从自身位置解析仓库根，只编译真实 lookup 和独立 TB，不编译两个顶层或服务聚合。输出为 `reports/ip_tops/route_lookup_<label>/summary.json`、每 case 刺激/编译二进制/命令/返回值/日志，以及源、入口、TB 快照；已有 label 拒绝覆盖。下一步在库存与聚合接口更新后执行现有 Switch 集成回归。

先在未修改的原壳上通过其真实旧端口发出请求：`--label shell_red --mode shell` 编译返回 0、运行返回 1，明确报告 `FAIL unimplemented_route_lookup implemented=0 ready=0`。这是旧壳能力红测，不把新接口缺失导致的编译错误算作行为失败；该模式仅用于保留的旧接口阶段。

新接口功能测试用 Python `ID -> enabled目的列表` 字典生成独立预期，RTL 用匹配位向量的唯一置位判断，双方不共享实现算法或辅助函数。TB 比较整个 source-major 矩阵和所有错误位。实际 `--label functional` 完成：

| PORTS | 实际组合向量 | 表项 ID / 请求 ID 值覆盖 | 源到目的组合 |
|---:|---:|---|---|
| 1 | 2180 | 各 1024/1024 | 1/1 |
| 2 | 2232 | 各 1024/1024 | 4/4 |
| 3 | 2360 | 各 1024/1024 | 9/9 |
| 4 | 2672 | 各 1024/1024 | 16/16 |
| 5 | 3600 | 各 1024/1024 | 25/25 |

五个正常配置全部编译/运行返回 0，共 13044 个完整矩阵比较。覆盖包含 0/1/511/512/1023 边界、全目标值、所有 source-target 对、全部 valid×enable 掩码、自环、无匹配、每对重复表项及两个重复项分别禁用、每配置 128 个确定种子的随机表/请求/使能组合。1024 个值覆盖不是 1024×1024 全部请求/表项笛卡尔积覆盖，更不是全部路由表穷举。

两类隔离真实 RTL 注错均编译 0、运行 1，并由 `FAIL lookup case=` 实际比较检出：5 端口丢弃 ID 最高位、3 端口错误接受重复匹配。超时、编译错误或其他任意失败不计检出，正常源码未被注错覆盖。

Yosys 对 1/2/3/4/5 端口分别运行 `read_verilog; hierarchy; proc; opt; check -assert; stat` 全部返回 0，最终网表均无 latch，保留在 `reports/ip_tops/route_lookup_synthesis/`。这是通用综合展开和结构检查，没有工艺 STA 或频率/面积签核结论。

## 集成检查

库存与聚合已由 owner 更新：lookup 标为明确 subset 的 `existing_partial`，旧 generic-service 实例移除，真实顶层使用功能接口。实际执行 `python3 verification/ip_tops/run_switch.py --label route_lookup_integrated`，2/3/4 端口正常配置全部编译/运行返回 0，routing/hold 两个真实注错均检出。完整 544 位回归证据在 `reports/ip_tops/switch_route_lookup_integrated/summary.json`；它涵盖原有所有权、轮询公平、stall、包内气泡、错误路由、self-route、复位及有界排空。

另外保留了一轮独立整字重构等价尝试：从提交 `4a6ccf5037505b859e821d43e4f484cee06d9b0e` 提取旧顶层，与当前顶层组成 544 位、6 步 miter，比较 ready/valid/data/last/error，排除已更新的 pending 状态位图。固定初始复位、运行时静态路由表/使能、反压时保持全部源字段、包内含 valid 气泡时保持 dst 等合法接口假设。2/3 端口达到每 case 20 秒 SAT 时限，4 端口达到 35 秒进程时限，**三项均未证明，不计通过**；没有据此给出整字形式等价结论。全部日志、miter、脚本和状态保留在 `reports/ip_tops/route_lookup_equivalence/`。未追加拆分证明或扩大求解时限。

契约外边界需明确：已锁 owner 在 `valid=0` 时若把 dst 改成重复目标，旧/新顶层的 ready 可能不同。这违反固定 packet dst 的接口约束，当前提取不承诺该序列的等价；不能把有效包契约下的真实全宽回归通过扩大成任意无约束输入的形式等价。功能交付依据是独立 lookup 回归、实际 Switch 全宽回归和通用综合检查，形式超时仍单独开放。
