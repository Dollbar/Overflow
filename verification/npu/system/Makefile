VERILATOR ?= verilator
YOSYS ?= yosys
OPENSTA ?= sta
LIBERTY ?=
CLOCK_PERIOD_NS ?= 1.000
CLOCK_UNCERTAINTY_NS ?= 0.030
INPUT_DELAY_NS ?= 0.050
OUTPUT_DELAY_NS ?= 0.050
OUTPUT_LOAD_PF ?= 0.005

THIS_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(THIS_DIR)/../../..)
BUILD_DIR := $(THIS_DIR)/build
EGRESS_RTL := \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_control_buffer.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_rank_count16.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_request_slot.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_egress.sv
EGRESS_TB := $(THIS_DIR)/tb/tb_npu_dma_hbm_egress.sv
EGRESS_TOP := tb_npu_dma_hbm_egress
EGRESS_SIM_DIR := $(BUILD_DIR)/verilator/$(EGRESS_TOP)
EGRESS_SIM_BIN := $(EGRESS_SIM_DIR)/V$(EGRESS_TOP)
RESPONSE_RTL := \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_control_buffer.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_response_channel.sv \
	$(REPO_ROOT)/rtl/npu/dma/npu_dma_hbm_response_router.sv
RESPONSE_TB := $(THIS_DIR)/tb/tb_npu_dma_hbm_response_router.sv
RESPONSE_TOP := tb_npu_dma_hbm_response_router
RESPONSE_SIM_DIR := $(BUILD_DIR)/verilator/$(RESPONSE_TOP)
RESPONSE_SIM_BIN := $(RESPONSE_SIM_DIR)/V$(RESPONSE_TOP)
STA_DIR := $(THIS_DIR)/STA
STA_BUILD_DIR := $(BUILD_DIR)/sta
STA_SCRIPT := $(STA_DIR)/scripts/sta_generic.tcl
SYNTH_SCRIPT := $(STA_DIR)/scripts/synth_generic.tcl
CELL_MAP := $(STA_DIR)/scripts/generic_cells_map.v
EGRESS_NETLIST := $(STA_BUILD_DIR)/npu_dma_hbm_egress_mapped.v
EGRESS_JSON := $(STA_BUILD_DIR)/npu_dma_hbm_egress_mapped.json
EGRESS_SDC := $(STA_DIR)/sdc/npu_dma_hbm_egress_1ghz.sdc
RESPONSE_NETLIST := $(STA_BUILD_DIR)/npu_dma_hbm_response_router_mapped.v
RESPONSE_JSON := $(STA_BUILD_DIR)/npu_dma_hbm_response_router_mapped.json
RESPONSE_SDC := $(STA_DIR)/sdc/npu_dma_hbm_response_router_1ghz.sdc
FLAGS := --language 1800-2017 -Wall --timing

.PHONY: lint lint-egress lint-response synth-readiness synth-egress synth-response \
	sim sim-egress sim-response sta-generic sta-egress sta-response \
	check-liberty test clean

lint: lint-egress lint-response

lint-egress:
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(EGRESS_TOP) \
		$(EGRESS_RTL) $(EGRESS_TB)

lint-response:
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(RESPONSE_TOP) \
		$(RESPONSE_RTL) $(RESPONSE_TB)

synth-readiness: synth-egress synth-response

synth-egress:
	$(YOSYS) -q -p 'read_verilog -sv $(EGRESS_RTL); hierarchy -top npu_dma_hbm_egress; proc; opt; check; stat'

synth-response:
	$(YOSYS) -q -p 'read_verilog -sv $(RESPONSE_RTL); hierarchy -top npu_dma_hbm_response_router; proc; opt; check; stat'

$(EGRESS_SIM_BIN): $(EGRESS_RTL) $(EGRESS_TB)
	@mkdir -p $(EGRESS_SIM_DIR)
	$(VERILATOR) $(FLAGS) --binary --top-module $(EGRESS_TOP) \
		--Mdir $(EGRESS_SIM_DIR) $(EGRESS_RTL) $(EGRESS_TB)

$(RESPONSE_SIM_BIN): $(RESPONSE_RTL) $(RESPONSE_TB)
	@mkdir -p $(RESPONSE_SIM_DIR)
	$(VERILATOR) $(FLAGS) --binary --top-module $(RESPONSE_TOP) \
		--Mdir $(RESPONSE_SIM_DIR) $(RESPONSE_RTL) $(RESPONSE_TB)

sim: sim-egress sim-response

sim-egress: $(EGRESS_SIM_BIN)
	$(EGRESS_SIM_BIN)

sim-response: $(RESPONSE_SIM_BIN)
	$(RESPONSE_SIM_BIN)

check-liberty:
	@test -n "$(LIBERTY)" || { echo "LIBERTY must name a readable standard-cell Liberty file"; exit 2; }
	@test -r "$(LIBERTY)" || { echo "LIBERTY is not readable: $(LIBERTY)"; exit 2; }

$(EGRESS_NETLIST): $(EGRESS_RTL) $(SYNTH_SCRIPT) $(CELL_MAP) | check-liberty
	@mkdir -p $(STA_BUILD_DIR)
	LIBERTY="$(abspath $(LIBERTY))" RTL="$(EGRESS_RTL)" \
		TOP=npu_dma_hbm_egress CELL_MAP="$(CELL_MAP)" \
		NETLIST="$(EGRESS_NETLIST)" \
		JSON="$(EGRESS_JSON)" $(YOSYS) -q -c $(SYNTH_SCRIPT)

$(RESPONSE_NETLIST): $(RESPONSE_RTL) $(SYNTH_SCRIPT) $(CELL_MAP) | check-liberty
	@mkdir -p $(STA_BUILD_DIR)
	LIBERTY="$(abspath $(LIBERTY))" RTL="$(RESPONSE_RTL)" \
		TOP=npu_dma_hbm_response_router CELL_MAP="$(CELL_MAP)" \
		NETLIST="$(RESPONSE_NETLIST)" \
		JSON="$(RESPONSE_JSON)" $(YOSYS) -q -c $(SYNTH_SCRIPT)

sta-generic: sta-egress sta-response

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

test: lint synth-readiness sim

clean:
	rm -rf $(BUILD_DIR)
