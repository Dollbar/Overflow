# Write 接收器独立验证记录

本轮接管 `endpoint_receive_transactions.v` 和新 `run_write_receiver.py`，核对 WRITE_ENABLE=1 的请求八槽、响应八槽和共享 Data owner 十六槽实现。接收器保存完整 600-bit 退休记录；普通 Write 等待实际 N 个 Beat 及区域 BE 完整后才输出 2048-bit Data/256-bit BE，WriteFull 不等待 BE；WriteResponse 无 Data。WRITE_ENABLE 默认0保留既有 Read 路径。本轮没有修改 core/top、其他模块或库存。

## 发现与修改

`write_receiver_first` 首请求失败不是 RTL 字段错位。增加实际/期望输出后，`write_receiver_diagnostic` 显示期望首项 WriteFull tag2047，却已看到后续 Read tag13。原 TB 在 posedge 阻塞修改 cycle，又组合从 cycle 生成 ready，导致 DUT 与 scoreboard 在同一沿可能观察不同 ready。改为 negedge 驱动后，原 8837 记录/2093 请求/2 响应通过，证据保存在 `write_receiver_stable_ready`。失败标签均未覆盖。

生产 RTL 本轮增加结构解码未使用输出的显式连接、BE 比较和 NUMBEATS 比较的明确九位宽度、非消费字段标记。严格 Verilator 原报 PINMISSING/WIDTHEXPAND/UNUSEDSIGNAL；修正后两模式均 `-Wall` 零警告退出。没有为 TB 竞态改动 RTL FIFO 或数据顺序行为，也没有关闭警告。

EARLY 先处理同字上半旧尾，再扫描下半新 Control，是有功能意义的防死锁处理。新增因果向量：八条 Read 请求已占满请求出口，应用等待先前 ReadResponse 才拉起 request_ready；下一字下半是第九请求，上半是该 Response 最后半 Data。真实 RTL 103 cycles 排空；实际删除 EARLY 选择的 RTL 副本在 200000 cycles 超时，证明不是仅对源代码文本做检查。最初普通向量没有检出该扰动，保留 `write_receiver_extended` 的未检出结果，新增因果向量后才将故障覆盖计为通过。

## 可复跑命令与证据

```sh
python3 verification/endpoint_transaction/run_write_receiver.py --label write_receiver_release --faults
python3 -O verification/endpoint_transaction/run_write_receiver.py --label write_receiver_release_optimized --faults
python3 verification/endpoint_transaction/run_receiver.py --label write_receiver_legacy_final --faults
```

使用新 label，输出位于 `build/verification/endpoint_transaction/<label>/`。每例保存实际 RTL 副本、runner 副本、TB、输入和 expected 元组、compile/run 日志、源 SHA256 与 artifact SHA256；总 result 汇总各例和静态检查。故障仅改变隔离副本，不修改生产 RTL。旧兼容 runner 不变。

混合 suite 共33例：四个正向/恢复场景、25个非法场景、四个真实 RTL 扰动。主向量为8851条记录、2097个请求、26个响应，覆盖2080个合法普通 Write 几何和10个合法 WriteFull，以及多种混排和首尾位置。普通与长反压分别运行全部主向量；因果旧尾和局部 reset 使用独立向量。

主向量检查自然字段起点、跨64B Beat、高位地址、tag高位、ATTR/ASI/META原样交付、普通稀疏/全零 BE、Full 区域 BE 重建、普通 BE 紧随实际2N半字、两个 Write 同Control、Write/ReadResponse共享owner、旧Data和旧BE尾交换、普通Message插空、CWAY无效位忽略、所有五个Write状态、OFFSET/LAST/SPARE无效位容许。请求/响应出口独立长停顿并绕回队列；每次 valid 都比较完整期望元组，包含 stall 期间的值。输入 releases 使用非零变化模式，逐条检查 r_record 保存的600位与同次握手输入一致，不产生第二次信用归还。

25个非法场景包括 multicast命令、Full地址/长度非法、跨256B、NUMBEATS不符、pool/vc/cache/compression不支持、保留状态、WriteResponse带LEN、multicast类型、ReadResponse非法OFFSET、孤立Data/BE、BE提前、范围外BE、用Data替代预期BE、poison/auth、msg/class错配、未知Message、非零mandatory NOP、同Control后段非法字段及跨port Data。要求无该非法字的事务输出、error置位并保持、ready/valid全部封锁；不把静默等待当检测成功。尚未收到BE的合法停顿没有凭空设定协议错误超时。

局部 reset 在旧四Beat WriteFull 已部分收集后清除队列及owner，随后新WriteFull和无Data写响应正常输出，旧事务不泄漏。它只验证本地同步复位，不表示已执行内存可撤销或完整网络隔离恢复。

四个真实RTL扰动分别为Data半字bit翻转、普通BE强制零、请求Tag bit翻转、关闭EARLY导致因果死锁，全部应由输出oracle或明确超时检出。expected 字段以独立接口位宽拼接，数据由逐byte模式构造，不调用 RTL 编码器或新Python Write模型计算期望。

每轮 runner 对 WRITE_ENABLE=0/1 各运行 Icarus `-g2001` 生产源码展开、Verilator `--lint-only -Wall` 和 Yosys `read_verilog/chparam/hierarchy -check/proc/opt/check -assert/stat`。两模式六项检查通过；Yosys mixed模式报告零结构问题。此为综合前端和结构检查，不是工艺映射、PPA、STA、形式等价或联盟认证。旧 Read runner 共41例（包含四个故障）通过；其兼容接口与现有 assembler 未改。

这些是退休记录到 typed 事务的单模块测试，classes/msg 是测试显式提供的元数据，不证明完整 TL classifier、credits 或原始线上序列正确。压缩、poison、认证、多Beat Read、未知tenure恢复仍不支持并显式阻断。完整两Endpoint/Switch、后端执行次数和共享Tag归属由独立总装回归继续验证。
