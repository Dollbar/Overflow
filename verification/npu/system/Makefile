VERILATOR ?= verilator
YOSYS ?= yosys
OPENSTA ?= sta
LIBERTY ?=
OPENSTA_BIN := $(shell command -v $(OPENSTA) 2>/dev/null)
ifneq ($(OPENSTA_BIN),)
OPENSTA_LIBRARY_PATH ?= $(abspath $(dir $(OPENSTA_BIN))/../lib)
export LD_LIBRARY_PATH := $(OPENSTA_LIBRARY_PATH):$(LD_LIBRARY_PATH)
endif
CLOCK_PERIOD_NS ?= 1.000
CLOCK_UNCERTAINTY_NS ?= 0.030
INPUT_DELAY_NS ?= 0.050
OUTPUT_DELAY_NS ?= 0.050
OUTPUT_LOAD_PF ?= 0.005
ABC_DELAY_PS ?= 850
ALLOCATOR_ABC_DELAY_PS ?= 750
BOUNDARY_ABC_DELAY_PS ?= 750
ADDRGEN_ABC_DELAY_PS ?= 650
MOVER_ABC_DELAY_PS ?= 650
ABC_CONSTR ?= $(STA_DIR)/scripts/abc_generic.constr
DRIVING_CELL ?= BUFX1
DRIVING_PIN ?= Y
export DRIVING_CELL DRIVING_PIN
export ABC_CONSTR

THIS_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(THIS_DIR)/../../..)
BUILD_DIR := $(THIS_DIR)/build
EGRESS_RTL := \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_control_buffer.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_wide_control_buffer.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_carry_select_block.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_carry_select_adder.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_rank_count16.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_request_slot.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_egress.sv
EGRESS_TB := $(THIS_DIR)/tb/tb_npu_dma_hbm_egress.sv
EGRESS_TOP := tb_npu_dma_hbm_egress
EGRESS_SIM_DIR := $(BUILD_DIR)/verilator/$(EGRESS_TOP)
EGRESS_SIM_BIN := $(EGRESS_SIM_DIR)/V$(EGRESS_TOP)
RESPONSE_RTL := \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_control_buffer.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_wide_control_buffer.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_carry_select_block.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_carry_select_adder.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_response_channel.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_response_router.sv
RESPONSE_TB := $(THIS_DIR)/tb/tb_npu_dma_hbm_response_router.sv
RESPONSE_TOP := tb_npu_dma_hbm_response_router
RESPONSE_SIM_DIR := $(BUILD_DIR)/verilator/$(RESPONSE_TOP)
RESPONSE_SIM_BIN := $(RESPONSE_SIM_DIR)/V$(RESPONSE_TOP)
TRACKER_RTL := \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_control_buffer.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_rank_count16.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_tag_tracker.sv
TRACKER_TB := $(THIS_DIR)/tb/tb_npu_dma_hbm_tag_tracker.sv
TRACKER_TOP := tb_npu_dma_hbm_tag_tracker
TRACKER_SIM_DIR := $(BUILD_DIR)/verilator/$(TRACKER_TOP)
TRACKER_SIM_BIN := $(TRACKER_SIM_DIR)/V$(TRACKER_TOP)
ALLOCATOR_RTL := \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_control_buffer.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_priority_encoder256.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_local_tag_allocator.sv
ALLOCATOR_TB := $(THIS_DIR)/tb/tb_npu_dma_local_tag_allocator.sv
ALLOCATOR_TOP := tb_npu_dma_local_tag_allocator
ALLOCATOR_SIM_DIR := $(BUILD_DIR)/verilator/$(ALLOCATOR_TOP)
ALLOCATOR_SIM_BIN := $(ALLOCATOR_SIM_DIR)/V$(ALLOCATOR_TOP)
MONITOR_RTL := \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_carry_select_block.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_carry_select_adder.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_rank_count16.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_status_monitor.sv
MONITOR_TB := $(THIS_DIR)/tb/tb_npu_dma_hbm_status_monitor.sv
MONITOR_TOP := tb_npu_dma_hbm_status_monitor
MONITOR_SIM_DIR := $(BUILD_DIR)/verilator/$(MONITOR_TOP)
MONITOR_SIM_BIN := $(MONITOR_SIM_DIR)/V$(MONITOR_TOP)
BOUNDARY_RTL := \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_control_buffer.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_wide_control_buffer.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_carry_select_block.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_carry_select_adder.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_rank_count16.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_request_slot.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_response_channel.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_priority_encoder256.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_local_tag_allocator.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_egress.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_response_router.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_tag_tracker.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_status_monitor.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_boundary.sv
BOUNDARY_TB := $(THIS_DIR)/tb/tb_npu_dma_hbm_boundary.sv
BOUNDARY_TOP := tb_npu_dma_hbm_boundary
BOUNDARY_SIM_DIR := $(BUILD_DIR)/verilator/$(BOUNDARY_TOP)
BOUNDARY_SIM_BIN := $(BOUNDARY_SIM_DIR)/V$(BOUNDARY_TOP)
ADDRGEN_RTL := \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_pkg.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_carry_select_block.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_carry_select_adder.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_address_generator.sv
ADDRGEN_TB := $(THIS_DIR)/tb/tb_npu_dma_address_generator.sv
ADDRGEN_TOP := tb_npu_dma_address_generator
ADDRGEN_SIM_DIR := $(BUILD_DIR)/verilator/$(ADDRGEN_TOP)
ADDRGEN_SIM_BIN := $(ADDRGEN_SIM_DIR)/V$(ADDRGEN_TOP)
MOVER_RTL := \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_pkg.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_control_buffer.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_wide_control_buffer.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_carry_select_block.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_carry_select_adder.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_address_generator.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_tag_metadata_bank.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_channel_mover.sv
MOVER_TB := $(THIS_DIR)/tb/tb_npu_dma_channel_mover.sv
MOVER_TOP := tb_npu_dma_channel_mover
MOVER_SIM_DIR := $(BUILD_DIR)/verilator/$(MOVER_TOP)
MOVER_SIM_BIN := $(MOVER_SIM_DIR)/V$(MOVER_TOP)
ENGINE_RTL := \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_pkg.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_command_queue.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_address_generator.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_tag_metadata_bank.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_channel_mover.sv \
	$(BOUNDARY_RTL) \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_engine.sv
ENGINE_TB := $(THIS_DIR)/tb/tb_npu_dma_engine.sv
ENGINE_TOP := tb_npu_dma_engine
ENGINE_SIM_DIR := $(BUILD_DIR)/verilator/$(ENGINE_TOP)
ENGINE_SIM_BIN := $(ENGINE_SIM_DIR)/V$(ENGINE_TOP)
SHARED_SRAM_RTL := \
	$(REPO_ROOT)/Library/models/kd28/sram/rtl/kd28_sram_sdp_model.v \
	$(REPO_ROOT)/Library/models/kd28/sram/rtl/kd28_sram_cells.v \
	$(REPO_ROOT)/Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v \
	$(REPO_ROOT)/rtl/npu/sram/npu_round_robin_arbiter16.sv \
	$(REPO_ROOT)/rtl/npu/sram/npu_pod_shared_sram.sv
SHARED_SRAM_SYNTH_RTL := \
	$(REPO_ROOT)/Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v \
	$(REPO_ROOT)/rtl/npu/sram/npu_round_robin_arbiter16.sv \
	$(REPO_ROOT)/rtl/npu/sram/npu_pod_shared_sram.sv
SHARED_SRAM_BLACKBOX := \
	$(REPO_ROOT)/Library/models/kd28/sram/rtl/kd28_sram_blackboxes.v
SHARED_SRAM_TB := $(THIS_DIR)/tb/tb_npu_pod_shared_sram.sv
SHARED_SRAM_TOP := tb_npu_pod_shared_sram
SHARED_SRAM_SIM_DIR := $(BUILD_DIR)/verilator/$(SHARED_SRAM_TOP)
SHARED_SRAM_SIM_BIN := $(SHARED_SRAM_SIM_DIR)/V$(SHARED_SRAM_TOP)
POD_RTL := $(ENGINE_RTL) $(SHARED_SRAM_RTL) \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_pod.sv
POD_SYNTH_RTL := $(ENGINE_RTL) $(SHARED_SRAM_SYNTH_RTL) \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_pod.sv
POD_TB := $(THIS_DIR)/tb/tb_npu_dma_pod.sv
POD_TOP := tb_npu_dma_pod
POD_SIM_DIR := $(BUILD_DIR)/verilator/$(POD_TOP)
POD_SIM_BIN := $(POD_SIM_DIR)/V$(POD_TOP)
STA_DIR := $(THIS_DIR)/STA
STA_BUILD_DIR := $(BUILD_DIR)/sta
STA_SCRIPT := $(STA_DIR)/scripts/sta_generic.tcl
SYNTH_SCRIPT := $(STA_DIR)/scripts/synth_generic.tcl
CELL_MAP ?= $(STA_DIR)/scripts/generic_cells_map.v
EGRESS_NETLIST := $(STA_BUILD_DIR)/npu_dma_hbm_egress_mapped.v
EGRESS_JSON := $(STA_BUILD_DIR)/npu_dma_hbm_egress_mapped.json
EGRESS_SDC := $(STA_DIR)/sdc/npu_dma_hbm_egress_1ghz.sdc
RESPONSE_NETLIST := $(STA_BUILD_DIR)/npu_dma_hbm_response_router_mapped.v
RESPONSE_JSON := $(STA_BUILD_DIR)/npu_dma_hbm_response_router_mapped.json
RESPONSE_SDC := $(STA_DIR)/sdc/npu_dma_hbm_response_router_1ghz.sdc
TRACKER_NETLIST := $(STA_BUILD_DIR)/npu_dma_hbm_tag_tracker_mapped.v
TRACKER_JSON := $(STA_BUILD_DIR)/npu_dma_hbm_tag_tracker_mapped.json
TRACKER_SDC := $(STA_DIR)/sdc/npu_dma_hbm_tag_tracker_1ghz.sdc
ALLOCATOR_NETLIST := $(STA_BUILD_DIR)/npu_dma_local_tag_allocator_mapped.v
ALLOCATOR_JSON := $(STA_BUILD_DIR)/npu_dma_local_tag_allocator_mapped.json
ALLOCATOR_SDC := $(STA_DIR)/sdc/npu_dma_local_tag_allocator_1ghz.sdc
MONITOR_NETLIST := $(STA_BUILD_DIR)/npu_dma_hbm_status_monitor_mapped.v
MONITOR_JSON := $(STA_BUILD_DIR)/npu_dma_hbm_status_monitor_mapped.json
MONITOR_SDC := $(STA_DIR)/sdc/npu_dma_hbm_status_monitor_1ghz.sdc
BOUNDARY_NETLIST := $(STA_BUILD_DIR)/npu_dma_hbm_boundary_mapped.v
BOUNDARY_JSON := $(STA_BUILD_DIR)/npu_dma_hbm_boundary_mapped.json
BOUNDARY_SDC := $(STA_DIR)/sdc/npu_dma_hbm_boundary_1ghz.sdc
ADDRGEN_NETLIST := $(STA_BUILD_DIR)/npu_dma_address_generator_mapped.v
ADDRGEN_JSON := $(STA_BUILD_DIR)/npu_dma_address_generator_mapped.json
ADDRGEN_SDC := $(STA_DIR)/sdc/npu_dma_address_generator_1ghz.sdc
MOVER_NETLIST := $(STA_BUILD_DIR)/npu_dma_channel_mover_mapped.v
MOVER_JSON := $(STA_BUILD_DIR)/npu_dma_channel_mover_mapped.json
MOVER_SDC := $(STA_DIR)/sdc/npu_dma_channel_mover_1ghz.sdc
STA_NETLISTS := $(EGRESS_NETLIST) $(RESPONSE_NETLIST) $(TRACKER_NETLIST) \
	$(ALLOCATOR_NETLIST) $(MONITOR_NETLIST) $(BOUNDARY_NETLIST) \
	$(ADDRGEN_NETLIST) $(MOVER_NETLIST)
FLAGS := --language 1800-2017 -Wall --timing

.PHONY: lint lint-egress lint-response lint-tracker lint-allocator lint-monitor \
	lint-boundary synth-readiness synth-egress synth-response synth-tracker \
	synth-allocator synth-monitor synth-boundary sim sim-egress sim-response \
	sim-tracker sim-allocator sim-monitor sim-boundary sta-generic sta-egress \
	sta-response sta-tracker sta-allocator sta-monitor sta-boundary \
	lint-addrgen synth-addrgen sim-addrgen sta-addrgen lint-mover sta-mover \
	synth-mover sim-mover lint-engine synth-engine sim-engine \
	lint-shared-sram synth-shared-sram sim-shared-sram \
	lint-pod synth-pod sim-pod \
	check-liberty test clean FORCE

FORCE:

$(STA_NETLISTS): FORCE

lint: lint-egress lint-response lint-tracker lint-allocator lint-monitor \
	lint-boundary lint-addrgen lint-mover lint-engine lint-shared-sram lint-pod

lint-egress:
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(EGRESS_TOP) \
		$(EGRESS_RTL) $(EGRESS_TB)

lint-response:
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(RESPONSE_TOP) \
		$(RESPONSE_RTL) $(RESPONSE_TB)

lint-tracker:
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(TRACKER_TOP) \
		$(TRACKER_RTL) $(TRACKER_TB)

lint-allocator:
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(ALLOCATOR_TOP) \
		$(ALLOCATOR_RTL) $(ALLOCATOR_TB)

lint-monitor:
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(MONITOR_TOP) \
		$(MONITOR_RTL) $(MONITOR_TB)

lint-boundary:
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(BOUNDARY_TOP) \
		$(BOUNDARY_RTL) $(BOUNDARY_TB)

lint-addrgen:
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(ADDRGEN_TOP) \
		$(ADDRGEN_RTL) $(ADDRGEN_TB)

lint-mover:
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(MOVER_TOP) \
		$(MOVER_RTL) $(MOVER_TB)

lint-engine:
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(ENGINE_TOP) \
		$(ENGINE_RTL) $(ENGINE_TB)

lint-shared-sram:
	$(VERILATOR) $(FLAGS) -Wno-DECLFILENAME --lint-only \
		--top-module $(SHARED_SRAM_TOP) \
		$(SHARED_SRAM_RTL) $(SHARED_SRAM_TB)

lint-pod:
	$(VERILATOR) $(FLAGS) -Wno-DECLFILENAME --lint-only \
		--top-module $(POD_TOP) $(POD_RTL) $(POD_TB)

synth-readiness: synth-egress synth-response synth-tracker synth-allocator \
	synth-monitor synth-boundary synth-addrgen synth-mover synth-engine \
	synth-shared-sram synth-pod

synth-egress:
	$(YOSYS) -q -p 'read_verilog -sv $(EGRESS_RTL); hierarchy -top npu_dma_hbm_egress; proc; opt; check; stat'

synth-response:
	$(YOSYS) -q -p 'read_verilog -sv $(RESPONSE_RTL); hierarchy -top npu_dma_hbm_response_router; proc; opt; check; stat'

synth-tracker:
	$(YOSYS) -q -p 'read_verilog -sv $(TRACKER_RTL); hierarchy -top npu_dma_hbm_tag_tracker; proc; opt; check; stat'

synth-allocator:
	$(YOSYS) -q -p 'read_verilog -sv $(ALLOCATOR_RTL); hierarchy -top npu_dma_local_tag_allocator; proc; opt; check; stat'

synth-monitor:
	$(YOSYS) -q -p 'read_verilog -sv $(MONITOR_RTL); hierarchy -top npu_dma_hbm_status_monitor; proc; opt; check; stat'

synth-boundary:
	$(YOSYS) -q -p 'read_verilog -sv $(BOUNDARY_RTL); hierarchy -top npu_dma_hbm_boundary; proc; opt; check; stat'

synth-addrgen:
	$(YOSYS) -q -p 'read_verilog -sv $(ADDRGEN_RTL); hierarchy -top npu_dma_address_generator; proc; opt; check; stat'

synth-mover:
	$(YOSYS) -q -p 'read_verilog -sv $(MOVER_RTL); hierarchy -top npu_dma_channel_mover; proc; opt; check; stat'

synth-engine:
	$(YOSYS) -q -p 'read_verilog -sv $(ENGINE_RTL); hierarchy -top npu_dma_engine; proc; opt; check; stat'

synth-shared-sram:
	@mkdir -p $(BUILD_DIR)
	$(YOSYS) -p 'read_verilog -sv -lib $(SHARED_SRAM_BLACKBOX); read_verilog -sv $(SHARED_SRAM_SYNTH_RTL); hierarchy -top npu_pod_shared_sram; proc; opt; check; stat' \
		> $(BUILD_DIR)/npu_pod_shared_sram_synth.log
	@test "$$(awk '/KD28_SRAM_SDP_2048X256/{count=$$2} END{print count}' \
		$(BUILD_DIR)/npu_pod_shared_sram_synth.log)" = "256" || \
		{ tail -80 $(BUILD_DIR)/npu_pod_shared_sram_synth.log; \
		  echo "Expected exactly 256 KD28_SRAM_SDP_2048X256 cells"; exit 1; }
	@echo "[SYNTH PASS] npu_pod_shared_sram fixed_macros=256"

synth-pod:
	@mkdir -p $(BUILD_DIR)
	$(YOSYS) -p 'read_verilog -sv -lib $(SHARED_SRAM_BLACKBOX); read_verilog -sv $(POD_SYNTH_RTL); hierarchy -top npu_dma_pod; proc; opt; check; stat' \
		> $(BUILD_DIR)/npu_dma_pod_synth.log
	@test "$$(awk '/KD28_SRAM_SDP_2048X256/{count=$$2} END{print count}' \
		$(BUILD_DIR)/npu_dma_pod_synth.log)" = "256" || \
		{ tail -80 $(BUILD_DIR)/npu_dma_pod_synth.log; \
		  echo "Expected exactly 256 KD28_SRAM_SDP_2048X256 cells"; exit 1; }
	@echo "[SYNTH PASS] npu_dma_pod fixed_macros=256"

$(EGRESS_SIM_BIN): $(EGRESS_RTL) $(EGRESS_TB)
	@mkdir -p $(EGRESS_SIM_DIR)
	$(VERILATOR) $(FLAGS) --binary --top-module $(EGRESS_TOP) \
		--Mdir $(EGRESS_SIM_DIR) $(EGRESS_RTL) $(EGRESS_TB)

$(RESPONSE_SIM_BIN): $(RESPONSE_RTL) $(RESPONSE_TB)
	@mkdir -p $(RESPONSE_SIM_DIR)
	$(VERILATOR) $(FLAGS) --binary --top-module $(RESPONSE_TOP) \
		--Mdir $(RESPONSE_SIM_DIR) $(RESPONSE_RTL) $(RESPONSE_TB)

$(TRACKER_SIM_BIN): $(TRACKER_RTL) $(TRACKER_TB)
	@mkdir -p $(TRACKER_SIM_DIR)
	$(VERILATOR) $(FLAGS) --binary --top-module $(TRACKER_TOP) \
		--Mdir $(TRACKER_SIM_DIR) $(TRACKER_RTL) $(TRACKER_TB)

$(ALLOCATOR_SIM_BIN): $(ALLOCATOR_RTL) $(ALLOCATOR_TB)
	@mkdir -p $(ALLOCATOR_SIM_DIR)
	$(VERILATOR) $(FLAGS) --binary --top-module $(ALLOCATOR_TOP) \
		--Mdir $(ALLOCATOR_SIM_DIR) $(ALLOCATOR_RTL) $(ALLOCATOR_TB)

$(MONITOR_SIM_BIN): $(MONITOR_RTL) $(MONITOR_TB)
	@mkdir -p $(MONITOR_SIM_DIR)
	$(VERILATOR) $(FLAGS) --binary --top-module $(MONITOR_TOP) \
		--Mdir $(MONITOR_SIM_DIR) $(MONITOR_RTL) $(MONITOR_TB)

$(BOUNDARY_SIM_BIN): $(BOUNDARY_RTL) $(BOUNDARY_TB)
	@mkdir -p $(BOUNDARY_SIM_DIR)
	$(VERILATOR) $(FLAGS) --binary --top-module $(BOUNDARY_TOP) \
		--output-split 20000 --output-split-cfuncs 500 \
		--Mdir $(BOUNDARY_SIM_DIR) $(BOUNDARY_RTL) $(BOUNDARY_TB)

$(ADDRGEN_SIM_BIN): $(ADDRGEN_RTL) $(ADDRGEN_TB)
	@mkdir -p $(ADDRGEN_SIM_DIR)
	$(VERILATOR) $(FLAGS) --binary --top-module $(ADDRGEN_TOP) \
		--Mdir $(ADDRGEN_SIM_DIR) $(ADDRGEN_RTL) $(ADDRGEN_TB)

$(MOVER_SIM_BIN): $(MOVER_RTL) $(MOVER_TB)
	@mkdir -p $(MOVER_SIM_DIR)
	$(VERILATOR) $(FLAGS) --binary --top-module $(MOVER_TOP) \
		--Mdir $(MOVER_SIM_DIR) $(MOVER_RTL) $(MOVER_TB)

$(ENGINE_SIM_BIN): $(ENGINE_RTL) $(ENGINE_TB)
	@mkdir -p $(ENGINE_SIM_DIR)
	$(VERILATOR) $(FLAGS) --binary --top-module $(ENGINE_TOP) \
		--output-split 20000 --output-split-cfuncs 500 \
		--Mdir $(ENGINE_SIM_DIR) $(ENGINE_RTL) $(ENGINE_TB)

$(SHARED_SRAM_SIM_BIN): $(SHARED_SRAM_RTL) $(SHARED_SRAM_TB)
	@mkdir -p $(SHARED_SRAM_SIM_DIR)
	$(VERILATOR) $(FLAGS) -Wno-DECLFILENAME --binary \
		--top-module $(SHARED_SRAM_TOP) \
		--output-split 20000 --output-split-cfuncs 500 \
		--Mdir $(SHARED_SRAM_SIM_DIR) \
		$(SHARED_SRAM_RTL) $(SHARED_SRAM_TB)

$(POD_SIM_BIN): $(POD_RTL) $(POD_TB)
	@mkdir -p $(POD_SIM_DIR)
	$(VERILATOR) $(FLAGS) -Wno-DECLFILENAME --binary \
		--top-module $(POD_TOP) \
		--output-split 20000 --output-split-cfuncs 500 \
		--Mdir $(POD_SIM_DIR) $(POD_RTL) $(POD_TB)

sim: sim-egress sim-response sim-tracker sim-allocator sim-monitor sim-boundary \
	sim-addrgen sim-mover sim-engine sim-shared-sram sim-pod

sim-egress: $(EGRESS_SIM_BIN)
	$(EGRESS_SIM_BIN)

sim-response: $(RESPONSE_SIM_BIN)
	$(RESPONSE_SIM_BIN)

sim-tracker: $(TRACKER_SIM_BIN)
	$(TRACKER_SIM_BIN)

sim-allocator: $(ALLOCATOR_SIM_BIN)
	$(ALLOCATOR_SIM_BIN)

sim-monitor: $(MONITOR_SIM_BIN)
	$(MONITOR_SIM_BIN)

sim-boundary: $(BOUNDARY_SIM_BIN)
	$(BOUNDARY_SIM_BIN)

sim-addrgen: $(ADDRGEN_SIM_BIN)
	$(ADDRGEN_SIM_BIN)

sim-mover: $(MOVER_SIM_BIN)
	$(MOVER_SIM_BIN)

sim-engine: $(ENGINE_SIM_BIN)
	$(ENGINE_SIM_BIN)

sim-shared-sram: $(SHARED_SRAM_SIM_BIN)
	$(SHARED_SRAM_SIM_BIN)

sim-pod: $(POD_SIM_BIN)
	$(POD_SIM_BIN)

check-liberty:
	@test -n "$(LIBERTY)" || { echo "LIBERTY must name a readable standard-cell Liberty file"; exit 2; }
	@test -r "$(LIBERTY)" || { echo "LIBERTY is not readable: $(LIBERTY)"; exit 2; }

$(EGRESS_NETLIST): $(EGRESS_RTL) $(SYNTH_SCRIPT) $(CELL_MAP) | check-liberty
	@mkdir -p $(STA_BUILD_DIR)
	LIBERTY="$(abspath $(LIBERTY))" RTL="$(EGRESS_RTL)" \
		TOP=npu_dma_hbm_egress CELL_MAP="$(CELL_MAP)" \
		NETLIST="$(EGRESS_NETLIST)" \
		JSON="$(EGRESS_JSON)" ABC_DELAY_PS=$(ABC_DELAY_PS) \
		$(YOSYS) -q -c $(SYNTH_SCRIPT)

$(RESPONSE_NETLIST): $(RESPONSE_RTL) $(SYNTH_SCRIPT) $(CELL_MAP) | check-liberty
	@mkdir -p $(STA_BUILD_DIR)
	LIBERTY="$(abspath $(LIBERTY))" RTL="$(RESPONSE_RTL)" \
		TOP=npu_dma_hbm_response_router CELL_MAP="$(CELL_MAP)" \
		NETLIST="$(RESPONSE_NETLIST)" \
		JSON="$(RESPONSE_JSON)" ABC_DELAY_PS=$(ABC_DELAY_PS) \
		$(YOSYS) -q -c $(SYNTH_SCRIPT)

$(TRACKER_NETLIST): $(TRACKER_RTL) $(SYNTH_SCRIPT) $(CELL_MAP) | check-liberty
	@mkdir -p $(STA_BUILD_DIR)
	LIBERTY="$(abspath $(LIBERTY))" RTL="$(TRACKER_RTL)" \
		TOP=npu_dma_hbm_tag_tracker CELL_MAP="$(CELL_MAP)" \
		NETLIST="$(TRACKER_NETLIST)" \
		JSON="$(TRACKER_JSON)" ABC_DELAY_PS=$(ABC_DELAY_PS) \
		$(YOSYS) -q -c $(SYNTH_SCRIPT)

$(ALLOCATOR_NETLIST): $(ALLOCATOR_RTL) $(SYNTH_SCRIPT) $(CELL_MAP) | check-liberty
	@mkdir -p $(STA_BUILD_DIR)
	LIBERTY="$(abspath $(LIBERTY))" RTL="$(ALLOCATOR_RTL)" \
		TOP=npu_dma_local_tag_allocator CELL_MAP="$(CELL_MAP)" \
		NETLIST="$(ALLOCATOR_NETLIST)" \
		JSON="$(ALLOCATOR_JSON)" ABC_DELAY_PS=$(ALLOCATOR_ABC_DELAY_PS) \
		$(YOSYS) -q -c $(SYNTH_SCRIPT)

$(MONITOR_NETLIST): $(MONITOR_RTL) $(SYNTH_SCRIPT) $(CELL_MAP) | check-liberty
	@mkdir -p $(STA_BUILD_DIR)
	LIBERTY="$(abspath $(LIBERTY))" RTL="$(MONITOR_RTL)" \
		TOP=npu_dma_hbm_status_monitor CELL_MAP="$(CELL_MAP)" \
		NETLIST="$(MONITOR_NETLIST)" \
		JSON="$(MONITOR_JSON)" ABC_DELAY_PS=$(ABC_DELAY_PS) \
		$(YOSYS) -q -c $(SYNTH_SCRIPT)

$(BOUNDARY_NETLIST): $(BOUNDARY_RTL) $(SYNTH_SCRIPT) $(CELL_MAP) | check-liberty
	@mkdir -p $(STA_BUILD_DIR)
	LIBERTY="$(abspath $(LIBERTY))" RTL="$(BOUNDARY_RTL)" \
		TOP=npu_dma_hbm_boundary CELL_MAP="$(CELL_MAP)" \
		NETLIST="$(BOUNDARY_NETLIST)" \
		JSON="$(BOUNDARY_JSON)" ABC_DELAY_PS=$(BOUNDARY_ABC_DELAY_PS) \
		$(YOSYS) -q -c $(SYNTH_SCRIPT)

$(ADDRGEN_NETLIST): $(ADDRGEN_RTL) $(SYNTH_SCRIPT) $(CELL_MAP) | check-liberty
	@mkdir -p $(STA_BUILD_DIR)
	LIBERTY="$(abspath $(LIBERTY))" RTL="$(ADDRGEN_RTL)" \
		TOP=npu_dma_address_generator CELL_MAP="$(CELL_MAP)" \
		NETLIST="$(ADDRGEN_NETLIST)" \
		JSON="$(ADDRGEN_JSON)" ABC_DELAY_PS=$(ADDRGEN_ABC_DELAY_PS) \
		$(YOSYS) -q -c $(SYNTH_SCRIPT)

$(MOVER_NETLIST): $(MOVER_RTL) $(SYNTH_SCRIPT) $(CELL_MAP) | check-liberty
	@mkdir -p $(STA_BUILD_DIR)
	LIBERTY="$(abspath $(LIBERTY))" RTL="$(MOVER_RTL)" \
		TOP=npu_dma_channel_mover CELL_MAP="$(CELL_MAP)" \
		NETLIST="$(MOVER_NETLIST)" \
		JSON="$(MOVER_JSON)" ABC_DELAY_PS=$(MOVER_ABC_DELAY_PS) \
		$(YOSYS) -q -c $(SYNTH_SCRIPT)

sta-generic: sta-egress sta-response sta-tracker sta-allocator sta-monitor \
	sta-boundary sta-addrgen sta-mover

sta-egress: $(EGRESS_NETLIST)
	LIBERTY="$(abspath $(LIBERTY))" NETLIST="$(EGRESS_NETLIST)" \
		TOP=npu_dma_hbm_egress SDC="$(EGRESS_SDC)" \
		CLOCK_PERIOD_NS=$(CLOCK_PERIOD_NS) \
		CLOCK_UNCERTAINTY_NS=$(CLOCK_UNCERTAINTY_NS) \
		INPUT_DELAY_NS=$(INPUT_DELAY_NS) OUTPUT_DELAY_NS=$(OUTPUT_DELAY_NS) \
		OUTPUT_LOAD_PF=$(OUTPUT_LOAD_PF) $(OPENSTA) $(STA_SCRIPT)

sta-response: $(RESPONSE_NETLIST)
	LIBERTY="$(abspath $(LIBERTY))" NETLIST="$(RESPONSE_NETLIST)" \
		TOP=npu_dma_hbm_response_router SDC="$(RESPONSE_SDC)" \
		CLOCK_PERIOD_NS=$(CLOCK_PERIOD_NS) \
		CLOCK_UNCERTAINTY_NS=$(CLOCK_UNCERTAINTY_NS) \
		INPUT_DELAY_NS=$(INPUT_DELAY_NS) OUTPUT_DELAY_NS=$(OUTPUT_DELAY_NS) \
		OUTPUT_LOAD_PF=$(OUTPUT_LOAD_PF) $(OPENSTA) $(STA_SCRIPT)

sta-tracker: $(TRACKER_NETLIST)
	LIBERTY="$(abspath $(LIBERTY))" NETLIST="$(TRACKER_NETLIST)" \
		TOP=npu_dma_hbm_tag_tracker SDC="$(TRACKER_SDC)" \
		CLOCK_PERIOD_NS=$(CLOCK_PERIOD_NS) \
		CLOCK_UNCERTAINTY_NS=$(CLOCK_UNCERTAINTY_NS) \
		INPUT_DELAY_NS=$(INPUT_DELAY_NS) OUTPUT_DELAY_NS=$(OUTPUT_DELAY_NS) \
		OUTPUT_LOAD_PF=$(OUTPUT_LOAD_PF) $(OPENSTA) $(STA_SCRIPT)

sta-allocator: $(ALLOCATOR_NETLIST)
	LIBERTY="$(abspath $(LIBERTY))" NETLIST="$(ALLOCATOR_NETLIST)" \
		TOP=npu_dma_local_tag_allocator SDC="$(ALLOCATOR_SDC)" \
		CLOCK_PERIOD_NS=$(CLOCK_PERIOD_NS) \
		CLOCK_UNCERTAINTY_NS=$(CLOCK_UNCERTAINTY_NS) \
		INPUT_DELAY_NS=$(INPUT_DELAY_NS) OUTPUT_DELAY_NS=$(OUTPUT_DELAY_NS) \
		OUTPUT_LOAD_PF=$(OUTPUT_LOAD_PF) $(OPENSTA) $(STA_SCRIPT)

sta-monitor: $(MONITOR_NETLIST)
	LIBERTY="$(abspath $(LIBERTY))" NETLIST="$(MONITOR_NETLIST)" \
		TOP=npu_dma_hbm_status_monitor SDC="$(MONITOR_SDC)" \
		CLOCK_PERIOD_NS=$(CLOCK_PERIOD_NS) \
		CLOCK_UNCERTAINTY_NS=$(CLOCK_UNCERTAINTY_NS) \
		INPUT_DELAY_NS=$(INPUT_DELAY_NS) OUTPUT_DELAY_NS=$(OUTPUT_DELAY_NS) \
		OUTPUT_LOAD_PF=$(OUTPUT_LOAD_PF) $(OPENSTA) $(STA_SCRIPT)

sta-boundary: $(BOUNDARY_NETLIST)
	LIBERTY="$(abspath $(LIBERTY))" NETLIST="$(BOUNDARY_NETLIST)" \
		TOP=npu_dma_hbm_boundary SDC="$(BOUNDARY_SDC)" \
		CLOCK_PERIOD_NS=$(CLOCK_PERIOD_NS) \
		CLOCK_UNCERTAINTY_NS=$(CLOCK_UNCERTAINTY_NS) \
		INPUT_DELAY_NS=$(INPUT_DELAY_NS) OUTPUT_DELAY_NS=$(OUTPUT_DELAY_NS) \
		OUTPUT_LOAD_PF=$(OUTPUT_LOAD_PF) $(OPENSTA) $(STA_SCRIPT)

sta-addrgen: $(ADDRGEN_NETLIST)
	LIBERTY="$(abspath $(LIBERTY))" NETLIST="$(ADDRGEN_NETLIST)" \
		TOP=npu_dma_address_generator SDC="$(ADDRGEN_SDC)" \
		CLOCK_PERIOD_NS=$(CLOCK_PERIOD_NS) \
		CLOCK_UNCERTAINTY_NS=$(CLOCK_UNCERTAINTY_NS) \
		INPUT_DELAY_NS=$(INPUT_DELAY_NS) OUTPUT_DELAY_NS=$(OUTPUT_DELAY_NS) \
		OUTPUT_LOAD_PF=$(OUTPUT_LOAD_PF) $(OPENSTA) $(STA_SCRIPT)

sta-mover: $(MOVER_NETLIST)
	LIBERTY="$(abspath $(LIBERTY))" NETLIST="$(MOVER_NETLIST)" \
		TOP=npu_dma_channel_mover SDC="$(MOVER_SDC)" \
		CLOCK_PERIOD_NS=$(CLOCK_PERIOD_NS) \
		CLOCK_UNCERTAINTY_NS=$(CLOCK_UNCERTAINTY_NS) \
		INPUT_DELAY_NS=$(INPUT_DELAY_NS) OUTPUT_DELAY_NS=$(OUTPUT_DELAY_NS) \
		OUTPUT_LOAD_PF=$(OUTPUT_LOAD_PF) $(OPENSTA) $(STA_SCRIPT)

test: lint synth-readiness sim

clean:
	rm -rf $(BUILD_DIR)
