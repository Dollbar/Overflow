# RTL

`endpoint/ualink_endpoint_top.v` 和 `switch/ualink_switch_top.v` 是研发顶层；`upli/`、`dl/`、`tl/`、`phy/` 及各服务目录包含当前实现与显式未实现的接口壳。202 个规划 RTL 条目中，66 个已有部分实现、136 个仍为接口壳，尚未达到完整 IP 交付。

通过验证脚本显式选择顶层和依赖；不要将 `variants/` 与默认 RTL 一起编译。测试平台和公共 package 位于 `verification/`，可复用 VIP 位于 `simulator/vip/`。运行入口、已验证的单 64B Read 范围与限制见 [顶层指南](../../verification/UAlink2.0/project/docs/ip_top_bringup.md) 和 [工程状态](../../verification/UAlink2.0/project/docs/status.md)。
