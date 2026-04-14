.PHONY: help check hbm-model kd28-sram-fifo sta-interfaces sta-kd28 npu-compute-lint \
	npu-compute-sim npu-compute-test npu-compute-waves npu-gemm-vector-lint \
	npu-gemm-vector-sim npu-gemm-vector-test npu-gemm-vector-waves \
	npu-system-lint npu-system-synth npu-system-sim npu-system-sta npu-system-test

PYTHON ?= python3

help:
	@echo "Repository targets:"
	@echo "  make check                  - run repository consistency checks"
	@echo "  make hbm-model              - run the HBM Python and RTL BFM regressions"
	@echo "  make kd28-sram-fifo         - generate and validate KD28 SRAM/FIFO models"
	@echo "  make sta-interfaces         - validate HBM/SerDes interface Liberty scenarios"
	@echo "  make sta-kd28               - validate KD28 SRAM synthetic Liberty scenarios"
	@echo "  make npu-compute-lint       - lint the split NPU compute RTL scope"
	@echo "  make npu-compute-sim        - run NPU compute self-checking RTL tests"
	@echo "  make npu-compute-test       - run all NPU compute verification gates"
	@echo "  make npu-compute-waves      - generate NPU compute directed VCD files"
	@echo "  make npu-system-test        - run NPU integration lint, synth checks, and simulation"
	@echo "  make npu-system-sta         - run NPU DMA 1 GHz generic STA with LIBERTY=<path>"

check:
	$(PYTHON) scripts/check_repository.py

hbm-model:
	$(MAKE) -C simulator/memory test

kd28-sram-fifo:
	$(PYTHON) scripts/generate_kd28_sram_library.py
	$(MAKE) -C verification/kd28 PYTHON=$(PYTHON) test

sta-interfaces:
	$(MAKE) -C technology PYTHON=$(PYTHON) sta-interfaces

sta-kd28:
	$(MAKE) -C technology PYTHON=$(PYTHON) sta-kd28

npu-compute-lint:
	$(MAKE) -C verification/npu/compute lint

npu-compute-sim:
	$(MAKE) -C verification/npu/compute sim

npu-compute-test:
	$(MAKE) -C verification/npu/compute test

npu-compute-waves:
	$(MAKE) -C verification/npu/compute waves

npu-system-lint:
	$(MAKE) -C verification/npu/system lint

npu-system-synth:
	$(MAKE) -C verification/npu/system synth-readiness

npu-system-sim:
	$(MAKE) -C verification/npu/system sim

npu-system-sta:
	$(MAKE) -C verification/npu/system sta-generic LIBERTY="$(LIBERTY)"

npu-system-test:
	$(MAKE) -C verification/npu/system test

# Compatibility aliases for existing automation. New integrations should use
# the npu-compute-* names above, which match the split source hierarchy.
npu-gemm-vector-lint: npu-compute-lint
npu-gemm-vector-sim: npu-compute-sim
npu-gemm-vector-test: npu-compute-test
npu-gemm-vector-waves: npu-compute-waves
