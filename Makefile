.PHONY: help check hbm-model kd28-sram-fifo sta-interfaces sta-kd28 kdlink-preflight \
	kdlink-model kdlink-rtl kdlink-static kdlink-formal kdlink-coverage kdlink-sta \
	kdlink-release-check kdlink-clean npu-compute-lint npu-compute-sim \
	npu-compute-test npu-compute-waves npu-gemm-vector-lint npu-gemm-vector-sim \
	npu-gemm-vector-test npu-gemm-vector-waves

PYTHON ?= python3
KDLINK_JOBS ?= 4
KDLINK_TIMEOUT ?= 1200
KDLINK_STA_ARGS ?=

help:
	@echo "Repository targets:"
	@echo "  make check                  - run repository consistency checks"
	@echo "  make hbm-model              - run the HBM Python and RTL BFM regressions"
	@echo "  make kd28-sram-fifo         - generate and validate KD28 SRAM/FIFO models"
	@echo "  make sta-interfaces         - validate HBM/SerDes interface Liberty scenarios"
	@echo "  make sta-kd28               - validate KD28 SRAM synthetic Liberty scenarios"
	@echo "  make kdlink-preflight       - audit repository paths, dependencies, and open tools"
	@echo "  make kdlink-model           - run the portable KDLink Python model regression"
	@echo "  make kdlink-rtl             - run all KDLink RTL simulations"
	@echo "  make kdlink-static          - run KDLink lint and structural CDC gates"
	@echo "  make kdlink-formal          - run the portable KDLink Yosys SAT suite"
	@echo "  make kdlink-coverage        - acquire and gate KDLink RTL coverage"
	@echo "  make kdlink-release-check   - run every portable KDLink release gate sequentially"
	@echo "  make kdlink-sta KDLINK_STA_ARGS='...' - run optional external-Liberty STA"
	@echo "  make kdlink-clean           - remove generated KDLink and technology work output"
	@echo "  make npu-compute-lint       - lint the split NPU compute RTL scope"
	@echo "  make npu-compute-sim        - run NPU compute self-checking RTL tests"
	@echo "  make npu-compute-test       - run all NPU compute verification gates"
	@echo "  make npu-compute-waves      - generate NPU compute directed VCD files"

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

kdlink-preflight:
	$(PYTHON) scripts/check_kdlink_release.py

kdlink-model:
	$(PYTHON) simulator/kdlink/scripts/run.py --model --timeout $(KDLINK_TIMEOUT)

kdlink-rtl:
	$(PYTHON) simulator/kdlink/scripts/run.py --group all --jobs $(KDLINK_JOBS) --timeout $(KDLINK_TIMEOUT)

kdlink-static:
	$(PYTHON) verification/kdlink/scripts/run_static.py

kdlink-formal:
	$(PYTHON) verification/kdlink/scripts/run_formal.py

kdlink-coverage:
	$(PYTHON) verification/kdlink/scripts/run_coverage.py --jobs $(KDLINK_JOBS)

kdlink-sta:
	$(PYTHON) scripts/check_kdlink_release.py --require-sta
	$(PYTHON) verification/kdlink/scripts/run_sta.py $(KDLINK_STA_ARGS)

kdlink-release-check:
	$(MAKE) kdlink-preflight PYTHON=$(PYTHON)
	$(MAKE) kdlink-model PYTHON=$(PYTHON) KDLINK_TIMEOUT=$(KDLINK_TIMEOUT)
	$(MAKE) kdlink-rtl PYTHON=$(PYTHON) KDLINK_JOBS=$(KDLINK_JOBS) KDLINK_TIMEOUT=$(KDLINK_TIMEOUT)
	$(MAKE) kdlink-static PYTHON=$(PYTHON)
	$(MAKE) kdlink-formal PYTHON=$(PYTHON)
	$(MAKE) kdlink-coverage PYTHON=$(PYTHON) KDLINK_JOBS=$(KDLINK_JOBS)
	$(MAKE) check PYTHON=$(PYTHON)

kdlink-clean:
	$(MAKE) -C simulator/kdlink PYTHON=$(PYTHON) clean
	$(MAKE) -C technology PYTHON=$(PYTHON) clean
	rm -rf verification/kdlink/cdc/work verification/kdlink/coverage/work \
		verification/kdlink/formal/work verification/kdlink/sta/work

npu-compute-lint:
	$(MAKE) -C verification/npu/compute lint

npu-compute-sim:
	$(MAKE) -C verification/npu/compute sim

npu-compute-test:
	$(MAKE) -C verification/npu/compute test

npu-compute-waves:
	$(MAKE) -C verification/npu/compute waves

# Compatibility aliases for existing automation. New integrations should use
# the npu-compute-* names above, which match the split source hierarchy.
npu-gemm-vector-lint: npu-compute-lint
npu-gemm-vector-sim: npu-compute-sim
npu-gemm-vector-test: npu-compute-test
npu-gemm-vector-waves: npu-compute-waves
