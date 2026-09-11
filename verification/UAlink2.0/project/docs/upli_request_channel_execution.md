# 原生 UPLI Request Channel 实施契约

依据 UALink Common Specification Rev 2.0 的本地授权正文核对。本文件仅给出实施释义与来源定位，不复制私有正文。本阶段实现 Originator 原生请求发送字段层；完整接收保存、检查、RAS处理与各事务命令执行仍分别交由接收及事务模块完成。

## 精确来源与边界

| 来源 | 确认的实现规则 |
|---|---|
| §2.5，pp.41–42 | station支持1/2/4端口；Req与OrigData共用首次真实Req建立的相位，以端口数为周期持续轮转，包括空闲周期；信用返回不参加TDM |
| §2.6，pp.43–45 | 每端口VC0..3与共享pool信用；接收返回数量编码0..3对应1..4；一次Req消耗一次原账户信用；初始化完成需连续观察大于一周期 |
| §2.7.4，Table 2-2，pp.49–52 | 下表全部原生字段、返回信用接口及四组Request parity；不是TL压缩后的字段 |
| §2.7.8，pp.71–72 | 双向连接且已有足够信用才发Beat；带数据请求与首OrigData同沿，发送前预约全部数据信用；后续数据连续占该port时隙；允许Read覆盖旧数据尾拍 |
| §3.1.1，pp.85–86 | even parity；valid保护每周期检查，其他Request保护在有效周期检查；保护交接须覆盖前一保护结束到后一保护建立的边界 |
| §4.1–4.3，pp.101–104 | 同一UPLI时钟与同步接口reset；reset取消旧状态/信用；四个连接握手电平齐备后才可传Beat，返回信用只要求对应返回方向已连接 |
| §5.1.1，p.105及后续TL字段表 | TL控制/数据半字属于下一级编码，本层不得用128bit TL Read格式取代原生Request全部字段 |

## 完整发送字段

| 原生字段 | 位宽 | 候选输入/输出后缀 |
|---|---:|---|
| ReqVld | 1 | valid |
| ReqPortID | 2 | port |
| ReqASI | 2 | asi |
| ReqAuthTag | 64 | auth_tag |
| ReqSrcPhysAccID | 10 | src |
| ReqDstPhysAccID | 10 | dst |
| ReqTag | 11 | tag |
| ReqNumBeats | 2 | num_beats |
| ReqAddr | 57 | address |
| ReqCmd | 6 | command |
| ReqLen | 6 | length |
| ReqAttr | 8 | attr |
| ReqMetaData | 8 | metadata |
| ReqVC | 2 | vc |
| ReqPool | 1 | pool |

所有字段使用完整位宽；不截断高地址、Tag、ID、授权标签、命令、属性或元数据。除valid外合计189bit。`upli_request_channel`为无时钟、无缓存的组合发送层，具有`i_rstn`与对应`i_*`/`o_*`原生字段；有效输出等于`i_rstn && i_valid`，无效周期所有输出字段及parity清零，这是比规范无效字段不关心更确定的本地行为。无`ready`线上信号、无新增私有线上字段。

四个输出为`o_valid_parity`、`o_auth_tag_parity`、`o_address_parity`、`o_control_parity`。valid保护自身；授权保护64bit AuthTag；地址保护57bit Addr；控制保护Tag11/Len6/Attr8/Cmd6/Meta8/VC2/ASI2/Src10/Dst10/Port2/NumBeats2/Pool1，恰好68bit。三类字段保护互不混入。原候选使用显式XOR；当前生产leaf已接公共parity primitive，并按同一保护集合完成全部输出组合等价验证。

## 唯一发送所有权及连接

主线统一source wrapper只实例化一次已实现`upli_burst_sender`，其内部复用`upli_burst_control`与两个真实`upli_credit_bank`，分别管理Request和OrigData信用。Request leaf不得再实例化bank、连接控制器、TDM计数器、数据预约器或自己的发送队列。`i_valid`必须直接来自该sender的实际`o_req_valid`，不是未获准的candidate_valid；Port/VC/Pool分别取该sender真实输出。

统一sender的`C_REQUEST_WIDTH=184`。内部不增加线上字段的透明容器固定按高到低排列：`{ASI2, AuthTag64, Src10, Dst10, Tag11, NumBeats2, Addr57, Cmd6, Len6, Attr8, Meta8}`。Port/VC/Pool不在容器重复保存，取已扣账的真实控制字段。该打包仅为本地连接约定，不能冒称规范规定的189bit线编码。

实际连接资格来自既有`upli_connection_side`：Originator的rx_connected对应Request/OrigData返回信用方向，beats_connected为双向齐备。共同reset清除连接、银行余额/初始化确认、burst所有权与TDM；本无状态字段层只组合屏蔽reset期间输出。连接不能被本leaf根据局部valid自行建立或撤销。

现有银行消耗沿前已存在的信用和已确认初始化，不能借同沿刚返回的信用或同沿刚完成的初始化。§2.7.4.2（p.52）要求同一端口的Tag跨命令类型唯一，直到最后Response Beat接收才可复用；Tag分配/退休属于上游事务管理，本leaf只保留完整11bit。每次真实ReqVld只扣其port/VC或pool一个Request信用；Data信用独立逐拍扣减，带数据候选发出前由共享burst控制器确认完整尾部容量。不能对已获准并扣账的Req再独立过滤，否则Request与OrigData/银行状态脱节。源必须保持完整候选直到实际accepted，不是线上ready握手。

## 上游资格与后续接收职责

Table 2-2要求未授权请求或无效周期AuthTag为零。当前统一wrapper没有`authorization_active`输入，也不执行授权清零；输入生产者必须在候选发出前将未授权AuthTag置零。后续事务资格层负责落实该条件，授权功能是否启用属于本地配置。leaf有效周期保持所有输入位，不能猜测授权状态。ReqAddr低两位应为零；普通Read的NumBeats应为零，Vendor Defined Read的NumBeats有独立语义；Cmd[5]=1的写/原子/消息类NumBeats必须与实际OrigData拍数匹配。ReqSrc/Dst/ASI/Attr/Metadata在Collective及Vendor命令中存在其他语义，不能把它们统一限制成普通Read/Write配置。命令合法性、256B边界、BE以及业务权限由候选前的事务资格层负责，发送字段层不是完整命令执行器。

返回接口保持四端口原生形状：CreditVld4、CreditPool4、各端口VC合并8、各端口Num合并8、InitDone4；另CreditVldParity保护全部4个valid位且每周期检查，CreditParity保护全部20bit Pool/VC/Num且任一valid时检查，即使部分端口当前无返回也不能只保护被选账户。InitDone不包含在这两个保护集合内。信用错误不能用重新生成parity洗掉；共享wrapper的真实接收检查/RAS诊断须先检输入保护，再交银行。银行当前非法事件整沿保持并报注册诊断；该诊断不撤销已经在线发送的Beat，集成必须把其定义为故障边界并停止后续候选，而非伪称自动恢复。

现有`upli_receive_channel`保存opaque payload及原VC/Pool、按实际容量发初始信用并在真实退休归还原账户；它不含完整Request字段/parity/命令/TDM接收验证，不能把其存在宣称为本次Request完整接收实现。后续接收应先检查valid parity（每周期）、有效周期其他保护及连接，再保存完整元组；非法控制的恢复按RAS层处理，不把受损控制当合法请求或数据poison后继续。

## 当前确定与未覆盖

原生字段位宽、保护集合、信用单位、连接/TDM与首数据原子条件已由上述正文确定。未确定的产品策略包括完整Authorization选择/验证、供应商命令和Collective业务实现、接收控制错误隔离与安全恢复；这些不由字段leaf猜测。本阶段没有普通64B专用限制，也不把字段透传等同于所有命令已经执行。统一source wrapper的真实发送功能、接收功能、TL压缩、DL重放及完整标准一致性分别记录证据。

候选和自检位于`build/development/upli_request_channel/`；先保留实际旧壳编译成功但能力失败证据，再实现typed字段层。验证包括逐字段每bit、固定独立字面值、有效/无效/reset、四保护集合的真实RTL故障以及真实burst sender的连接/信用/TDM/首数据配对；不开展PPA或STA。

所有字段层i_rstn必须与唯一sender及两侧连接控制器使用同一UPLI reset。不能单独复位字段leaf后仍让sender扣账，或让leaf的valid被另一reset域截断。
