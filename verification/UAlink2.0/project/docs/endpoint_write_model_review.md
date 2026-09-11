# 独立 Write 参考模型审查

新增 `model/ualink/endpoint_write.py`、`verification/endpoint_transaction/test_write_model.py` 和 `config/endpoint_write_contract.json`，落实 `endpoint_write_execution.md` 的普通未压缩 Write / WriteFull 完整几何与 BE 语义。没有修改 RTL、库存或现有 Read 模型。本模型不是原生 UPLI、周期仿真或认证/压缩实现。

采用先红后绿：`write_model_red` 在模型文件创建前运行，15 个测试全部因独立 Write 能力缺失而失败，errors=0；实现后 `write_model_green` 同组测试全部通过。最终可复跑命令为：

```sh
python3 verification/endpoint_transaction/test_write_model.py --label write_model_release --faults
python3 -O verification/endpoint_transaction/test_write_model.py --label write_model_release_optimized --faults
```

每次使用新 label，产物位于 `build/verification/endpoint_transaction/<label>/`：`run.log`、`result.json`、四份 owned 源文件的 SHA256 和 `snapshot/`；`--faults` 另生成隔离的模型扰动文件、子运行日志和结果。它不会改写生产模型。重复执行应换新 label，避免覆盖既有证据。

## 已覆盖的语义

15 个行为测试包含普通 64 个 DWORD 起点 × 64 个 LEN 的全部 4096 个几何组合：2080 合法、2016 非法；并枚举同一空间中 WriteFull 恰好 10 个合法起点/长度组合。普通每个合法几何使用全零、全一、交错和首尾 BE 四种模式，共 8320 次 byte-memory oracle 检查。

三组固定 128-bit 请求字面值覆盖普通 CMD=0x28、Full CMD=0x29、高位地址、高 Tag/ID、非零 ATTR/ASI/META 和跨 64B Beat；五组固定 64-bit 响应字面值覆盖状态 0/2/3/6/8，并拒绝其他状态。固定值由单独的逐字段二进制拼接工作表核对，测试代码只保存字面值，不调用模型 encoder 生成 expected。decode 使用这些固定字输入，不能仅以 encode/decode 往返正确证明位段正确。

其他检查包括实际 N 个完整 Data Beat 元组、每 Beat 低/高 256 位顺序、紧随 2N 个 Data 半字的整份区域 BE、普通范围外 BE 拒绝、Full 输入 BE 忽略后重建、全零 BE 仍计一次执行、未修改原 bytes、高地址 memory base、错误完成不更新字节、OFFSET/LAST/SPARE 的 RX 容许及 TX 清零、CLOAD 拒绝/CWAY 忽略、错误响应种类及 LEN/状态、非法输入类型和位宽。

模型内存更新按 Beat/lane 和区域 BE 寻址；测试 oracle 从实际地址枚举应修改的 byte，使用独立的 touched-block 计数，而不调用模型的 Beat/mask/data-halves 推导函数。两者共享规范与输入数据，未共享 RTL 生成器、tenure 或编解码函数。向 RTL 实施代理提供 API 和固定向量仅用于对照；其实际 TB 仍使用独立几何与字节期望，不使用同一模型函数同时制造激励和计算期望。

`--faults` 实际执行四份修改后的模型：把普通 CMD 改成 multicast、Beat 数忽略起始地址偏移、忽略 BE 写满、允许错误 kind 完成 Tag。四项均应以非零退出被测试拒绝。Beat 数错误还会使合法跨 Beat 请求抛出验证异常；这些异常是模型语义被扰动后的检测结果，不算正常通过。正常与 `-O` 都使用 unittest 检查和显式异常，生产模型不依靠会被优化移除的 assert。

## API、事件与边界

`WriteRequest` 保存完整 port/tag/address/src/dst、精确 N 个 512-bit Data Beat、256-bit 区域 BE、full/length/attr/asi/metadata/vc/pool。应用 2048-bit 向量的最低 512 位是相对 Beat0，模型元组仅包含实际 N 项；不用传输的高位不是额外 Beat。普通 `data_halves()` 输出恰好 `2N+1` 项，Full 恰好 `2N` 项。

`encode_write/decode_write` 处理一个 128-bit 请求字段；`encode_response/decode_response` 处理一个无 Data 的 64-bit Write Response。当前模型限制 VC0、VC 信用、CLOAD0、无 poison/auth/compression；这是明确的本地 profile，不把 ASI/ATTR/META 任意非零判为标准非法。WriteFull 在整个应用事务接口忽略输入 BE，是已冻结的应用契约；原生 UPLI 上所有传输 Beat 的 BE 仍须为一。

`ByteMemory` 是不可变的 bytes/base_address/executions；`memory_write` 返回新 memory 和 WriteResponse，任何错误状态均不修改字节。合法调用都计一次后端尝试，包含全零 BE 和非零错误状态。完整地址范围不存在时状态0变为 DECODE ERROR=3；显式非零后端状态优先。这是本地后端策略，不是声称规范强制整事务 rollback 或定义了 ASI/coherence 语义。

`WriteBackend.accept()` 只保存请求与 token，占用容量但不执行；`finish()` 才产生一次执行和响应；`retire_response()` 才释放 token/capacity。结果允许按 token 乱序到达，重复 finish、未接纳 token、容量满、无效状态或目的不符都在修改状态前拒绝。该事件模型不调度 Read/Write 地址依赖，也不表达真实 UPLI 的“最后 Data 后下一拍才能响应”约束；RTL 定向时序测试仍不可省略。

`ReadWriteTags` 以完整 `(port,tag)` 共享预约，检查实际发出事件、response kind、目的、状态和完成退休。跨 Read/Write 的同 Tag 冲突会失败，不同配置端口可使用相同 Tag；错误或重复响应不会释放其他事务。保守地到应用退休才复用 Tag。该小模型仅用于共享所有权事件，不验证 Read 数据内容或组装，不替代现有 Read 模型。它没有 reset epoch、watchdog/isolation 或 Tag 合法复用后迟到响应辨别能力。

下一步是让真实两 Endpoint/Switch 的 Write、稀疏 BE 和混合 Read/Write 执行与逐字节 oracle 对照，并独立统计执行次数。仅最终读回相同数据不足以发现重复执行，模型通过也不代表 RTL 总装、DL 恢复或完整 IP 已完成。
