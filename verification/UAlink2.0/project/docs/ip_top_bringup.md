# Endpoint / Switch 顶层研发交付

原生双角色 Endpoint 前端顶层现已实际连接 connection、四通道TX、四通道保护RX、Request holding、Read/Write response collector、request context和唯一role Drop控制。启用context时，真实request bridge只有context一个descriptor消费者；issue不释放，外部合法最终release才回收。单在途memory adapter已独立验证命令、结果和最终响应退休的分段所有权，但尚未接入顶层，因此 `o_backend_implemented=0` 保持。RX burst monitor已接入同一个role Drop控制器，补齐Req/Data配对、Offset/Last/VC诊断。Switch已有整包容量预约、Request/Response/VC分区缓存、物理出口scheduler、typed repack及其可选生产顶层路径；RAS isolation义务账本也已替换共用壳。当前结构为223项、103个部分实现、120个显式壳。见 [Endpoint context顶层记录](upli_endpoint_context_top_execution.md)、[memory adapter记录](endpoint_memory_adapter_execution.md)、[VC队列审查](switch_egress_vc_queues_review.md)和[scheduler审查](switch_egress_scheduler_review.md)。

最新完整普通 Read 增量：`FULL_READ_ENABLE=1`已贯通4..256B合法DWORD长度、首尾字节掩码、2048位后端结果及完整Tag收齐。三组真实双Endpoint经Switch回归完成1652笔事务，包含12次Write执行及8次重放；接收器/Tag另验证single乱序及multi响应。独立参考模型与RTL编码器分别覆盖532480合法几何/ATTR组合。写在途统一reset在两bank、三窗口通过；完整Read部分响应统一reset已验证，独立LinkDown/epoch尚未闭合。详见[Read集成审查](endpoint_read_integration_review.md)。


本阶段按用户最新优先级，先补齐两套 IP 的模块层级、接口、实例和构建入口，再逐项实现功能及衔接。完整目标仍以 `ip_delivery_plan.md` 为准；模块壳存在不代表相应协议功能完成。

## 最新容量与复位验证

最新容量与复位增量：20组独立事务容量组合完成320笔真实Read，三组默认回归另完成48笔；五组非法容量和一项容量接线故障按预期检出。三种在途统一同步复位窗口在两种bank配置下通过，12笔旧预约取消后产生12笔新轮次完成，两个漏复位故障被检出。严格静态风格门限仍未闭合，新顶层工艺STA未完成，详见[增量审查](endpoint_capacity_review.md)。

## 此前实际Read链

`TRANSACTION_MODE=1`已连接真实Read事务模块；新增可选`WRITE_ENABLE=1`连接普通Write/WriteFull，当前93个部分实现、123个未实现壳。Write混合总装验证状态见[Write审查](endpoint_write_integration_review.md)。三组真实两端Read因果回归完成48笔事务，三项实际接线故障全部检出。复跑与完整边界见[因果事务评审](endpoint_causal_read_review.md)；以下首批接口壳与独立fixture记录属于前一阶段。

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

两个顶层的 `o_pending_features[127:0]` 仅标记清单中尚未实现的接口壳：Endpoint 当前91个壳位、Switch当前114个壳位为1（稳定slot不重排）。既有 `existing_partial` 模块的剩余功能不会由这些位完整表达；位图为0不是完整IP就绪条件。
