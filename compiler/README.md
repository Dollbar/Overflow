# Compiler

The compiler imports PyTorch/Transformers graphs into MLIR and performs normalization, fusion, quantized
layout, TP/EP/PP partitioning, memory planning, communication insertion, scheduling, and KD-ISA generation.

Outputs must run on the simulator and remain numerically consistent with `models/` references. The compiler
must not depend on undocumented RTL behavior.
