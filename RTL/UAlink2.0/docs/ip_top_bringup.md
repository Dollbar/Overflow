# Endpoint / Switch 顶层研发交付

本阶段按用户最新优先级，先补齐两套 IP 的模块层级、接口、实例和构建入口，再逐项实现功能及衔接。完整目标仍以 `ip_delivery_plan.md` 为准；模块壳存在不代表相应协议功能完成。

## 当前顶层

- `rtl/endpoint/ualink_endpoint_top.v`：将实际 TL 源组捕获/发送 SRAM、信用准入、600-bit 接收 SRAM/FC 发布及 DL 重放合并。新增真实发送 holding 容量预约，把原固定延迟 DL 返回转换为可背压的 ready/valid 输出。
- `rtl/switch/ualink_switch_top.v`：按显式 10-bit 目的侧带选择唯一启用端口，提供参数化端口仲裁、包内独占与输出停顿保持。配置在复位期间设置，运行期间保持稳定。
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

两个顶层的 `o_pending_features[127:0]` 仅标记清单中尚未实现的接口壳：Endpoint 低109位、Switch低127位为1。既有 `existing_partial` 模块的剩余功能不会由这些位完整表达；位图为0不是完整IP就绪条件。
