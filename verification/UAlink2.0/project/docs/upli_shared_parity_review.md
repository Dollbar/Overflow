# Typed TX leaf 共用 parity 生成器转换审查

本次只转换 Request 与 OrigData 的组合发送叶模块；每个模块真实实例化一次 `upli_parity`，原有 typed 字段赋值保持不变。未修改生产 RTL、两个原始 leaf 候选或 root 的原始 primitive 候选。可安装文件位于本目录 `rtl/`，与 `release/rtl/upli/` 逐字节相同。

Request 使用 `CHANNEL_KIND=0`，控制输入完整 68 位为 `{tag,length,attr,command,metadata,vc,asi,src,dst,port,num_beats,pool}`。valid、地址、授权标签和控制均来自既有共同 `i_rstn && i_valid` 门控后的实际输出；原生 parity 直接接公共位 0/1/2/3。OrigData 使用 `CHANNEL_KIND=3`，控制低 9 位为 `{pool,vc,port_id,offset,error,last}`，所有 512 位数据及 64 位 BE 原样接入，包括 BE 无效的字节；valid 为零仍保留既有 raw 透传和 parity 生成。原生四组输出直接接公共位 0、1、11:4、12。两个实例均关闭接收校验，未消费的输入组为零，诊断输出完整命名连接。

两份 leaf 没有新增时钟、状态、pipeline、credit bank 或时序所有权；请求信用、首拍 Req/OrigData 同沿以及 TDM 继续由共同发送器负责。本审查不代替 sender 的状态验证，也不证明 primitive 的所有接收错误分类。合并 primitive 副本和 OrigData 副本只补充 `timescale 1ns/1ps`，外部严格 lint 不需要 timescale override。

| 验证 | Request | OrigData |
|---|---:|---:|
| SAT 自由二态输入位数 | 191 | 586 |
| 同时比较的全部输出位数 | 194 | 597 |
| 原始 XOR 对共享 primitive 全组合等价 | exit 0 | exit 0 |
| `hierarchy -check` / `check -assert` | 通过 | 通过 |
| leaf 内实际 primitive 数量 | 1，kind 0 | 1，kind 3 |
| leaf 内 `$reduce_xor` 数量 | 0 | 0 |
| Icarus `-g2001` 编译 | exit 0 | exit 0 |
| Verilator `--Wall --language 1364-2001` | exit 0 | exit 0 |

原始 XOR 代码作为独立 golden，无需调用新 primitive 或共享参考函数。Yosys 在 flatten 前保存真实 hierarchy；脚本检查 primitive 输出 net ID 与每个原生 parity 输出 net ID 完全相同，再 flatten 并使用 `sat -verify -prove-asserts -set-def-inputs` 比较全部输出。证明覆盖所有确定 0/1 输入组合，包括 Request reset/idle 与 OrigData valid=0；不声称四态 X/Z 仿真等价、工艺 PPA 或完整 UPLI 合规。

红测 `runs/shared_parity_red` 在转换实现前将原 XOR 中 Tag 高位删去，真实 SAT exit 1 并产生反例。最终 `runs/shared_parity_release` 的两项实际改线故障均 exit 1、存在 JSON/VCD witness，runner 判定检出成功：

- `tag_high_fault`：公共控制输入删去 Tag[10]；反例 rstn=valid=1、Tag[10]=1，gold 控制 parity 为 1，mutant 为 0，其余字段输出不变。
- `be_mask_fault`：实际 primitive 数据输入先按每字节 BE 清零；反例 valid=0、BE=0、原始数据非零，gold 数据 parity 为 `8'h80`，mutant 为 0。此反例直接验证 idle 和无效字节不能遮蔽原始保护组。

最终脚本、源副本、层级 JSON、工具完整命令/返回码/日志和所有产物 hash 均保存在各 label 中；早期 `shared_parity_first` 也保留，其 lint 使用过 timescale override，最终标签已移除。`runs/shared_parity_skill_release` 使用原冻结 typed spec 审查两份转换 leaf：Request 0 errors / 9 模板样式 warnings，OrigData 0 errors / 0 warnings，同句注释检查分别 69/69、50/50。安装级 `validate_verilog_skill.py` exit 1：缺少 `/home/ljy/.codex/skills/agents-md-generator/scripts/manage_docs.py`；这是本地 skill 安装门禁 HOLD，未改动或安装技能，也未将其记为验证通过。

可复现开发验证：

```sh
python3 build/development/upli_shared_parity/run.py --label NEW
python3 build/development/upli_shared_parity/check_skill.py --label NEW_SKILL
```

可发布验证材料在 `release/verification/upli_channels/`：`run_shared_parity.py` 与 `fixtures/upli_request_channel_xor.v`、`fixtures/upli_orig_data_channel_xor.v`。runner 默认只读取工程 `rtl/upli/` 下三个模块及同目录 fixtures，不导入或读取开发目录；原 XOR fixtures 只用于验证，不可加入生产 RTL 编译清单。安装后的运行命令为：

```sh
python3 verification/upli_channels/run_shared_parity.py --label NEW
```

输出为 `build/verification/upli_channels/shared_parity/NEW/`。发布副本已在独立 release 工程布局执行 `portable_release`，两项等价、两组编译/lint 和两项实际故障均达到预期。此目录内结果位于 `release/build/verification/upli_channels/shared_parity/portable_release/`。仅安装 `release/rtl/` 与 `release/verification/` 所需文件，不将开发证据误作源依赖。下一步由 root 安装后运行共同 sender/native typed 的实际时序回归。

冻结 SHA256：

| 文件 | SHA256 |
|---|---|
| `rtl/upli_request_channel.v` | `01e1d95d86af69e4b78c65590a1575eb9c2700370f968ecc85d4c487c23bccb7` |
| `rtl/upli_orig_data_channel.v` | `04e0a789c80e6d52e825af77a123e76d8c0f886f347692dd0a9e9c3f0dc6457f` |
| `rtl/upli_parity.v` | `9e12e67c72e50616d5298616d0cabf3e551c8fd7df360ed7c00c722266c32c94` |
| `release/verification/upli_channels/run_shared_parity.py` | `b0d770b24796545cd3654fa28d30db57d97fa7f2a2f97b3f06690772197f51e7` |
| 原 Request XOR fixture | `a2e02374041e4615c0c68e449747cbd85594226fe880c3b3f7e0e6577fd57fda` |
| 原 OrigData XOR fixture | `36bce7856ddea52b0e76090e3ae1d166dac64bda4bf9706068f358b83c3eb530` |
| root 原 primitive（未改） | `d26b82240c8224fa871d9d13fbe10e3386da07925ee89b083be6e208ac1f58cd` |
