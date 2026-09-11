# Endpoint / Switch 顶层研发交付

原生 Request/OrigData 发送字段层与共享信用/TDM 总装已形成实际 RTL；Read/Write Response 独立信用/TDM发送器与四通道TX/SRAM闭环也已验证。接收侧已有实际事件 TDM 观察、跨 VC/Pool 的每端口有序 SRAM 退休、四通道类型 parity/poison/信用封装，以及 Endpoint Request/OrigData 完整事务 holding；完整 station 尚未接入顶层。Switch 新增整包出口容量原子预约，但真实 egress queue 尚在隔离开发。当前结构为213项、89个部分实现、124个显式壳。见 [接收封装验证](upli_native_rx_channel_execution.md)、[Endpoint请求桥验证](upli_endpoint_request_bridge_execution.md)和[Switch预约验证](switch_credit_reservation_review.md)。

最新完整普通 Read 增量：`FULL_READ_ENABLE=1`已贯通4..256B合法DWORD长度、首尾字节掩码、2048位后端结果及完整Tag收齐。三组真实双Endpoint经Switch回归完成1652笔事务，包含12次Write执行及8次重放；接收器/Tag另验证single乱序及multi响应。独立参考模型与RTL编码器分别覆盖532480合法几何/ATTR组合。写在途统一reset在两bank、三窗口通过；完整Read部分响应统一reset已验证，独立LinkDown/epoch尚未闭合。详见[Read集成审查](endpoint_read_integration_review.md)。


本阶段按用户最新优先级，先补齐两套 IP 的模块层级、接口、实例和构建入口，再逐项实现功能及衔接。完整目标仍以 `ip_delivery_plan.md` 为准；模块壳存在不代表相应协议功能完成。

## 最新容量与复位验证

最新容量与复位增量：20组独立事务容量组合完成320笔真实Read，三组默认回归另完成48笔；五组非法容量和一项容量接线故障按预期检出。三种在途统一同步复位窗口在两种bank配置下通过，12笔旧预约取消后产生12笔新轮次完成，两个漏复位故障被检出。严格静态风格门限仍未闭合，新顶层工艺STA未完成，详见[增量审查](endpoint_capacity_review.md)。

## 此前实际Read链

`TRANSACTION_MODE=1`已连接真实Read事务模块；新增可选`WRITE_ENABLE=1`连接普通Write/WriteFull，当前89个部分实现、124个未实现壳。Write混合总装验证状态见[Write审查](endpoint_write_integration_review.md)。三组真实两端Read因果回归完成48笔事务，三项实际接线故障全部检出。复跑与完整边界见[因果事务评审](endpoint_causal_read_review.md)；以下首批接口壳与独立fixture记录属于前一阶段。

## 首批接口壳替换

前一阶段库存为60个部分实现、142个未实现壳。Read/Response typed编码器已按单64B普通Read子集验证字段，但尚未接入真正事务引擎。Switch通过真实`switch_route_lookup`端口接收完整10位ID唯一目标矩阵，继续保留包所有权和反压行为。历史初版门级综合属于前一源码快照；本次增量结果见 [模块衔接进展](typed_modules_progress.md)。

```sh
make ip-module-smoke IP_RUN_LABEL=fresh_modules
```

输出分别在`build/verification/endpoint_transaction/`和`reports/ip_tops/`。后续连接真实Read发起、内存执行、响应组装及Tag完成。

## 当前顶层

- `rtl/endpoint/ualink_endpoint_top.v`：将实际 TL 源组捕获/发送 SRAM、信用准入、600-bit 接收 SRAM/FC 发布及 DL 重放合并。新增真实发送 holding 容量预约，把原固定延迟 DL 返回转换为可背压的 ready/valid 输出。
- `rtl/switch/ualink_switch_top.v`：按显式 10-bit 目的侧带选择唯一启用端口，提供参数化端口仲裁、包内独占与输出停顿保持。默认静态配置在复位期间设置并保持；可选原子路由配置服务只在完整空闲边界提交。
- 完整模块清单与待实现模块边界见 `config/ip_module_inventory.json` 和 `ip_module_inventory.md`。现有模块复用，缺失模块用明确标记的不可接纳服务壳表示，逐项替换后重新验证。

## 初版系统连接

两个实际 Endpoint 的 `{24-bit DL header, 520-bit local payload}` 输出经 Switch 数字 fabric 到达对端。测试适配器显式给出目的 ID，并将 CRC-status 作为额外测试元数据携带；单个 DL 槽作为一个本地单拍 packet。故障适配器可丢弃槽或翻转 CRC-status。

这验证的是实际顶层数字连接及可复用的交换 fabric。Switch 当前没有从标准 TL 字段解析路由，也没有独立终止每一跳 TL/DL 的信用与重放；当前发送源仍为独立 Request/Response fixture。标准 framing、完整 UPLI 事务/Tag、逐跳协议、INC、安全、PCS/FEC、管理和真实物理签核均保留在模块清单中继续实现，不因顶层存在而关闭。

## 构建与验证

```sh
python3 verification/ip_tops/run_link.py --kd28-root /authorized/path --label ese_clean
python3 verification/ip_tops/run_link.py --kd28-root /authorized/path --label ese_recovery --ports 4 --inject
python3 verification/ip_tops/run_switch.py --label switch_clean
make ip-structure IP_RUN_LABEL=structure_check
make ip-top-smoke KD28_ROOT=/authorized/path IP_RUN_LABEL=system_check
make ip-top-synth KD28_ROOT=/authorized/path IP_RUN_LABEL=synthesis_check
```

`run_link.py` 输出新 `build/verification/ip_tops/LABEL/` 目录中的实例化测试台、输入 fixture、编译/运行日志、完整 trace、源码和产物 SHA、独立 TL/DL/SRAM 审计。脚本拒绝覆盖已有标签。测试复用前序独立语义检查器，实际 DUT 改为新顶层实例；不会以测试模型取代其 SRAM、信用或重放模块。

下一步按模块清单推进实际事务接收/执行/响应完成，接入 Switch TL 目的解析和每端口协议终止，随后逐功能族补齐并逐项更新状态。当前综合检查仅证明相应工具能展开/转换声明结构，不是工艺时序或可制造性签核。

两个顶层的 `o_pending_features[127:0]` 仅标记清单中尚未实现的接口壳：Endpoint 当前93个壳位、Switch当前117个壳位为1（稳定slot不重排）。既有 `existing_partial` 模块的剩余功能不会由这些位完整表达；位图为0不是完整IP就绪条件。
