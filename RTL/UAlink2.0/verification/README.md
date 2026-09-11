# 验证入口

运行 `make test`、`make rtl-smoke`，以及 `make sram-smoke KD28_ROOT=/authorized/path`。具体目录分别覆盖 `model/`、`tools/`、`rtl/`、`formal/`、`tl_publish/`、`tl_receive/`、`tl_port/`、`tl_peers/`、`dl_replay/` 与 `rs/`。

TL 发布器的扩展检查：先运行 `verification/tl_publish/run_rtl.py`，再运行同目录 `run_checks.py`（严格 lint、综合和 56 次实际故障注入）；之后 `run_safety.py` 保留两项任意初态保持性质反例，`run_reachable_safety.py` 证明可达状态不变量并完成保持性质。前者的部分性质失败是已知诊断，不能单独作为证明通过入口。

运行输出均位于 `build/` 或 `reports/`，不会提交。使用 `make clean` 清理；历史结果的保留范围见 [工程状态](../docs/status.md)。
