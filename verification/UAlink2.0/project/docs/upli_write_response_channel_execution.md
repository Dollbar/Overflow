# 原生 UPLI Write Response 发送字段契约与候选复核

依据 Common Rev 2.0 §2.7.6/Table 2-18、§2.5、§2.7.8、§3.1.1/§3.1.2。生产库存的 generic shell 仍为 planned，完整职责包括原生通道及信用；本轮只交付 TX 组合字段/保护码子集，不将 RX、信用返回、隔离或完整 station 标成完成。私有正文不复制发布。

## 冻结接口

`upli_write_response_channel` 无参数、时钟或存储。`i_rstn` 是共同复位的组合屏蔽条件，`i_valid` 是上游已获连接、信用及正确时隙资格的实际发送事件；`o_valid=i_rstn&&i_valid`。全部字段 idle/reset 为零，有效时完整透传，不增加原生 ready，不接受或执行未完成命令。

| 输入 / 输出 | 位数 | 内容 |
|---|---:|---|
| `i_type_info` / `o_type_info` | 2 | 原请求类别 |
| `i_tag` / `o_tag` | 11 | 原请求完整标签 |
| `i_status` / `o_status` | 4 | 原生响应状态 |
| `i_src` / `o_src` | 10 | 响应源 ID，仅 debug 用途，不依赖它执行功能 |
| `i_dst` / `o_dst` | 10 | 返回路由目标 ID |
| `i_port` / `o_port` | 2 | 原生端口及 TDM 标识 |
| `i_vc` / `o_vc` | 2 | 原请求 VC，特殊控制事件按其规则提供 |
| `i_pool` / `o_pool` | 1 | 实际使用 Pool 或专用 VC 信用 |
| `i_auth_tag` / `o_auth_tag` | 64 | 完整响应授权标签 |

另输出 `o_valid_parity`、`o_auth_tag_parity`、`o_control_parity`。本通道没有 Data、ByteEn、Address、Offset、Last、NumBeats，不能套用 Read Response 或 TL 半 Flit 格式增添这些字段。

Tag/Dst/VC 来自原请求，Src 对应原目标但只能作为 debug 信息。授权未启用时上游必须提供 AuthTag=0，本模块没有 auth-enable；idle 无条件零。ISOLATE 的字段忽略、角色适用和状态转换由上游专用策略执行，本层不解释成普通 Write 完成。status/type 合法性依赖原命令与角色，本层保留全部位，不擅自重写 vendor/INC/ISOLATE 编码。

Table 2-18 的 AuthTag 数据 Driver 是 Completer，AuthTagParity 行却标 Originator。这里按同表数据所有权、WrRspVld 时序和 §3.1.1 的发送保护关系，由实际 Completer TX 数据生成校验；记录表内方向矛盾，不称为额外规范确认。

## 公共 parity 与站级边界

真实实例化公共 `upli_parity`，固定 `CHANNEL_KIND=2`。`i_control[41:0]={o_type_info,o_tag,o_status,o_src,o_dst,o_port,o_vc,o_pool}`，高26位补零；共42控制位。Auth64 独立接实际 `o_auth_tag`。公共码位0/3/1分别连接 valid/auth/control parity，均从实际输出字段生成。关闭接收检查，地址/数据/BE/信用输入置零，未使用诊断明确终止，不暴露虚假 RX 接口。

偶校验的接收检查规则是 Valid 每周期、Auth/控制仅 valid 周期；RX 检查、认证验证和错误恢复不在该 TX leaf 内。Write Response 每个响应一个 Beat，§2.5 的 WrRsp TDM 相位由首个有效 WrRsp 独立建立，不共享 Request/OrigData 或 Read Response 相位。真实 station TX 调度器负责信用初始化、扣账、返回及正确 PortID。按 §2.7.8，Write Response 不得早于最后 OrigData 接收后的下一周期；命令执行器和调度器负责该因果关系，本层无历史验证它。

建议站内完整 bundle106 为 `{Auth64,Type2,Tag11,Status4,Src10,Dst10,Port2,VC2,Pool1}`；若调度器独立提供 Port/VC/Pool，则 payload101 为其余字段。该建议是本地打包约定，不是 UPLI/TL 序列化格式，也不是本模块新加接口。

已核对 `model/ualink/upli_parity.py` 的偶校验/信用边界与 `upli_tdm.py` 的独立 wr_rsp 相位。原 parity model 只直接提供 OrigData/credit 检查，不能冒充已有 Write Response 全字段模型。本轮期望通过独立逐字段 population-count 构造，不调用公共 RTL helper 或原模型。

## 实际验证和可发布入口

发布副本在候选 `release/rtl/upli/upli_write_response_channel.v`、`release/verification/upli_channels/run_write_response.py` 与 `write_response_tb.sv`。runner ROOT 为自身 `parents[2]`，默认直接读 `ROOT/rtl/upli/` 下本模块和公共 parity，不依赖 development；候选通过显式 `--rtl`、`--parity` 覆盖。结果写 `ROOT/build/verification/upli_channels/write_response/LABEL`，拒绝覆盖 label。健康源只读并核对前后哈希，故障仅修改独立产物副本。

安装后复跑：

```sh
python3 verification/upli_channels/run_write_response.py --label write_response_final
python3 verification/upli_channels/run_write_response.py --label write_response_fault_pool --fault pool_parity
```

候选可从任意 cwd 调用 release runner 并显式传候选 RTL/公共 parity 路径。输出包括向量、g2001/仿真/严格 lint/Yosys 日志、netlist JSON、源与产物哈希。下一步接实际 Write Response 发送事件，另验证站级信用、执行完成因果和 TDM。

真实测试3508行：106个字段位各自 walking-one/walking-zero及四种 reset/valid 组合，全部2048种 Type/Status/Port/VC/Pool 编码保持，固定高位 Tag/ID/Auth 模式和600个固定种子随机样例。所有字段及独立 parity 全宽比较，idle/reset 的 Auth 和其他字段必须零；编码保持覆盖不代表每个组合都是合法协议事务。

`old_shell_red` 为旧壳缺原生端口的真实展开失败，不是旧行为失败证明。候选 `initial_green` 和从 `/tmp` 的 `portable_final_replay` 均通过3508行。五个实际源故障——Tag最高位清除、Auth丢弃、控制校验漏Pool、reset门控去除、Status高位翻转——全部编译0、运行1，以 `WRITE_RESPONSE_COMPARE` 检出。`portable_final` 是发布复制前误从错误 cwd 发起的编排失败，保留记录，不计RTL通过或失败。

Icarus `-g2001`、Verilator `-Wall` 无豁免、Yosys `memory_map; check -assert` 全通过，实际一个公共 parity 实例、零锁存器。技能 `validate_verilog_artifacts` 以组合接口契约检查通过0错误/0警告，69行RTL代码均有语义注释；公共依赖另有独立审查，不把本报告扩大成其严格注释成绩。整技能自测会启动清理外部状态/缓存，超过本轮目录所有权，未执行并记录 not_run，不称全部技能自测闭合。

冻结 RTL SHA-256：`aa18d2cb708261565091fcbbd463af8f15e5dff60993d11bb46f3e30ef6b7178`。实际公共 parity SHA-256：`9e12e67c72e50616d5298616d0cabf3e551c8fd7df360ed7c00c722266c32c94`。完整发布文件、命令及健康/红测/故障哈希在候选 `freeze.json`。未改生产 RTL、库存或 top。
