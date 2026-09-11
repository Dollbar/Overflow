# UPLI parity 独立审查

审查范围为 Common Rev 2.0 Tables 2-2/2-15/2-18/2-21、§3.1.1/§3.1.2，候选 `build/development/upli_parity/upli_parity.v`、`docs/upli_parity_execution.md` 及既有 `model/ualink/upli_parity.py`。只读核对保护组、限定时机和诊断分类，未修改候选或生产 RTL。本次未发现确定的功能错误；这是静态独立审查，不新增声称动态覆盖或完整 RAS 实现。

| 通道 | 控制组逐字段位宽合计 | 核对 |
|---|---|---|
| Request | Tag11+Len6+Attr8+Cmd6+Meta8+VC2+ASI2+Src10+Dst10+Port2+NumBeats2+Pool1=68 | 使用 control[67:0]；地址57、Auth64独立 |
| Read Response | Type2+Tag11+Status4+Offset2+Last1+NumBeats2+VC2+Src10+Dst10+Port2+DataError1+Pool1=48 | 使用 control[47:0]；Auth64、8组Data64独立 |
| Write Response | Type2+Tag11+Status4+Src10+Dst10+Port2+VC2+Pool1=42 | 使用 control[41:0]；Auth64独立 |
| OrigData | Last1+Error1+Offset2+Port2+VC2+Pool1=9 | 使用 control[8:0]；8组Data64、BE64独立 |

生成逻辑不依赖 `i_check_enable` 或 valid；检查逻辑仅通过 `checked` 限定诊断。Valid 与 CreditValid parity 每个启用检查周期都检查，包括 valid=0，可发现丢失或多余有效信号；控制、地址、Auth、Data、BE 只在本通道 valid 时检查。不存在的保护组生成零且不检查收到的值。上部未使用 control 位不进入 parity，符合各通道实际组宽。

CreditFields 的 VC8、Num8、Pool4 共20位完整参与生成；任意一个 CreditValid=1 时检查整个20位组，未按端口 valid 掩掉其他端口字段。四个 CreditValid 位整体具有单独 parity，与原模型一致。不能因没有启用某端口就删除其原生信用字段的保护。

Data 每个自然64位组都包含未选和 poison 数据，未使用 BE 掩码。OrigData ByteEnParity 原表描述含自引用字样，采用 §3.1.1 明确的 BE 独立保护要求及原模型解释为完整 BE64 偶校验是合理且已公开标注的条款解释。

`o_control_error` 包括 Valid、控制、Request地址和两个信用组；`o_data_error` 包括全部Data组以及 BE；Auth parity 独立输出 `o_auth_error`。§3.1.2 的明确 Control/Data 枚举没有 AuthTagParity，保留独立诊断避免擅自定义标准分类，但整合层仍须明确 Auth parity 错误的响应，不能把此输出当认证验证成功/失败。poison 字段自身属于控制 parity，BE parity 错误属于 Data Error；这两个概念不能互换。RX保护重叠、poison注入与隔离/恢复仍不在本模块内。

`CHANNEL_KIND` 合法范围0..3；非法值在 check_enable=1 时给 control_error，文档与实现一致。此为本地配置诊断，未宣称协议线上编码。当前合约采用完全组合 leaf，复位和检查使能由调用层控制。后续 typed wrapper 的字段拼接仍须逐字段验证，单独 leaf 正确不能证明 wrapper 未漏字段。

审查快照 SHA-256：

- RTL `d26b82240c8224fa871d9d13fbe10e3386da07925ee89b083be6e208ac1f58cd`
- 执行契约 `8c1dd980d6b4176d9dbd587018b00c67108e5d40596bf49ce0f0ce6d8ae61026`
- 私有 Common 正文 `15cd742c536e1e701a958db8a04f54666b072b8d95a72a834b0aa7d2c58e3383`（正文不复制发布）
