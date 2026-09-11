# Run: make -f scripts/initialization.mk sim-initialization PORTS=4
# Outputs: build/initialization_*/{vectors.mem,compile.log,obj}, reports/initialization_*.log.
# Next: integration, formal and actual-library physical gates before stage closure.
SHELL := /bin/bash
.DEFAULT_GOAL := sim-initialization
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
HALF_PERIOD_PS ?= 320
WAIT ?= 0
UNIFORM_CAPACITY ?=
PATTERN ?= standard
CAPACITY_SUFFIX := $(if $(UNIFORM_CAPACITY),_uniform$(UNIFORM_CAPACITY),)$(if $(filter-out standard,$(PATTERN)),_$(PATTERN),)
INIT_RUN := $(ROOT_DIR)/build/initialization_$(PORTS)_$(CREDIT_WIDTH)_$(HALF_PERIOD_PS)$(CAPACITY_SUFFIX)
VECTOR_ARGS := --ports $(PORTS) --width $(CREDIT_WIDTH) --pattern $(PATTERN) $(if $(UNIFORM_CAPACITY),--uniform-capacity $(UNIFORM_CAPACITY),)
INIT_SYNTH := $(ROOT_DIR)/build/initialization_synth_$(PORTS)
INIT_LIB := $(LIB_ROOT)/tcbn28hpcplusbwp40p140$(CORNER).lib
STARTUP_RUN := $(ROOT_DIR)/build/startup_$(PORTS)_$(CREDIT_WIDTH)_$(WAIT)_$(HALF_PERIOD_PS)$(CAPACITY_SUFFIX)

# Run: make -f scripts/initialization.mk sim-startup PORTS=4 WAIT=1
# Outputs: build/startup_*/vectors.mem, compile.log, obj; reports/startup_*.log.
# Next: review four-channel direction/timing, then receiver storage and normal returns.
.PHONY: sim-startup
sim-startup:
	@test "$(WAIT)" = 0 -o "$(WAIT)" = 1
	@test "$(HALF_PERIOD_PS)" = 320 -o "$(HALF_PERIOD_PS)" = 3200
	mkdir -p "$(STARTUP_RUN)" "$(ROOT_DIR)/reports"
	$(PYTHON) "$(ROOT_DIR)/verification/rtl/startup_vectors.py" $(VECTOR_ARGS) --wait $(WAIT) > "$(STARTUP_RUN)/vectors.mem"
	init_caps=$$($(PYTHON) "$(ROOT_DIR)/verification/rtl/initialization_vectors.py" $(VECTOR_ARGS) --capacities); \
	$(VERILATOR) --binary --timing --language 1364-2001 -Wall --top-module upli_credit_startup_tb --Mdir "$(STARTUP_RUN)/obj" -GC_NUM_PORTS=$(PORTS) -GC_CREDIT_WIDTH=$(CREDIT_WIDTH) -GC_HALF_PERIOD_PS=$(HALF_PERIOD_PS) "-GC_WAIT=1'b$(WAIT)" "-GC_CAPACITIES=$$(( $(PORTS)*5*$(CREDIT_WIDTH) ))'h$$init_caps" "$(ROOT_DIR)/rtl/upli/upli_connection_side.v" "$(ROOT_DIR)/rtl/upli/upli_credit_initializer.v" "$(ROOT_DIR)/rtl/upli/upli_credit_bank.v" "$(ROOT_DIR)/verification/rtl/upli_credit_startup_tb.v" > "$(STARTUP_RUN)/compile.log" 2>&1 || { tail -n 30 "$(STARTUP_RUN)/compile.log"; exit 1; }
	"$(STARTUP_RUN)/obj/Vupli_credit_startup_tb" +VECTORS="$(STARTUP_RUN)/vectors.mem" 2>&1 | tee "$(ROOT_DIR)/reports/startup_$(PORTS)_$(CREDIT_WIDTH)_$(WAIT)_$(HALF_PERIOD_PS)$(CAPACITY_SUFFIX).log"

# Physical characterization fixes width4 and all capacities8; explicit authorized library.
.PHONY: synth-initialization sta-initialization
synth-initialization:
	@test "$(PATTERN)" = standard
	@test "$(CREDIT_WIDTH)" = 4 && test "$(CORNER)" = ssg0p81v125c
	@test -z "$(UNIFORM_CAPACITY)" -o "$(UNIFORM_CAPACITY)" = 8
	@test -n "$(LIB_ROOT)" && test -f "$(INIT_LIB)"
	mkdir -p "$(INIT_SYNTH)" "$(ROOT_DIR)/reports"
	UALINK_LIBERTY="$(INIT_LIB)" UALINK_BUILD_DIR="$(INIT_SYNTH)" UALINK_PORTS=$(PORTS) $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/synth_initialization.tcl" > "$(ROOT_DIR)/reports/initialization_synth_$(PORTS).log" 2>&1 || { tail -n 40 "$(ROOT_DIR)/reports/initialization_synth_$(PORTS).log"; exit 1; }

sta-initialization:
	@test "$(PATTERN)" = standard
	@test "$(CREDIT_WIDTH)" = 4
	@test -z "$(UNIFORM_CAPACITY)" -o "$(UNIFORM_CAPACITY)" = 8
	@test -n "$(LIB_ROOT)" && test -f "$(INIT_LIB)" && test -f "$(INIT_SYNTH)/mapped.v"
	mkdir -p "$(ROOT_DIR)/reports"
	UALINK_LIBERTY="$(INIT_LIB)" UALINK_NETLIST="$(INIT_SYNTH)/mapped.v" UALINK_PERIOD_NS=$(PERIOD_NS) $(STA) -exit "$(ROOT_DIR)/scripts/sta_initialization.tcl" > "$(ROOT_DIR)/reports/initialization_sta_$(PORTS)_$(CORNER)_$(PERIOD_NS).log" 2>&1 || { tail -n 12 "$(ROOT_DIR)/reports/initialization_sta_$(PORTS)_$(CORNER)_$(PERIOD_NS).log"; exit 1; }
	$(PYTHON) "$(ROOT_DIR)/scripts/check_sta_report.py" "$(ROOT_DIR)/reports/initialization_sta_$(PORTS)_$(CORNER)_$(PERIOD_NS).log" --design initialization

.PHONY: sim-initialization
.PHONY: prove-initialization
prove-initialization:
	mkdir -p "$(ROOT_DIR)/reports"
	init_caps=$$($(PYTHON) "$(ROOT_DIR)/verification/rtl/initialization_vectors.py" $(VECTOR_ARGS) --capacities); \
	UALINK_PORTS=$(PORTS) UALINK_CREDIT_WIDTH=$(CREDIT_WIDTH) UALINK_CAPACITIES="$$init_caps" UALINK_BUILD_DIR="$(ROOT_DIR)/build/initialization_properties_$(PORTS)_$(CREDIT_WIDTH)$(CAPACITY_SUFFIX)" $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/prove_initialization.tcl" > "$(ROOT_DIR)/reports/initialization_properties_$(PORTS)_$(CREDIT_WIDTH)$(CAPACITY_SUFFIX).log" 2>&1 || { tail -n 30 "$(ROOT_DIR)/reports/initialization_properties_$(PORTS)_$(CREDIT_WIDTH)$(CAPACITY_SUFFIX).log"; exit 1; }

.PHONY: equiv-initialization
equiv-initialization:
	@test "$(PATTERN)" = standard
	@test "$(CREDIT_WIDTH)" = 4 && test "$(CORNER)" = ssg0p81v125c
	@test -z "$(UNIFORM_CAPACITY)" -o "$(UNIFORM_CAPACITY)" = 8
	@test -n "$(LIB_ROOT)" && test -f "$(INIT_LIB)" && test -f "$(INIT_SYNTH)/mapped.v"
	mkdir -p "$(ROOT_DIR)/reports"
	UALINK_LIBERTY="$(INIT_LIB)" UALINK_NETLIST="$(INIT_SYNTH)/mapped.v" UALINK_PORTS=$(PORTS) $(YOSYS) -Q -T -c "$(ROOT_DIR)/scripts/equiv_initialization.tcl" > "$(ROOT_DIR)/reports/initialization_equiv_$(PORTS).log" 2>&1 || { tail -n 30 "$(ROOT_DIR)/reports/initialization_equiv_$(PORTS).log"; exit 1; }

sim-initialization:
	@test "$(HALF_PERIOD_PS)" = 320 -o "$(HALF_PERIOD_PS)" = 3200
	mkdir -p "$(INIT_RUN)" "$(ROOT_DIR)/reports"
	$(PYTHON) "$(ROOT_DIR)/verification/rtl/initialization_vectors.py" $(VECTOR_ARGS) > "$(INIT_RUN)/vectors.mem"
	init_caps=$$($(PYTHON) "$(ROOT_DIR)/verification/rtl/initialization_vectors.py" $(VECTOR_ARGS) --capacities); \
	$(VERILATOR) --binary --timing --language 1364-2001 -Wall --top-module upli_credit_initialization_tb --Mdir "$(INIT_RUN)/obj" -GC_NUM_PORTS=$(PORTS) -GC_CREDIT_WIDTH=$(CREDIT_WIDTH) -GC_HALF_PERIOD_PS=$(HALF_PERIOD_PS) "-GC_CAPACITIES=$$(( $(PORTS)*5*$(CREDIT_WIDTH) ))'h$$init_caps" "$(ROOT_DIR)/rtl/upli/upli_credit_initializer.v" "$(ROOT_DIR)/verification/rtl/upli_credit_initialization_tb.v" > "$(INIT_RUN)/compile.log" 2>&1 || { tail -n 30 "$(INIT_RUN)/compile.log"; exit 1; }
	"$(INIT_RUN)/obj/Vupli_credit_initialization_tb" +VECTORS="$(INIT_RUN)/vectors.mem" 2>&1 | tee "$(ROOT_DIR)/reports/initialization_$(PORTS)_$(CREDIT_WIDTH)_$(HALF_PERIOD_PS)$(CAPACITY_SUFFIX).log"
