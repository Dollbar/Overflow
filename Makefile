.PHONY: help check hbm-model kd28-sram-fifo sta-interfaces sta-kd28 kdlink-preflight \
	kdlink-model kdlink-rtl kdlink-static kdlink-formal kdlink-coverage kdlink-sta \
	kdlink-release-check kdlink-clean npu-compute-lint npu-compute-sim \
	npu-compute-test npu-compute-waves npu-gemm-vector-lint npu-gemm-vector-sim \
	npu-gemm-vector-test npu-gemm-vector-waves npu-system-lint npu-system-synth \
	npu-system-sim npu-system-sta npu-system-sta-nangate45 npu-system-test \
	npu-pod-lint npu-pod-synth npu-pod-sim npu-pod-test npu-pod-noc-test \
	npu-pod-array-lint npu-pod-closure npu-command-lint npu-command-synth \
	npu-command-sim npu-command-test npu-noc-lint npu-noc-synth \
	npu-noc-formal npu-noc-formal-deep npu-noc-sim npu-noc-vip npu-noc-coverage npu-noc-test \
	npu-noc-closure npu-owned-rtl-test

PYTHON ?= python3
REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
OPENROAD_FLOW_ROOT ?= $(REPO_ROOT)/third_party/OpenROAD-flow-scripts
NANGATE45_LIBERTY ?= $(OPENROAD_FLOW_ROOT)/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib
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
	@echo "  make npu-system-test        - run NPU integration lint, synth checks, and simulation"
	@echo "  make npu-system-sta         - run NPU DMA 1 GHz generic STA with LIBERTY=<path>"
	@echo "  make npu-system-sta-nangate45 - run NPU DMA STA with OpenROAD-flow-scripts Nangate45"
	@echo "  make npu-pod-test           - verify complete Pod and router-independent NoC attachment"
	@echo "  make npu-pod-noc-test       - verify only the fast Pod/NoC attachment handoff"
	@echo "  make npu-pod-array-lint     - elaborate the complete 2x4 Pod/NoC shell"
	@echo "  make npu-pod-closure        - run Pod tests, four-seed array stress, and coverage gates"
	@echo "  make npu-noc-closure        - run the complete 2x4 NoC lint/synth/formal/sim/coverage gate"
	@echo "  make npu-noc-vip            - run the reusable NoC source/sink/monitor/checker VIP smoke test"
	@echo "  make npu-noc-formal-deep    - run the optional four-VC 10-step Router SAT proof"
	@echo "  make npu-command-test       - verify decoded command routing and completion aggregation"
	@echo "  make npu-owned-rtl-test     - run all NPU-owned RTL gates (excludes external NoC/system CDC and physical signoff)"

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

npu-system-lint:
	$(MAKE) -C verification/npu/system lint

npu-system-synth:
	$(MAKE) -C verification/npu/system synth-readiness

npu-system-sim:
	$(MAKE) -C verification/npu/system sim

npu-system-sta:
	$(MAKE) -C verification/npu/system sta-generic LIBERTY="$(LIBERTY)"

npu-system-sta-nangate45:
	$(MAKE) -C verification/npu/system sta-generic \
		LIBERTY="$(NANGATE45_LIBERTY)" \
		CELL_MAP="$(REPO_ROOT)/verification/npu/system/STA/scripts/nangate45_cells_map.v" \
		ABC_CONSTR="$(REPO_ROOT)/verification/npu/system/STA/scripts/abc_nangate45.constr" \
		DRIVING_CELL=BUF_X1 DRIVING_PIN=Z

npu-system-test:
	$(MAKE) -C verification/npu/system test

npu-pod-lint:
	$(MAKE) -C verification/npu/pod lint

npu-pod-synth:
	$(MAKE) -C verification/npu/pod synth

npu-pod-sim:
	$(MAKE) -C verification/npu/pod sim

npu-pod-test:
	$(MAKE) -C verification/npu/pod test

npu-pod-noc-test:
	$(MAKE) -C verification/npu/pod test-noc

npu-pod-array-lint:
	$(MAKE) -C verification/npu/pod lint-array

npu-pod-closure:
	$(MAKE) -C verification/npu/pod closure

npu-command-lint:
	$(MAKE) -C verification/npu/command lint

npu-command-synth:
	$(MAKE) -C verification/npu/command synth

npu-command-sim:
	$(MAKE) -C verification/npu/command sim

npu-command-test:
	$(MAKE) -C verification/npu/command test

npu-noc-lint:
	$(MAKE) -C verification/npu/noc lint

npu-noc-synth:
	$(MAKE) -C verification/npu/noc synth

npu-noc-formal:
	$(MAKE) -C verification/npu/noc formal

npu-noc-formal-deep:
	$(MAKE) -C verification/npu/noc formal-deep

npu-noc-sim:
	$(MAKE) -C verification/npu/noc sim

npu-noc-vip:
	$(MAKE) -C verification/npu/noc sim-vip

npu-noc-coverage:
	$(MAKE) -C verification/npu/noc coverage

npu-noc-test:
	$(MAKE) -C verification/npu/noc test

npu-noc-closure:
	$(MAKE) -C verification/npu/noc closure

# Complete reproducible gate for the RTL owned by the NPU workstream. Physical
# STA and cross-owner NoC/system integration remain separate because they need
# selected technology files and externally frozen clock/router contracts.
npu-owned-rtl-test:
	$(MAKE) -C verification/npu/compute lint references sim sim-peak
	$(MAKE) -C verification/npu/system test
	$(MAKE) -C verification/npu/command test
	$(MAKE) -C verification/npu/pod closure

# Compatibility aliases for existing automation. New integrations should use
# the npu-compute-* names above, which match the split source hierarchy.
npu-gemm-vector-lint: npu-compute-lint
npu-gemm-vector-sim: npu-compute-sim
npu-gemm-vector-test: npu-compute-test
npu-gemm-vector-waves: npu-compute-waves
