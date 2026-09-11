# 生产 FIFO / SRAM 包装器接线审查

日期：2026-09-11。生产 RTL 和外部 KD28 源码未修改。本项验证实际 `upli_receive_storage` 的结构绑定，不将结构检查当作全载荷形式证明。

使用显式授权依赖、实际 FIFO、映射器及功能 SRAM cells/SP/SDP/TDP 模型，Yosys `hierarchy -check; proc; check -assert` 展开 256/512/600 位 × 深度 1/2/3/5 × 两种无效输出模式，共 24 配置。所有公开端口、FIFO/mapper 数据与地址/使能/时钟连接、逻辑容量、生产地址宽度 `depth.bit_length()`、映射深度 `max(2,depth)`、固定宏类别及宏到实际 SDP 模型的全部引脚均核对通过。

证据位于 `build/verification/sram_storage_map/production_bindings/evidence.json`，包括实际展开图、源哈希、图哈希和每项结果。24 份保留图已在 `python -O` 下重新检查且源/图 SHA 一致。4 项基于真实图的测试在正常与优化 Python 均通过：健康图、读返回旁路、逻辑容量破坏、固定模型写掩码旁路。

```sh
python3 verification/sram_storage_map/check_storage_binding.py --kd28-root /authorized/path --label fresh_binding
python3 verification/sram_storage_map/test_storage_binding.py
python3 -O verification/sram_storage_map/test_storage_binding.py
```

图扰动测试依赖实际 `production_bindings/w600_d3_raw0/binding.json` fixture；复现时将上述标签改为 `production_bindings`，完整命令也见测试文件头。主检查输出新目录下各参数图、日志与 `evidence.json`，拒绝覆盖。

组合边界：此前 FIFO 完整载荷归纳覆盖 8/32/512 位，尚未在 256/600 位上取得同等形式证据；本项生产绑定与 96 组实际宏行为回归不自动补齐这一缺口。宏引脚形式证明的任意 Q 与实际 SRAM 行为需按匹配参数、时钟、地址合法性和读先于写契约组合，未宣称完整 TL 联合归纳或真实宏时序签核。下一项重点是实际端点事务组装与响应完成关联。
