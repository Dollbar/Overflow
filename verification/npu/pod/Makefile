VERILATOR ?= verilator
VERILATOR_COVERAGE ?= verilator_coverage
YOSYS ?= yosys
PYTHON ?= python3
JOBS ?= 4
ARRAY_SEEDS ?= 00000001 52a731c9 deadbeef c001d00d
COVERAGE_MIN_LINE ?= 96.0
COVERAGE_MIN_BRANCH ?= 56.0
COVERAGE_MIN_EXPR ?= 77.0
COVERAGE_MIN_TOGGLE ?= 12.5
COVERAGE_MIN_FSM_STATE ?= 100.0
COVERAGE_MIN_USER ?= 25.0

THIS_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(THIS_DIR)/../../..)
BUILD_DIR := $(THIS_DIR)/build
FLAGS := --language 1800-2017 -Wall -Wno-DECLFILENAME --timing

NPU_RTL_DIR := $(REPO_ROOT)/rtl/npu
COMMON_RTL_DIR := $(NPU_RTL_DIR)/common
TENSOR_RTL_DIR := $(NPU_RTL_DIR)/tensor
VECTOR_RTL_DIR := $(NPU_RTL_DIR)/vector
SCHEDULER_RTL_DIR := $(NPU_RTL_DIR)/scheduler
SRAM_RTL_DIR := $(NPU_RTL_DIR)/sram
COMPUTE_RTL_DIR := $(NPU_RTL_DIR)/compute
DMA_RTL_DIR := $(NPU_RTL_DIR)/dma
POD_RTL_DIR := $(NPU_RTL_DIR)/pod
COMMAND_RTL_DIR := $(NPU_RTL_DIR)/command

COMPUTE_PACKAGES := \
	$(COMMON_RTL_DIR)/fp8_pkg.sv \
	$(COMMON_RTL_DIR)/mxfp_pkg.sv \
	$(VECTOR_RTL_DIR)/vector_pkg.sv \
	$(SCHEDULER_RTL_DIR)/npu_scheduler_pkg.sv
POD_PACKAGES := $(COMPUTE_PACKAGES) \
	$(DMA_RTL_DIR)/npu_dma_pkg.sv \
	$(POD_RTL_DIR)/npu_pod_pkg.sv \
	$(COMMAND_RTL_DIR)/npu_command_pkg.sv

COMMAND_BODY_RTL := $(COMMAND_RTL_DIR)/npu_pod_command_gateway.sv
MANAGED_POD_RTL := $(POD_RTL_DIR)/npu_managed_compute_pod.sv
POD_ARRAY_RTL := $(NPU_RTL_DIR)/npu_2x4_pod_array.sv

DMA_BODY_RTL := \
	$(DMA_RTL_DIR)/npu_dma_command_queue.sv \
	$(DMA_RTL_DIR)/npu_dma_address_generator.sv \
	$(DMA_RTL_DIR)/npu_dma_tag_metadata_bank.sv \
	$(DMA_RTL_DIR)/npu_dma_channel_mover.sv \
	$(DMA_RTL_DIR)/npu_dma_hbm_control_buffer.sv \
	$(DMA_RTL_DIR)/npu_dma_hbm_wide_control_buffer.sv \
	$(DMA_RTL_DIR)/npu_dma_carry_select_block.sv \
	$(DMA_RTL_DIR)/npu_dma_carry_select_adder.sv \
	$(DMA_RTL_DIR)/npu_dma_hbm_rank_count16.sv \
	$(DMA_RTL_DIR)/npu_dma_hbm_request_slot.sv \
	$(DMA_RTL_DIR)/npu_dma_hbm_response_channel.sv \
	$(DMA_RTL_DIR)/npu_dma_priority_encoder256.sv \
	$(DMA_RTL_DIR)/npu_dma_local_tag_allocator.sv \
	$(DMA_RTL_DIR)/npu_dma_hbm_egress.sv \
	$(DMA_RTL_DIR)/npu_dma_hbm_response_router.sv \
	$(DMA_RTL_DIR)/npu_dma_hbm_tag_tracker.sv \
	$(DMA_RTL_DIR)/npu_dma_hbm_status_monitor.sv \
	$(DMA_RTL_DIR)/npu_dma_hbm_boundary.sv \
	$(DMA_RTL_DIR)/npu_dma_engine.sv

POD_BODY_RTL := \
	$(POD_RTL_DIR)/npu_pod_scoreboard.sv \
	$(POD_RTL_DIR)/npu_pod_local_loader.sv \
	$(POD_RTL_DIR)/npu_pod_sram_read_mux.sv \
	$(POD_RTL_DIR)/npu_compute_pod.sv

SHARED_SRAM_RTL := \
	$(REPO_ROOT)/Library/models/kd28/sram/rtl/kd28_sram_sdp_model.v \
	$(REPO_ROOT)/Library/models/kd28/sram/rtl/kd28_sram_cells.v \
	$(REPO_ROOT)/Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v \
	$(SRAM_RTL_DIR)/npu_round_robin_arbiter16.sv \
	$(SRAM_RTL_DIR)/npu_pod_shared_sram.sv

COMPUTE_SEARCH_DIRS := $(COMMON_RTL_DIR) $(TENSOR_RTL_DIR) \
	$(VECTOR_RTL_DIR) $(SCHEDULER_RTL_DIR) $(SRAM_RTL_DIR) \
	$(COMPUTE_RTL_DIR)
COMPUTE_ALL_RTL := $(sort $(foreach dir,$(COMPUTE_SEARCH_DIRS), \
	$(wildcard $(dir)/*.sv) $(wildcard $(dir)/*.v)))
COMPUTE_LINT_BODY := $(filter-out $(COMPUTE_PACKAGES) \
	$(SRAM_RTL_DIR)/kd28_npu_sram_adapter.sv \
	$(SRAM_RTL_DIR)/npu_pod_shared_sram.sv \
	$(SRAM_RTL_DIR)/npu_round_robin_arbiter16.sv \
	$(TENSOR_RTL_DIR)/TILE_FP8_16_FIFO.sv,$(COMPUTE_ALL_RTL))
COMPUTE_TILE_STUB := \
	$(REPO_ROOT)/verification/npu/compute/models/TILE_FP8_16_FIFO_lint_stub.sv

COMPUTE_STUB := $(THIS_DIR)/models/npu_square_gemm_system_stub.sv
SHARED_SRAM_STUB := $(THIS_DIR)/models/npu_pod_shared_sram_stub.sv
FULL_POD_STUB_RTL := $(POD_PACKAGES) $(DMA_BODY_RTL) $(COMMAND_BODY_RTL) \
	$(SHARED_SRAM_STUB) $(filter-out $(POD_RTL_DIR)/npu_compute_pod.sv, \
	$(POD_BODY_RTL)) $(COMPUTE_STUB) $(POD_RTL_DIR)/npu_compute_pod.sv \
	$(MANAGED_POD_RTL)
FULL_POD_REAL_RTL := $(POD_PACKAGES) $(COMPUTE_LINT_BODY) \
	$(COMPUTE_TILE_STUB) $(DMA_BODY_RTL) $(COMMAND_BODY_RTL) \
	$(SHARED_SRAM_RTL) $(POD_BODY_RTL) $(MANAGED_POD_RTL)

SCOREBOARD_RTL := $(REPO_ROOT)/rtl/npu/pod/npu_pod_scoreboard.sv
SCOREBOARD_TB := $(THIS_DIR)/tb/tb_npu_pod_scoreboard.sv
SCOREBOARD_TOP := tb_npu_pod_scoreboard
SCOREBOARD_SIM_DIR := $(BUILD_DIR)/verilator/$(SCOREBOARD_TOP)
SCOREBOARD_SIM_BIN := $(SCOREBOARD_SIM_DIR)/V$(SCOREBOARD_TOP)

LOADER_RTL := \
	$(REPO_ROOT)/rtl/npu/pod/npu_pod_pkg.sv \
	$(REPO_ROOT)/rtl/npu/pod/npu_pod_local_loader.sv
LOADER_TB := $(THIS_DIR)/tb/tb_npu_pod_local_loader.sv
LOADER_TOP := tb_npu_pod_local_loader
LOADER_SIM_DIR := $(BUILD_DIR)/verilator/$(LOADER_TOP)
LOADER_SIM_BIN := $(LOADER_SIM_DIR)/V$(LOADER_TOP)

MUX_RTL := $(REPO_ROOT)/rtl/npu/pod/npu_pod_sram_read_mux.sv
MUX_TB := $(THIS_DIR)/tb/tb_npu_pod_sram_read_mux.sv
MUX_TOP := tb_npu_pod_sram_read_mux
MUX_SIM_DIR := $(BUILD_DIR)/verilator/$(MUX_TOP)
MUX_SIM_BIN := $(MUX_SIM_DIR)/V$(MUX_TOP)

NOC_RTL := \
	$(POD_RTL_DIR)/npu_pod_noc_pkg.sv \
	$(POD_RTL_DIR)/npu_pod_noc_link_slice.sv \
	$(POD_RTL_DIR)/npu_pod_noc_attachment.sv
ARRAY_STUB_RTL := $(FULL_POD_STUB_RTL) $(NOC_RTL) $(POD_ARRAY_RTL)
PROTOCOL_CHECKER := \
	$(REPO_ROOT)/verification/npu/common/vip/npu_ready_valid_protocol_checker.sv
POD_ARRAY_TB_PKG := $(THIS_DIR)/pkg/npu_pod_array_tb_pkg.sv
HBM_RESPONDER_VIP := $(THIS_DIR)/vip/npu_hbm_partition_responder_vip.sv
ARRAY_TB := $(THIS_DIR)/tb/tb_npu_2x4_pod_array.sv
ARRAY_TOP := tb_npu_2x4_pod_array
ARRAY_SIM_SOURCES := $(ARRAY_STUB_RTL) $(POD_ARRAY_TB_PKG) \
	$(PROTOCOL_CHECKER) $(HBM_RESPONDER_VIP) $(ARRAY_TB)
ARRAY_SIM_DIR := $(BUILD_DIR)/verilator/$(ARRAY_TOP)
ARRAY_SIM_BIN := $(ARRAY_SIM_DIR)/V$(ARRAY_TOP)
ARRAY_COVERAGE_DIR := $(BUILD_DIR)/coverage/$(ARRAY_TOP)
ARRAY_COVERAGE_BIN := $(ARRAY_COVERAGE_DIR)/V$(ARRAY_TOP)
ARRAY_COVERAGE_DATA := $(ARRAY_COVERAGE_DIR)/coverage.dat
ARRAY_COVERAGE_SUMMARY := $(ARRAY_COVERAGE_DIR)/coverage-summary.txt
COVERAGE_CHECKER := \
	$(REPO_ROOT)/verification/npu/common/scripts/check_verilator_coverage.py
NOC_TB := $(THIS_DIR)/tb/tb_npu_pod_noc_attachment.sv
NOC_TOP := tb_npu_pod_noc_attachment
NOC_SIM_DIR := $(BUILD_DIR)/verilator/$(NOC_TOP)
NOC_SIM_BIN := $(NOC_SIM_DIR)/V$(NOC_TOP)

FULL_POD_TB := $(THIS_DIR)/tb/tb_npu_compute_pod.sv
FULL_POD_TOP := tb_npu_compute_pod
FULL_POD_SIM_DIR := $(BUILD_DIR)/verilator/$(FULL_POD_TOP)
FULL_POD_SIM_BIN := $(FULL_POD_SIM_DIR)/V$(FULL_POD_TOP)
MANAGED_POD_TB := $(THIS_DIR)/tb/tb_npu_managed_compute_pod.sv
MANAGED_POD_TOP := tb_npu_managed_compute_pod
MANAGED_POD_SIM_DIR := $(BUILD_DIR)/verilator/$(MANAGED_POD_TOP)
MANAGED_POD_SIM_BIN := $(MANAGED_POD_SIM_DIR)/V$(MANAGED_POD_TOP)

.PHONY: preflight lint lint-scoreboard lint-loader lint-mux lint-noc lint-full \
	lint-full-real lint-managed lint-array lint-array-tb synth \
	synth-scoreboard synth-loader synth-mux synth-noc sim sim-scoreboard \
	sim-loader sim-mux sim-noc sim-full sim-managed sim-array \
	sim-array-multiseed coverage-array \
	test closure test-noc clean

preflight:
	@command -v "$(VERILATOR)" >/dev/null || { \
		echo "ERROR: VERILATOR='$(VERILATOR)' is not executable or not on PATH" >&2; exit 2; }
	@command -v "$(VERILATOR_COVERAGE)" >/dev/null || { \
		echo "ERROR: VERILATOR_COVERAGE='$(VERILATOR_COVERAGE)' is not executable or not on PATH" >&2; exit 2; }
	@command -v "$(YOSYS)" >/dev/null || { \
		echo "ERROR: YOSYS='$(YOSYS)' is not executable or not on PATH" >&2; exit 2; }
	@command -v "$(PYTHON)" >/dev/null || { \
		echo "ERROR: PYTHON='$(PYTHON)' is not executable or not on PATH" >&2; exit 2; }
	@command -v g++ >/dev/null || { \
		echo "ERROR: g++ is required by the Verilator binary build" >&2; exit 2; }
	@command -v tee >/dev/null || { \
		echo "ERROR: tee is required by the coverage report gate" >&2; exit 2; }
	@$(PYTHON) -c 'import sys; assert sys.version_info >= (3, 9), "Python 3.9 or newer is required"'
	@$(VERILATOR) --version
	@$(YOSYS) -V
	@$(PYTHON) --version

lint: lint-scoreboard lint-loader lint-mux lint-noc lint-full lint-full-real \
	lint-managed lint-array lint-array-tb

lint-scoreboard:
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(SCOREBOARD_TOP) \
		$(SCOREBOARD_RTL) $(SCOREBOARD_TB)

lint-loader:
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(LOADER_TOP) \
		$(LOADER_RTL) $(LOADER_TB)

lint-mux:
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(MUX_TOP) \
		$(MUX_RTL) $(MUX_TB)

lint-noc:
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(NOC_TOP) \
		$(NOC_RTL) $(NOC_TB)

lint-full:
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(FULL_POD_TOP) \
		--Mdir $(BUILD_DIR)/verilator/full-pod-lint \
		$(FULL_POD_STUB_RTL) $(FULL_POD_TB)

lint-full-real:
	$(VERILATOR) $(FLAGS) --lint-only --top-module npu_compute_pod \
		-GARRAY_DIM=2 --Mdir $(BUILD_DIR)/verilator/full-pod-real-lint \
		$(FULL_POD_REAL_RTL)

lint-managed:
	$(VERILATOR) $(FLAGS) --lint-only --top-module npu_managed_compute_pod \
		-GARRAY_DIM=2 --Mdir $(BUILD_DIR)/verilator/managed-pod-lint \
		$(FULL_POD_STUB_RTL)

lint-array:
	$(VERILATOR) $(FLAGS) --lint-only --top-module npu_2x4_pod_array \
		-GARRAY_DIM=2 \
		--Mdir $(BUILD_DIR)/verilator/pod-array-lint $(ARRAY_STUB_RTL)

lint-array-tb:
	$(VERILATOR) $(FLAGS) --assert --lint-only --top-module $(ARRAY_TOP) \
		--Mdir $(BUILD_DIR)/verilator/pod-array-tb-lint \
		$(ARRAY_SIM_SOURCES)

synth: synth-scoreboard synth-loader synth-mux synth-noc

synth-scoreboard:
	$(YOSYS) -q -p 'read_verilog -sv $(SCOREBOARD_RTL); hierarchy -top npu_pod_scoreboard; proc; opt; check; stat'

synth-loader:
	$(YOSYS) -q -p 'read_verilog -sv $(LOADER_RTL); hierarchy -top npu_pod_local_loader; proc; opt; check; stat'

synth-mux:
	$(YOSYS) -q -p 'read_verilog -sv $(MUX_RTL); hierarchy -top npu_pod_sram_read_mux; proc; opt; check; stat'

synth-noc:
	$(YOSYS) -q -p 'read_verilog -sv $(NOC_RTL); hierarchy -top npu_pod_noc_attachment; proc; opt; check; stat'

$(SCOREBOARD_SIM_BIN): $(SCOREBOARD_RTL) $(SCOREBOARD_TB)
	@mkdir -p $(SCOREBOARD_SIM_DIR)
	$(VERILATOR) $(FLAGS) --binary --top-module $(SCOREBOARD_TOP) \
		--Mdir $(SCOREBOARD_SIM_DIR) $(SCOREBOARD_RTL) $(SCOREBOARD_TB)

$(LOADER_SIM_BIN): $(LOADER_RTL) $(LOADER_TB)
	@mkdir -p $(LOADER_SIM_DIR)
	$(VERILATOR) $(FLAGS) --binary --top-module $(LOADER_TOP) \
		--Mdir $(LOADER_SIM_DIR) $(LOADER_RTL) $(LOADER_TB)

$(MUX_SIM_BIN): $(MUX_RTL) $(MUX_TB)
	@mkdir -p $(MUX_SIM_DIR)
	$(VERILATOR) $(FLAGS) --binary --top-module $(MUX_TOP) \
		--Mdir $(MUX_SIM_DIR) $(MUX_RTL) $(MUX_TB)

$(NOC_SIM_BIN): $(NOC_RTL) $(NOC_TB)
	@mkdir -p $(NOC_SIM_DIR)
	$(VERILATOR) $(FLAGS) --binary --top-module $(NOC_TOP) \
		--Mdir $(NOC_SIM_DIR) $(NOC_RTL) $(NOC_TB)

$(FULL_POD_SIM_BIN): $(FULL_POD_STUB_RTL) $(FULL_POD_TB)
	@mkdir -p $(FULL_POD_SIM_DIR)
	$(VERILATOR) $(FLAGS) --binary --top-module $(FULL_POD_TOP) \
		--output-split 20000 --output-split-cfuncs 500 \
		--Mdir $(FULL_POD_SIM_DIR) $(FULL_POD_STUB_RTL) $(FULL_POD_TB)

$(MANAGED_POD_SIM_BIN): $(FULL_POD_STUB_RTL) $(MANAGED_POD_TB)
	@mkdir -p $(MANAGED_POD_SIM_DIR)
	$(VERILATOR) $(FLAGS) --binary -j $(JOBS) --top-module $(MANAGED_POD_TOP) \
		--output-split 20000 --output-split-cfuncs 500 \
		--Mdir $(MANAGED_POD_SIM_DIR) $(FULL_POD_STUB_RTL) $(MANAGED_POD_TB)

$(ARRAY_SIM_BIN): $(ARRAY_SIM_SOURCES)
	@mkdir -p $(ARRAY_SIM_DIR)
	$(VERILATOR) $(FLAGS) --assert --binary -j $(JOBS) \
		--top-module $(ARRAY_TOP) --output-split 20000 \
		--output-split-cfuncs 500 --Mdir $(ARRAY_SIM_DIR) \
		$(ARRAY_SIM_SOURCES)

$(ARRAY_COVERAGE_BIN): $(ARRAY_SIM_SOURCES)
	@mkdir -p $(ARRAY_COVERAGE_DIR)
	$(VERILATOR) $(FLAGS) -Wno-UNOPTFLAT --assert --binary -j $(JOBS) \
		--coverage-line --coverage-expr --coverage-fsm --coverage-toggle \
		--coverage-user --coverage-per-instance --coverage-max-width 256 \
		--top-module $(ARRAY_TOP) --output-split 20000 \
		--output-split-cfuncs 500 --Mdir $(ARRAY_COVERAGE_DIR) \
		$(ARRAY_SIM_SOURCES)

sim: sim-scoreboard sim-loader sim-mux sim-noc sim-full sim-managed sim-array

sim-scoreboard: $(SCOREBOARD_SIM_BIN)
	$(SCOREBOARD_SIM_BIN)

sim-loader: $(LOADER_SIM_BIN)
	$(LOADER_SIM_BIN)

sim-mux: $(MUX_SIM_BIN)
	$(MUX_SIM_BIN)

sim-noc: $(NOC_SIM_BIN)
	$(NOC_SIM_BIN)

sim-full: $(FULL_POD_SIM_BIN)
	$(FULL_POD_SIM_BIN)

sim-managed: $(MANAGED_POD_SIM_BIN)
	$(MANAGED_POD_SIM_BIN)

sim-array: $(ARRAY_SIM_BIN)
	$(ARRAY_SIM_BIN)

sim-array-multiseed: $(ARRAY_SIM_BIN)
	@set -e; for seed in $(ARRAY_SEEDS); do \
		echo "[RTL_SIM] npu_2x4_pod_array SEED=$$seed"; \
		$(ARRAY_SIM_BIN) +SEED=$$seed; \
	done

coverage-array: $(ARRAY_COVERAGE_BIN)
	cd $(ARRAY_COVERAGE_DIR) && ./V$(ARRAY_TOP)
	test -s $(ARRAY_COVERAGE_DATA)
	$(VERILATOR_COVERAGE) --report summary $(ARRAY_COVERAGE_DATA) | \
		tee $(ARRAY_COVERAGE_SUMMARY)
	$(PYTHON) $(COVERAGE_CHECKER) $(ARRAY_COVERAGE_SUMMARY) \
		--minimum line=$(COVERAGE_MIN_LINE) \
		--minimum branch=$(COVERAGE_MIN_BRANCH) \
		--minimum expr=$(COVERAGE_MIN_EXPR) \
		--minimum toggle=$(COVERAGE_MIN_TOGGLE) \
		--minimum fsm_state=$(COVERAGE_MIN_FSM_STATE) \
		--minimum user=$(COVERAGE_MIN_USER)

test: preflight lint synth sim

closure: test sim-array-multiseed coverage-array

test-noc: lint-noc synth-noc sim-noc

clean:
	rm -rf $(BUILD_DIR)
