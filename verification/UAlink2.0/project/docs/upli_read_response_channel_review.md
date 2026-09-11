# 原生Read Response/Data字段层候选审核

本候选是完整624bit原生有效信息的组合TX字段层，实际实例化公共`upli_parity CHANNEL_KIND=1`。没有TDM/信用/响应收集/接收校验状态，不把库存原来包含传输管理的完整职责宣称为已完成。精确规范和接口边界见 `docs/upli_read_response_channel_execution.md`。

真实旧壳红测在 `shell_red/`：iverilog编译0、仿真1，命中READ_RESPONSE_UNIMPLEMENTED；随后才生成typed RTL。最终独立发布布局重放 `release_replay/build/verification/upli_channels/read_response_channel/portable` 与 `portable_O` 均通过7396正常向量、8个实际RTL故障检出和3项静态检查，各56项制品SHA独立重算零差异。

独立Python oracle不导入RTL或现有parity函数；按字段字典组装624bit信息，并用每byte的bit计数计算even parity。四组字面值直接写期望绕过参考计算，包含全一数据/控制/Auth：各64bit数据组与64bitAuth及48bit控制均为偶数个一。624bit逐位分别有效/invalid/reset测试共1872项；512个数据bit在poison0/1下共1024项；16 status ×4 type ×4 offset ×4 num ×2 last ×2 poison共4096项；另400随机完整元组和4个literal。全部控制字段均参加独立保护敏感性检查，全部512数据位各自验证对应的8个parity组。

单拍向量包括保留编码以及不能组成合法多拍事务的组合，目的在于确认透明字段层不丢位。这不是证明这些编码或跨拍次序合法。所有输入只被本层作为已获准的实际Beat处理；不在扣信用后过滤数据。

八种故障实际修改隔离RTL副本：Tag高位裁剪、Auth高位裁剪、DataError被清零、poison时屏蔽实际data parity输入、非零status时屏蔽data parity输入、控制保护遗漏Src、Data parity组顺序接错、valid parity反相。每项必须编译0、运行1且匹配READ_RESPONSE_MISMATCH才判为检出，编译失败和超时不算故障检查通过。TB验证所有实际输出字段和所有11个发送parity位，没有从DUT内部读取期望。

静态检查包括Verilog-2001编译、严格Verilator -Wall以及Yosys read/hierarchy/proc/opt/check -assert/stat，使用真实公共primitive依赖且无warning豁免。技能artifact gate对owned RTL最终0 errors、10项常量宽度建议；整个技能selfcheck实际执行后仍因外部缺少agents-md-generator/scripts/manage_docs.py失败，保留 `skill/selfcheck.log`，未伪称该工具链自检通过。公共primitive保持生产源码原样，本轮不修改其风格或算法。

候选RTL SHA256：`fdbe47e8a32bddbf2e2897e4945429b1315546985fb77d9bcba84a3b0a9dcce5`；实际公共parity SHA256：`9e12e67c72e50616d5298616d0cabf3e551c8fd7df360ed7c00c722266c32c94`。其它冻结文件及逐项证据见 `freeze.json`。

发布文件为 `release/rtl/upli/upli_read_response_channel.v` 与 `release/verification/upli_channels/` 下的runner/TB/reference。ROOT=parents[2]，只读取生产rtl/upli，输出新建label目录，拒绝覆盖历史产物：

```sh
python3 verification/upli_channels/run_read_response_channel.py --label fresh --faults --static
python3 -O verification/upli_channels/run_read_response_channel.py --label fresh_O --faults --static
```

下一步由主线安装候选并在对应production源码上重放，之后再独立实现真实Response发送管理和接收检查。本轮不含station、RX、Tag生命周期、信用管理、Authorization认证、完整RAS恢复、TL/DL一致性或PPA/STA签核。

Table2-15 AuthTagParity的Driver列与AuthTag字段方向矛盾已在execution明确保留；本候选按本地TX生成保护契约实现，不把实现选择称为规范勘误。

## 对Write Response候选的只读交叉审核

被审源码 `build/development/upli_write_response_channel/upli_write_response_channel.v` SHA256：`aa18d2cb708261565091fcbbd463af8f15e5dff60993d11bb46f3e30ef6b7178`。依据Common Rev2 Table2-18（pp.66–68）和父任务冻结的typed TX契约，9个信息字段为TypeInfo2/Tag11/Status4/Src10/Dst10/Port2/VC2/Pool1/AuthTag64，合计106bit，另valid；正文没有Data、BE、Offset、Last或NumBeats字段。实际代码完整保留这些位宽，使用CHANNEL_KIND2，control低42bit恰好为TypeInfo/Tag/Status/Src/Dst/Port/VC/Pool，高26bit为零；auth独立接64bit，输出parity[0]/[1]/[3]映射分别valid/control/auth。valid=reset&&已获准valid，全部信息字段同一有效门控，共同reset时清零，公共检查关闭而不伪造接收诊断。未发现具体字段、parity或reset接线错误。

边界：上游必须保证真实连接/信用准入、WriteResponse晚于末OrigData的合法时机、授权inactive置零和ISOLATE特殊语义；源ID可为非功能debug值，不能用其路由。Table2-18同样把AuthTagParity Driver列写Originator而AuthTag为Completer，方向疑点不能由本叶私自宣称解决。本只读审核不代替Write作者的仿真证据，也未修改该模块。
