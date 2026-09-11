# Endpoint Read / Response 字段编码评审

本次将 `rtl/endpoint/endpoint_read_encode.v`、`endpoint_response_encode.v` 两个未实现服务壳替换为真实 Verilog-2001 组合编码器。实现范围是已冻结的 single64B Read 字段 profile；这两个模块没有事务队列、Tag 生命周期、内存服务、Data 输入或完成握手，不能据此声明真实 Read→completer→Response→Tag 完成闭环。

## 来源和接口

字段定义沿用 `config/endpoint_transaction_contract.json`，独立固定原始 hex 与 `model/ualink/endpoint_transaction.py` 已核对。正式来源为 `specs/private/common.txt` 对应 Common 2.0：Table 5-29 / §5.9.1 p137 的 128 位请求字段，Table 5-30 / §5.9.2 pp138–139 的 64 位响应字段；Read CMD=3 与无 OrigData 见 Table 2-12 p57；状态 0/3 及错误响应仍须提供完整数据见 §2.7.5.1 Table 2-16 pp64–65。规范正文及校验值保留于契约，不复制受限规范正文到本报告。

共同输入为 `i_valid`、`i_tag[10:0]`、`i_src[9:0]`、`i_dst[9:0]`；共同输出为 `o_valid`、`o_error`、`o_control[255:0]`。这是局部有类型字段服务接口，不是原始 UPLI 线接口，也不再兼容旧研发壳的通用 data/meta 端口。

| 编码器 | 附加输入 | 当前允许值：局部实现子集 |
|---|---|---|
| Read | `i_address[56:0]`, `i_length[5:0]`, `i_attr[7:0]`, `i_vc[1:0]`, `i_pool`, `i_asi[1:0]`, `i_metadata[7:0]` | 地址低 6 位为 0；length=15；attr=FF；VC/pool/ASI/metadata=0 |
| Response | `i_status[3:0]`, `i_num_beats[1:0]`, `i_offset[1:0]`, `i_last`, `i_vc[1:0]`, `i_pool` | status=0 或 3；num_beats/offset/VC/pool=0；last=1 |

请求字段保留完整 `address[56:2]`，低 2 位按规范省略；64 字节对齐是当前局部子集的进一步限制。编码器不做 4 KiB 截断，也不判定地址是否映射到内存。CLOAD/CWAY/NUMBEATS 发零。响应 RD_WR=1、RSPTYPE=0、SPARE=0。响应 Tag 和源/目标交换由调用方负责，这里不产生关联关系，也不检查 debug-only SRC。

合法且有效输入时，字段放在 Control 的最低自然对齐位置，剩余 sector 全零；现有 TL 消费器将这些零 sector 识别为无请求/响应、无 Data tenure 的 NOP。有效但超出子集时 `o_valid=0,o_error=1,o_control=0`；`i_valid=0` 时所有输出为零，无论其余输入的 profile 是否有效。`o_error` 是局部诊断，不是规范响应状态或链路错误码。

## 独立验证与实测

运行器 `verification/endpoint_transaction/run_fields.py` 仅依赖 Python 标准库和 Icarus `iverilog` / `vvp`。工具从 PATH 查找，也可用 `--iverilog` / `--vvp` 显式传入。根路径从脚本位置解析，`--label` 必须创建新目录，不覆盖已有证据。

```sh
python3 verification/endpoint_transaction/run_fields.py --label fields_final --faults
python3 -O /absolute/repo/verification/endpoint_transaction/run_fields.py --label fields_optimized
```

上面的标签已有实测结果，重跑时换新标签。输出为 `build/verification/endpoint_transaction/<label>/result.json`、`vectors.json`，以及每个用例目录的实际 RTL 快照、生成 TB、仿真可执行文件、编译和仿真日志。结果保存工具路径、版本、编译/执行命令、源文件及产物 SHA256。最终 `fields_final` 的源文件和全部产物校验已核对一致。

先在原始壳上运行 `--shell-baseline --label fields_red_both`，分别把 Read 和 Response 正向首向量放到最前；两个壳都成功编译，然后由 `FIELD_SCOREBOARD` 实际断言失败，观测到 valid=0/error=1/control=0。该模式仅用于历史旧壳接口；在实现后的有类型接口上重跑红阶段，应使用保留目录内原始壳快照及记录的编译/仿真命令。红阶段的 `passed=true` 表示预期失败被观察到，不表示旧壳具有功能。

最终正向测试共 1,345 向量：Read 合法 86、非法 586、idle 587；Response 合法 35、非法 25、idle 26。检查依据为 6 个独立固定原始 hex、完整 Tag/源 ID/目标 ID 的 walking bits、Read 地址 bit 6..56 的 walking bits、所有有限 profile 选择器非法值和地址低 6 位逐位非法值、每个非法 profile 的 idle 对照，以及拒绝后恢复合法输入。不是随机覆盖，也不宣称遍历所有 Tag×ID×地址组合；4 态 X/Z 输入未定义为本次 profile。

每条向量比较 `{o_valid,o_error,o_control[255:0]}` 的全部位；期望值使用独立常量/位注入构造，不调用生产编码器、模型 encode/decode 或读取契约位段来生成 oracle。TB 同时实例化实际 `tl_control_decode` 与 `tl_control_tenure`，独立检查字段起点、请求/响应数、语义状态和 Data/BE 描述符：Read 为一个请求、0 Data；正常及 status=3 Response 都是一个响应、2 个 256 位 Data 半 Flit；idle/拒绝是零字段零 tenure。这只证明 Control 派生的 Data 需求，不证明真实 Data 已提供。

| 实际故障：只修改证据目录 RTL 副本 | 检出结果 |
|---|---|
| Read 地址缩为低 12 位 | fixed_max 全位断言失败 |
| Read Tag bit 10 丢失 | fixed_max 全位断言失败 |
| Read valid 绕过 profile 检查 | reject_address_1 全位断言失败 |
| Response RD_WR 错为 0 | response/fixed_zero 全位断言失败 |
| 实际 TL tenure 消费器遗漏普通 Read Response Data 计数 | 全位输出仍正确，独立 TL_CONSUMER 断言失败 |

`fields_final`：1,345 正向全过，5/5 故障被上述断言检出；故障编译全部成功，没有以编译错误充当检出。`fields_optimized` 从 `/tmp` 运行 Python `-O`，1,345 条全部通过，检查不依赖 Python `assert`。Icarus 为 12.0。两生产模块分别通过 `iverilog -g2001 -Wall`、Verilator 5.050 `--lint-only -Wall` 和技能独立 lint；后者各为 0 errors / 0 warnings。

`fields_static` 保留静态日志与按单模块限定范围的 `validate_verilog_artifacts` 报告：两模块均 0 errors，各 9 个模板布局警告（双语/修订头及七个不适合这类短组合模块的模板分区）。逐代码行中文注释检查通过。最初将整个 endpoint 目录误交给双模块 spec 的报告另有范围错误，不能用于这两个模块的结论；单模块 `endpoint_*_artifacts.json` 才是有效范围。技能全局 `validate_verilog_skill.py --no-require-remote` 因环境缺少 `/home/ljy/.codex/skills/agents-md-generator/scripts/manage_docs.py` 中止，故不宣称技能全局门通过。

## 后续接入边界

本次单位验证不编译角色聚合层。库存的 `existing_partial` 状态及旧壳实例移除由 root 统一维护；调用端需接新有类型端口。这里无时钟、寄存器、复位或 CDC，跨域和下游背压由调用端负责；`o_valid` 不能代替实际 TL/DL 接纳，不能据此释放 Tag 或扣信用。

下一步复用这两个字段编码器，实现真实请求接收、完整 57 位地址内存服务、由请求派生响应 Tag/ID，以及两 Data 半 Flit 组装与 Tag 完成关联。再连入已验证的 `tl_tx_prepared` / DL 实际接纳边界。任意长度/掩码、其他响应状态、Write/Atomic/INC、认证/压缩、超时/reset/epoch、完整 native UPLI 仍未实现；A19 CRC 位序及其他开放规范问题保持开放。

最终提交清理运行器第118行尾随空格后，root使用`--label typed_final_fields --faults`重新执行，1345正向与5项故障仍全部达到预期；RTL未变，最终入口SHA以该结果为准。
