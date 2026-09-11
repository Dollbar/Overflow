# Read Response sender 候选审查

该候选实现完整 staged 原生 Read Response TX，使用一个生产 `upli_credit_bank`、生产 `upli_read_response_channel` 及公共 parity。所有 619 bit/Beat 原生负载保留，最多四拍，低 Beat0；发送前对专用 VC 和共享池分别检查整笔沿前信用，每个实际原生 Beat 才扣一次。每 port 保存尾部，独立 TDM 在 idle 继续推进，single NumBeats=0 任意 Offset/Last 透明。Src 不作多拍准入比较。来源和具体边界见 `docs/upli_read_response_sender_execution.md`。

RTL 冻结 SHA256：`4ec11412689f2daddf1f10afc77193898b4314ce0b3574109a37c0a0a5cc7e5f`。可安装文件在本候选 `release/rtl/upli/` 与 `release/verification/upli_channels/`。候选源码、模型、TB、runner 和公共依赖各自快照入每次运行目录；测试生成从该次保存的 Python 源快照导入，避免活动源码与证据脱节。

独立参考使用显式字段字典、Python 整数位位置和每账户事件 journal；测试不读取 DUT 内部状态。TB 核对全部实际 typed outputs、重新组合的 619 bit payload、所有 11 bit parity、accepted、公开银行余额/init、busy、相位和错误状态。模型的 pack/unpack 另以独立绝对位置单 bit literal 检查。正常信用归还刺激由参考发送事件产生；刺激与预期共享此语义模型，但不共享 RTL 逻辑。实际 RTL 故障检出与固定位置检查补充该一致性边界，不等同联盟独立一致性或形式证明。

初始 `missing_red` 是在模块不存在时执行的编译失败，明确属于接口缺失 red，不能称为行为通过。后续真实错误副本提供行为反例：候选污染尾部、只在首拍扣账、idle 相位冻结、绕过整笔信用检查、错误尾拍 pool、错误要求 Src 相等、错误要求 single Last=1。所有副本均编译成功且由 `READ_SENDER_MISMATCH` 失败，不能把任意编译失败算故障检出。

首轮 `results/first_matrix` 四个正常配置通过：P1/CW3 1440 周期、P2/CW4 3927 周期、P4/CW4 与 P4/CW8 各 12492 周期。每个 port 覆盖 N=1..4、所有 2^N pools 组合与五状态 0/2/3/6/8，共 150 组合/port；另有跨 port 同时在途、Src 每拍变化、完整错误数据、single 任意 Offset/Last、未声明尾部噪声、多字段非法几何、无效 port、差一信用、同沿归还不能旁路、初始化确认前后、reset 取消旧尾部、银行错误粘滞阻断。每个输出周期都核对完整字段及信用，不仅统计最终次数。

最终 portable 独立布局回放在 `release_replay/build/verification/upli_channels/read_response_sender/frozen` 与 `frozen_optimized`，分别普通 Python 和 `python3 -O`。每次四正常、七故障和九项静态检查：P1/2/4 的 g2001、Verilator `--lint-only -Wall` 无警告、Yosys `proc; opt; memory_map; opt; check -assert; stat`。最终结果与逐文件哈希见各 `summary.json`/`manifest.json` 及候选 `freeze.json`。

技能 owned RTL artifact gate 零错误，196 个代码行均同一行解释性注释；13 项建议警告涉及传统头/区域命名、实例后缀及整数生成索引。完整 skill 自检仍受主机缺失 `agents-md-generator/scripts/manage_docs.py` 阻断，与本 RTL 结果分开记录；不声称工具生态自检通过。

本模块不是原生 RX、Tag 收集器或完整 station，不检查业务命令和 reserved status 合法性，也不推断授权策略。连接或信用错误中的完整 RAS/Isolation/响应连续性恢复不属于证明范围；故障可见后停止并等待统一 reset。复位前旧尾部取消由上层负责事务恢复。4-state/X 注入、穷举形式证明、时序/面积/PPA、工艺 STA、硬件互操作均未执行。

安装后运行：

```sh
python3 verification/upli_channels/run_read_response_sender.py --label read_sender_review --faults
python3 -O verification/upli_channels/run_read_response_sender.py --label read_sender_review_optimized --faults
```

输出位于 `build/verification/upli_channels/read_response_sender/LABEL`，包含实际源快照、vectors、coverage、命令、编译/运行/lint/Yosys 日志、summary 和 manifest。下一步由主线将该 sender 接入 station TX，与真实连接和信用接收闭环共同验证；叶测试不替代总装测试。
