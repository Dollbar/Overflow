VERILATOR ?= /home/ljy/software/verilator/bin/verilator
PYTHON ?= python3
GTKWAVE ?= gtkwave
JOBS ?= 4

THIS_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(THIS_DIR)/../../..)
RTL_DIR := $(REPO_ROOT)/rtl/npu/gemm_vector
PKG_DIR := $(THIS_DIR)/pkg
VIP_DIR := $(THIS_DIR)/vip
MODEL_DIR := $(THIS_DIR)/models
TB_DIR := $(THIS_DIR)/tb
BUILD_DIR := $(THIS_DIR)/build
VERILATOR_DIR := $(BUILD_DIR)/verilator
REFERENCE_DIR := $(BUILD_DIR)/reference
WAVE_DIR := $(BUILD_DIR)/waves

COMMON_FLAGS := --language 1800-2017 -Wall --timing

RTL_PACKAGES := \
	$(RTL_DIR)/fp8_pkg.sv \
	$(RTL_DIR)/vector_pkg.sv \
	$(RTL_DIR)/npu_scheduler_pkg.sv

SCHEDULER_RTL := \
	$(RTL_PACKAGES) \
	$(RTL_DIR)/npu_scheduler_fifo.sv \
	$(RTL_DIR)/npu_input_scheduler.sv

VECTOR_RTL := \
	$(RTL_DIR)/fp8_pkg.sv \
	$(RTL_DIR)/vector_pkg.sv \
	$(RTL_DIR)/fp32_unpack.sv \
	$(RTL_DIR)/fp32_subnormal_normalize.sv \
	$(RTL_DIR)/fp32_significand_add.sv \
	$(RTL_DIR)/fp32_normalize.sv \
	$(RTL_DIR)/fp32_round_pack.sv \
	$(RTL_DIR)/fp32_add_pipeline.sv \
	$(RTL_DIR)/kogge_stone_adder_48.sv \
	$(RTL_DIR)/fp32_mul_round_prepare.sv \
	$(RTL_DIR)/fp32_mul_round_pack.sv \
	$(RTL_DIR)/fp32_mul_pipeline.sv \
	$(RTL_DIR)/fp32_compare.sv \
	$(RTL_DIR)/fp32_to_fp8.sv \
	$(RTL_DIR)/fp32_exp_mul_u19_u4.sv \
	$(RTL_DIR)/fp32_exp_approx.sv \
	$(RTL_DIR)/fp32_recip_pipeline.sv \
	$(RTL_DIR)/fp32_rsqrt_pipeline.sv \
	$(RTL_DIR)/fp32_add_one_pipeline.sv \
	$(RTL_DIR)/fp32_sigmoid_pipeline.sv \
	$(RTL_DIR)/vector_alu16.sv \
	$(RTL_DIR)/gemm_epilogue16.sv \
	$(RTL_DIR)/vector_reduce16.sv \
	$(RTL_DIR)/vector_softmax_max_broadcast_slice.sv \
	$(RTL_DIR)/vector_softmax_recip_broadcast_slice.sv \
	$(RTL_DIR)/vector_softmax16.sv \
	$(RTL_DIR)/vector_norm_broadcast_slice.sv \
	$(RTL_DIR)/vector_norm16.sv \
	$(RTL_DIR)/vector_gelu16.sv \
	$(RTL_DIR)/vector_silu16.sv \
	$(RTL_DIR)/vector_engine_result_fifo.sv \
	$(RTL_DIR)/vector_engine16.sv

DESCRIPTOR_RTL := \
	$(RTL_PACKAGES) \
	$(PKG_DIR)/npu_gemm_vector_tb_pkg.sv \
	$(VIP_DIR)/npu_descriptor_source_vip.sv \
	$(VIP_DIR)/npu_post_result_sink_vip.sv \
	$(RTL_DIR)/npu_descriptor_buffer.sv

SRAM_MODEL := $(MODEL_DIR)/sram_macro_model.sv

SCHEDULER_TOP := tb_npu_input_scheduler
VECTOR_TOP := tb_vector_engine16
DESCRIPTOR_TOP := tb_descriptor_path
SRAM_TOP := tb_sram_macro_contract

SCHEDULER_BIN := $(VERILATOR_DIR)/scheduler-sim/V$(SCHEDULER_TOP)
VECTOR_BIN := $(VERILATOR_DIR)/vector-sim/V$(VECTOR_TOP)
DESCRIPTOR_BIN := $(VERILATOR_DIR)/descriptor-sim/V$(DESCRIPTOR_TOP)
SRAM_BIN := $(VERILATOR_DIR)/sram-sim/V$(SRAM_TOP)
SCHEDULER_WAVE_BIN := $(VERILATOR_DIR)/scheduler-waves/V$(SCHEDULER_TOP)
VECTOR_WAVE_BIN := $(VERILATOR_DIR)/vector-waves/V$(VECTOR_TOP)
DESCRIPTOR_WAVE_BIN := $(VERILATOR_DIR)/descriptor-waves/V$(DESCRIPTOR_TOP)
SRAM_WAVE_BIN := $(VERILATOR_DIR)/sram-waves/V$(SRAM_TOP)

SCHEDULER_SOURCES := $(SCHEDULER_RTL) $(TB_DIR)/tb_npu_input_scheduler.sv
VECTOR_SOURCES := $(VECTOR_RTL) $(TB_DIR)/tb_vector_engine16.sv
DESCRIPTOR_SOURCES := $(DESCRIPTOR_RTL) $(TB_DIR)/tb_descriptor_path.sv
SRAM_SOURCES := $(SRAM_MODEL) $(TB_DIR)/tb_sram_macro_contract.sv

.PHONY: help lint lint-scheduler lint-vector lint-descriptor lint-sram \
	sim sim-scheduler sim-vector sim-descriptor sim-sram test references \
	waves waves-scheduler waves-vector waves-descriptor waves-sram \
	view-waves clean

help:
	@echo "GEMM/vector verification targets:"
	@echo "  make lint        - run zero-warning Verilator lint for all environments"
	@echo "  make sim         - build and run all deterministic self-checking tests"
	@echo "  make test        - run lint, reference generation, and RTL regressions"
	@echo "  make waves       - rerun tests and write VCD files below build/waves"
	@echo "  make view-waves WAVE=descriptor_path - open one VCD with GTKWave"
	@echo "  make references  - regenerate deterministic Python reference vectors"
	@echo "  make clean       - remove generated build output"

lint: lint-scheduler lint-vector lint-descriptor lint-sram

lint-scheduler:
	mkdir -p $(VERILATOR_DIR)/scheduler-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(SCHEDULER_TOP) \
		--Mdir $(VERILATOR_DIR)/scheduler-lint $(SCHEDULER_SOURCES)

lint-vector:
	mkdir -p $(VERILATOR_DIR)/vector-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(VECTOR_TOP) \
		--Mdir $(VERILATOR_DIR)/vector-lint $(VECTOR_SOURCES)

lint-descriptor:
	mkdir -p $(VERILATOR_DIR)/descriptor-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(DESCRIPTOR_TOP) \
		--Mdir $(VERILATOR_DIR)/descriptor-lint $(DESCRIPTOR_SOURCES)

lint-sram:
	mkdir -p $(VERILATOR_DIR)/sram-lint
	$(VERILATOR) --lint-only $(COMMON_FLAGS) --top-module $(SRAM_TOP) \
		--Mdir $(VERILATOR_DIR)/sram-lint $(SRAM_SOURCES)

sim: sim-scheduler sim-vector sim-descriptor sim-sram

$(SCHEDULER_BIN): $(SCHEDULER_SOURCES)
	mkdir -p $(VERILATOR_DIR)/scheduler-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) -j $(JOBS) \
		--top-module $(SCHEDULER_TOP) --Mdir $(VERILATOR_DIR)/scheduler-sim \
		$(SCHEDULER_SOURCES)

sim-scheduler: $(SCHEDULER_BIN)
	cd $(THIS_DIR) && $(VERILATOR_DIR)/scheduler-sim/V$(SCHEDULER_TOP)

$(VECTOR_BIN): $(VECTOR_SOURCES)
	mkdir -p $(VERILATOR_DIR)/vector-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) -j $(JOBS) \
		--top-module $(VECTOR_TOP) --Mdir $(VERILATOR_DIR)/vector-sim \
		$(VECTOR_SOURCES)

sim-vector: $(VECTOR_BIN)
	cd $(THIS_DIR) && $(VERILATOR_DIR)/vector-sim/V$(VECTOR_TOP)

$(DESCRIPTOR_BIN): $(DESCRIPTOR_SOURCES)
	mkdir -p $(VERILATOR_DIR)/descriptor-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) -j $(JOBS) \
		--top-module $(DESCRIPTOR_TOP) --Mdir $(VERILATOR_DIR)/descriptor-sim \
		$(DESCRIPTOR_SOURCES)

sim-descriptor: $(DESCRIPTOR_BIN)
	cd $(THIS_DIR) && $(VERILATOR_DIR)/descriptor-sim/V$(DESCRIPTOR_TOP)

$(SRAM_BIN): $(SRAM_SOURCES)
	mkdir -p $(VERILATOR_DIR)/sram-sim $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) -j $(JOBS) \
		--top-module $(SRAM_TOP) --Mdir $(VERILATOR_DIR)/sram-sim \
		$(SRAM_SOURCES)

sim-sram: $(SRAM_BIN)
	cd $(THIS_DIR) && $(VERILATOR_DIR)/sram-sim/V$(SRAM_TOP)

references:
	mkdir -p $(REFERENCE_DIR)
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) $(MODEL_DIR)/vector_fp_reference.py \
		--mul-output $(REFERENCE_DIR)/fp32_mul.hex \
		--compare-output $(REFERENCE_DIR)/fp32_compare.hex \
		--fp8-to-fp32-output $(REFERENCE_DIR)/fp8_to_fp32.hex \
		--fp32-to-fp8-output $(REFERENCE_DIR)/fp32_to_fp8.hex --count 128
	PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=$(MODEL_DIR) $(PYTHON) $(MODEL_DIR)/vector_softmax16_reference.py \
		--output $(REFERENCE_DIR)/vector_softmax16.hex --count 64
	PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=$(MODEL_DIR) $(PYTHON) $(MODEL_DIR)/vector_norm16_reference.py \
		--output $(REFERENCE_DIR)/vector_norm16.hex --count 64
	PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=$(MODEL_DIR) $(PYTHON) $(MODEL_DIR)/vector_gelu16_reference.py \
		--output $(REFERENCE_DIR)/vector_gelu16.hex --count 64
	PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=$(MODEL_DIR) $(PYTHON) $(MODEL_DIR)/vector_silu16_reference.py \
		--output $(REFERENCE_DIR)/vector_silu16.hex --count 64

test: lint references sim

$(SCHEDULER_WAVE_BIN): $(SCHEDULER_SOURCES)
	mkdir -p $(VERILATOR_DIR)/scheduler-waves $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) --trace -DTRACE -j $(JOBS) \
		--top-module $(SCHEDULER_TOP) --Mdir $(VERILATOR_DIR)/scheduler-waves \
		$(SCHEDULER_SOURCES)

$(VECTOR_WAVE_BIN): $(VECTOR_SOURCES)
	mkdir -p $(VERILATOR_DIR)/vector-waves $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) --trace -DTRACE -j $(JOBS) \
		--top-module $(VECTOR_TOP) --Mdir $(VERILATOR_DIR)/vector-waves \
		$(VECTOR_SOURCES)

$(DESCRIPTOR_WAVE_BIN): $(DESCRIPTOR_SOURCES)
	mkdir -p $(VERILATOR_DIR)/descriptor-waves $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) --trace -DTRACE -j $(JOBS) \
		--top-module $(DESCRIPTOR_TOP) --Mdir $(VERILATOR_DIR)/descriptor-waves \
		$(DESCRIPTOR_SOURCES)

$(SRAM_WAVE_BIN): $(SRAM_SOURCES)
	mkdir -p $(VERILATOR_DIR)/sram-waves $(WAVE_DIR)
	$(VERILATOR) --binary $(COMMON_FLAGS) --trace -DTRACE -j $(JOBS) \
		--top-module $(SRAM_TOP) --Mdir $(VERILATOR_DIR)/sram-waves \
		$(SRAM_SOURCES)

waves-scheduler: $(SCHEDULER_WAVE_BIN)
	cd $(THIS_DIR) && $(SCHEDULER_WAVE_BIN)

waves-vector: $(VECTOR_WAVE_BIN)
	cd $(THIS_DIR) && $(VECTOR_WAVE_BIN)

waves-descriptor: $(DESCRIPTOR_WAVE_BIN)
	cd $(THIS_DIR) && $(DESCRIPTOR_WAVE_BIN)

waves-sram: $(SRAM_WAVE_BIN)
	cd $(THIS_DIR) && $(SRAM_WAVE_BIN)

waves: waves-scheduler waves-vector waves-descriptor waves-sram

WAVE ?= descriptor_path
view-waves:
	$(GTKWAVE) $(WAVE_DIR)/$(WAVE).vcd $(THIS_DIR)/waves/$(WAVE).gtkw

clean:
	rm -rf $(BUILD_DIR)
