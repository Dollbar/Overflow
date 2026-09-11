# Native RX 角色故障控制器契约与候选验证

`upli_rx_role_fault_controller` 是本地角色范围的故障保持与通知组件。读取 Common Rev2 §3.1.2（pp86–87）、§3.1.3（pp87–89）、§3.1.4.1–3.1.4.2（pp90–94），结合已安装 native RX 的分类诊断实现。本文仅释义，不复制私有正文。它不执行Isolation、补造响应、信用账本修复、固件管理流程或LinkDown恢复。

## 错误归属和参数

`C_NUM_PORTS` 仅1/2/4。`C_NUM_ROLES=1` 时全部通道诊断归同一个角色，调用方应只连接该角色实际拥有的接收检测点。双角色时 role0 是 Originator，role1 是 Completer。所有错误输入均为4位，bit0/1/2/3 对应 CHANNEL_KIND Request/ReadResponse/WriteResponse/OrigData，不使用可疑payload里的PortID决定范围。

| 检测输入 | 双角色非TL归属 |
|---|---|
| 正向Beat的control/Auth/profile/metadata/order/storage/TDM；Req、OrigData | Completer role1 |
| 同上；RdRsp、WrRsp | Originator role0 |
| `i_credit_control_error` 的Req、OrigData返回信用总线 | Originator role0 |
| 同上；RdRsp、WrRsp返回信用总线 | Completer role1 |

**返回信用的接收方向与同名正向Beat相反。** 不能把信用错误先并入正向错误，再使用同一个角色掩码。`i_credit_control_error[kind]` 表示该kind实际返回信用接口的错误，不能传入已经按另一套角色编码重排的数据。

`C_IS_TL=0` 默认角色独立：任一fatal只使其可信检测角色的全部端口进入Drop。`C_IS_TL=1` 必须同时配置两个角色；任一fatal扩大为同TL两个角色全部通道/端口。这个扩域来自 Common §3.1.4.2 p92 对TL双UPLI范围的要求及 §3.1.3 pp88–89 的TL Drop描述；非TL角色的默认独立范围来自 §3.1.4.2 p91。非法端口数、角色数、TL参数或TL单角色组合在展开时失败。

原生control及credit-control按已确认Control Error规则请求Drop。Auth/profile/metadata/order/storage/TDM采用明确的**本地保守fail-stop政策**，独立保存分类，不能声称规范已把这些全部定义成同一Control Error。`i_data_error` 包括已由native RX准确定位的data/BE错误，只从 `o_data_error_observed` 透传诊断，不生成Drop、Isolation或新Status，也不另写一个poison数据路径。实际每拍poison及新保护码仍由 `upli_native_rx_protection` 负责；与fatal同时出现时fatal的Drop照常有效。

## 时序、保持与恢复边界

所有输入为同域信号。`i_clk/i_rstn` 是上升沿时钟及同步低有效共同reset。`o_drop_roles[C_NUM_ROLES-1:0]` 同时包含当前组合fatal和寄存历史，保证同沿坏业务或同范围其它业务不穿过；各角色的Drop在posedge保持，直到共同reset。`o_drop_ports` 按 `role*C_NUM_PORTS+port` 展开对应角色全部端口。

`i_fault_ack` 仅确认本地通知。`o_ack_accepted` 是沿前确认资格：该角色必须已锁存Drop，且本沿无新错误来源。`o_notify_roles` 在Drop尚未确认或出现新来源时有效；新来源优先于同沿ack。持续同一个原因不是新增事件计数，不会每拍重新通知。ack从不清除Drop或原因位图，`o_reset_required` 明确给出本实现的保守恢复要求；需要外部真正共同reset相关RX、信用、存储及事务所有权，单独复位本控制器不能作为合法恢复流程。

`o_reason_sticky[31:0]` 每4位保存一种分类，低至高为control、credit-control、Auth parity、Auth profile、metadata、order、storage、TDM。`i_init_done_roles` 只在角色首次进入Drop时记录未完成初始化至 `o_init_incomplete`，之后初始化完成不能自动清除Drop、历史原因或此边界记录。历史输出本身由同步reset清除；组合Drop/当前诊断在reset有效时限定为零。

控制器没有信用有效、InitDone、connection或返回队列的修改接口。可信旧退休记录可沿已有native RX/adapter继续排空；坏返回信用仍须由实际guard的调用方禁止送入bank，guard本身只有诊断能力。测试没有把控制器当作信用过滤器，也不因坏valid parity猜测一个可补还的账户。

初始化未完成时本组件只保持Drop和记录边界，不改变已有initializer政策。实际联动验证确认native initializer后来完成也不会解除Drop；不据此声明初始化期间完整RAS恢复闭合。Isolation/watchdog/dummy CMPTO/ISOLATE、burst终止、管理CSR/恢复以及独立LinkDown处理均未实现。TL配置的作用域已实现，但本次只接四条实际RX路径；TX scheduler、未完响应尾部和TL/DL双向流量还需主线接入，不能将控制器通过称为完整TL Drop功能完成。

## TDD与独立证据

先运行真实缺模块红测。审查中发现首版误把返回信用按正向角色归类，先修改独立期望并运行 `credit_direction_red`：双角色非TL出现真实运行失败，单角色/TL仍通过；随后单独修复反向映射。旧 `first_matrix` 的早期通过不代表最终方向契约，所有历史证据保留。

独立Python oracle用 `(分类,channel)` 集合及角色集合推导范围、历史和通知，不读取DUT寄存器，不导入RTL helper或既有模型。9正常配置是1/2/4端口各自的单角色非TL、双角色非TL、双角色TL。每配置2170向量时隙，总19530；定向覆盖32个fatal来源、16种data-only掩码、同时错误/ack、跨角色新原因、idle保持、初始化前/后故障及reset，另有固定种子随机序列。不是任意长度故障序列的形式穷举。

真实集成TB在每配置实例化四个已安装 `upli_native_rx_channel`、实际ordered/receive/KD28 SRAM及四个 `upli_credit_guard`。9配置共453个采样沿，验证：OrigData坏data parity仍真实保存poison拍；坏WrRsp同沿禁止相应角色Read头退休；非TL另一Completer角色的好Request仍接纳并可消费；TL两角色共同阻断；可信已退休Read的旧返回在Drop期间排空；ack不能恢复；共同reset取消旧头；真实Req返回信用guard在初始化前报错，正确归Originator且后来InitDone不自动恢复。独立信用账本核对实际发布量，不从DUT保存队列构造期望。

6种隔离RTL注错为同沿Drop漏接、ack清Drop、data错误被错当fatal、非TL角色范围扩大、忽略信用错误、反向信用按正向掩码接错；所有编译返回0、运行返回1，由ROLE_PRE/POST检出。另在真实RX集成中重复同沿漏接、data误Drop、信用方向接错3种故障，分别实际触发 `ROLE_RX_SAME_EDGE_SCOPE`、`ROLE_RX_DATA_DROPPED`、`ROLE_RX_CREDIT_DIRECTION`。均仅改快照，不改生产或外部源。

`frozen` 与 `frozen_optimized` 普通/-O各31case全部通过：9正常unit、6真实unit faults、4非法参数拒绝、9实际RX集成、3实际集成fault。每次379个记录制品及全部源hash复核一致，normal/-O向量逐字节一致。9正常参数配置的g2001、无豁免Verilator `--lint-only -Wall`、Yosys层级/process/check均通过，所有网表零latch。技能artifact gate最终80/80代码行注释、0error/0warning；首次技能循环常量识别失败保留，修正为显式局部常量边界后通过。整套技能仓库自检会修改隔离目录以外状态，本轮未执行，不声明该门限通过。

## 冻结及安装

RTL SHA256：`ee025ed03e9377cd32dfff19835ab53a6faaff3b0e095da46371657ba52598b2`。候选根为 `build/development/upli_rx_role_fault_controller/`；`freeze.json` 列出全部六个安装文件及SHA。仅复制release下的一个RTL、四个verification文件及本文，不复制release/build历史证据。

实际最终命令：

```sh
python3 build/development/upli_rx_role_fault_controller/release/verification/upli_channels/run_role_fault.py --label frozen --rtl build/development/upli_rx_role_fault_controller/upli_rx_role_fault_controller.v --faults --receive --kd28-root /home/ljy/work/IC/OverFlow --project-root /home/ljy/work/IC/UALink
```

`python3 -O` 使用 `frozen_optimized`；重跑必须换未存在的新label。可安装runner直接用 `ROOT=Path(__file__).resolve().parents[2]`，生产命令为：

```sh
python3 verification/upli_channels/run_role_fault.py --label NEW --faults --receive --kd28-root /path/to/authorized/kd28/root
```

产物写 `build/verification/upli_channels/role_fault/NEW`。仅测试控制器可省略receive及KD28参数。下一步由主线安装并接入唯一实际角色/TL边界，尤其正确连接正向检测和反向信用检测，保持可信信用路径独立，继续完成TX/Isolation及管理恢复。
