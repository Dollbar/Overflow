# Run: make -f scripts/credit.mk sim-credit PORTS=4 CREDIT_WIDTH=4 INIT_CYCLES=2
# Outputs: build/credit_*/{vectors.mem,compile.log,obj/} and reports/credit_*.log.
# Next: synth-credit and sta-credit with an explicit authorized LIB_ROOT.
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
PYTHON ?= python3
VERILATOR ?= verilator
YOSYS ?= yosys
STA ?= sta
LIB_ROOT ?=
CORNER ?= ssg0p81v125c
PERIOD_NS ?= 0.640
PORTS ?= 1
CREDIT_WIDTH ?= 4
INIT_CYCLES ?= 2
HALF_PERIOD_PS ?= 320
UNIFORM_CAPACITY ?=
CAPACITY_SUFFIX := $(if $(UNIFORM_CAPACITY),_uniform$(UNIFORM_CAPACITY),)
CREDIT_RUN := $(ROOT_DIR)/build/credit_$(PORTS)_$(CREDIT_WIDTH)_$(INIT_CYCLES)_$(HALF_PERIOD_PS)$(CAPACITY_SUFFIX)
VECTOR_ARGS := --ports $(PORTS) --width $(CREDIT_WIDTH) --init $(INIT_CYCLES) $(if $(UNIFORM_CAPACITY),--uniform-capacity $(UNIFORM_CAPACITY),)
CREDIT_SYNTH := $(ROOT_DIR)/build/credit_synth_$(PORTS)
CREDIT_LIB := $(LIB_ROOT)/tcbn28hpcplusbwp40p140$(CORNER).lib

.PHONY: sim-credit
sim-credit:
	@test "$(HALF_PERIOD_PS)" = 320 -o "$(HALF_PERIOD_PS)" = 3200
	mkdir -p "$(CREDIT_RUN)" "$(ROOT_DIR)/reports"
	$(PYTHON) "$(ROOT_DIR)/verification/rtl/credit_vectors.py" $(VECTOR_ARGS) > "$(CREDIT_RUN)/vectors.mem"
	credit_caps=$$($(PYTHON) "$(ROOT_DIR)/verification/rtl/credit_vectors.py" $(VECTOR_ARGS) --capacities); \
	$(VERILATOR) --binary --timing --language 1364-2001 -Wall --top-module upli_credit_tb --Mdir "$(CREDIT_RUN)/obj" -GC_NUM_PORTS=$(PORTS) -GC_CREDIT_WIDTH=$(CREDIT_WIDTH) -GC_INIT_CYCLES=$(INIT_CYCLES) -GC_HALF_PERIOD_PS=$(HALF_PERIOD_PS) "-GC_CAPACITIES=$$(( $(PORTS)*5*$(CREDIT_WIDTH) ))'h$$credit_caps" "$(ROOT_DIR)/rtl/upli/upli_credit_bank.v" "$(ROOT_DIR)/verification/rtl/upli_credit_tb.v" > "$(CREDIT_RUN)/compile.log" 2>&1 || { tail -n 40 "$(CREDIT_RUN)/compile.log"; exit 1; }
	"$(CREDIT_RUN)/obj/Vupli_credit_tb" +VECTORS="$(CREDIT_RUN)/vectors.mem" 2>&1 | tee "$(ROOT_DIR)/reports/credit_$(PORTS)_$(CREDIT_WIDTH)_$(INIT_CYCLES)_$(HALF_PERIOD_PS)$(CAPACITY_SUFFIX).log"

.PHONY: prove-credit
prove-credit:
	mkdir -p "$(ROOT_DIR)/reports"
	credit_caps=$$($(PYTHON) "$(ROOT_DIR)/verification/rtl/credit_vectors.py" $(VECTOR_ARGS) --capacities); \
	UALINK_PORTS=$(PORTS) UALINK_CREDIT_WIDTH=$(CREDIT_WIDTH) UALINK_INIT_CYCLES=$(INIT_CYCLES) UALINK_CAPACITIES="$$credit_caps" $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/prove_credit.tcl" > "$(ROOT_DIR)/reports/credit_bounds_$(PORTS)_$(CREDIT_WIDTH)_$(INIT_CYCLES)$(CAPACITY_SUFFIX).log" 2>&1 || { tail -n 30 "$(ROOT_DIR)/reports/credit_bounds_$(PORTS)_$(CREDIT_WIDTH)_$(INIT_CYCLES)$(CAPACITY_SUFFIX).log"; exit 1; }

# Physical characterization deliberately fixes width=4, capacity=8, init=2.
.PHONY: synth-credit sta-credit equiv-credit
synth-credit:
	@test "$(CREDIT_WIDTH)" = 4 && test "$(INIT_CYCLES)" = 2
	@test -z "$(UNIFORM_CAPACITY)" -o "$(UNIFORM_CAPACITY)" = 8
	@test "$(CORNER)" = ssg0p81v125c && test -n "$(LIB_ROOT)" && test -f "$(CREDIT_LIB)"
	mkdir -p "$(CREDIT_SYNTH)" "$(ROOT_DIR)/reports"
	UALINK_LIBERTY="$(CREDIT_LIB)" UALINK_BUILD_DIR="$(CREDIT_SYNTH)" UALINK_PORTS=$(PORTS) $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/synth_credit.tcl" > "$(ROOT_DIR)/reports/credit_synth_$(PORTS).log" 2>&1 || { tail -n 50 "$(ROOT_DIR)/reports/credit_synth_$(PORTS).log"; exit 1; }

sta-credit:
	@test "$(CREDIT_WIDTH)" = 4 && test "$(INIT_CYCLES)" = 2
	@test -z "$(UNIFORM_CAPACITY)" -o "$(UNIFORM_CAPACITY)" = 8
	@test -n "$(LIB_ROOT)" && test -f "$(CREDIT_LIB)" && test -f "$(CREDIT_SYNTH)/mapped.v"
	mkdir -p "$(ROOT_DIR)/reports"
	UALINK_LIBERTY="$(CREDIT_LIB)" UALINK_NETLIST="$(CREDIT_SYNTH)/mapped.v" UALINK_PERIOD_NS=$(PERIOD_NS) $(STA) -exit "$(ROOT_DIR)/scripts/sta_credit.tcl" > "$(ROOT_DIR)/reports/credit_sta_$(PORTS)_$(CORNER)_$(PERIOD_NS).log" 2>&1 || { tail -n 12 "$(ROOT_DIR)/reports/credit_sta_$(PORTS)_$(CORNER)_$(PERIOD_NS).log"; exit 1; }
	$(PYTHON) "$(ROOT_DIR)/scripts/check_sta_report.py" "$(ROOT_DIR)/reports/credit_sta_$(PORTS)_$(CORNER)_$(PERIOD_NS).log"

equiv-credit:
	@test "$(CREDIT_WIDTH)" = 4 && test "$(INIT_CYCLES)" = 2
	@test -z "$(UNIFORM_CAPACITY)" -o "$(UNIFORM_CAPACITY)" = 8
	@test "$(CORNER)" = ssg0p81v125c && test -n "$(LIB_ROOT)" && test -f "$(CREDIT_LIB)" && test -f "$(CREDIT_SYNTH)/mapped.v"
	mkdir -p "$(ROOT_DIR)/reports"
	UALINK_LIBERTY="$(CREDIT_LIB)" UALINK_NETLIST="$(CREDIT_SYNTH)/mapped.v" UALINK_PORTS=$(PORTS) $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/equiv_credit.tcl" > "$(ROOT_DIR)/reports/credit_equiv_$(PORTS).log" 2>&1 || { tail -n 30 "$(ROOT_DIR)/reports/credit_equiv_$(PORTS).log"; exit 1; }
