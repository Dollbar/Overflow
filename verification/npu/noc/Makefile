VERILATOR ?= verilator
VERILATOR_COVERAGE ?= verilator_coverage
YOSYS ?= yosys
PYTHON ?= python3
JOBS ?= 4
NOC_SEED0 ?= 5130563
NOC_SEED1 ?= 12648430
NOC_SEED2 ?= 19088743
NOC_SEED3 ?= 305419896

THIS_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(THIS_DIR)/../../..)
BUILD_DIR := $(THIS_DIR)/build
FLAGS := --language 1800-2017 -Wall --timing --no-sched-zero-delay
COVERAGE_FLAGS := --coverage-line --coverage-expr --coverage-toggle \
	--coverage-max-width 256
COVERAGE_CHECKER := \
	$(REPO_ROOT)/verification/npu/common/scripts/check_verilator_coverage.py
COVERAGE_MIN_LINE ?= 94
COVERAGE_MIN_BRANCH ?= 80
COVERAGE_MIN_EXPR ?= 58
# Wide payload/counter state dominates toggle bins; this gate is a measured
# regression baseline, not a claim that idle payload bits should all toggle.
COVERAGE_MIN_TOGGLE ?= 17
FULL_COVERAGE_MIN_LINE ?= 92
FULL_COVERAGE_MIN_BRANCH ?= 78
FULL_COVERAGE_MIN_EXPR ?= 61
FULL_COVERAGE_MIN_TOGGLE ?= 38

POD_NOC_PKG := $(REPO_ROOT)/rtl/npu/pod/npu_pod_noc_pkg.sv
NOC_PKG := $(REPO_ROOT)/rtl/npu/noc/npu_noc_pkg.sv
FIFO_RTL := $(REPO_ROOT)/rtl/npu/noc/npu_noc_vc_fifo.sv
ROUTER_RTL := $(REPO_ROOT)/rtl/npu/noc/npu_noc_lane_router.sv
FABRIC_RTL := $(REPO_ROOT)/rtl/npu/noc/npu_noc_fabric_mesh.sv
MESH_RTL := $(REPO_ROOT)/rtl/npu/noc/npu_noc_mesh.sv
TB_PKG := $(THIS_DIR)/pkg/npu_noc_tb_pkg.sv
SOURCE_VIP := $(THIS_DIR)/vip/npu_noc_flit_source_vip.sv
SINK_VIP := $(THIS_DIR)/vip/npu_noc_flit_sink_vip.sv
MONITOR_VIP := $(THIS_DIR)/vip/npu_noc_flit_monitor_vip.sv
CHECKER_VIP := $(THIS_DIR)/vip/npu_noc_protocol_checker_vip.sv
RESET_SYNC_RTL := $(REPO_ROOT)/rtl/npu/noc/npu_noc_reset_sync.sv
LEVEL_SYNC_RTL := $(REPO_ROOT)/rtl/npu/noc/npu_noc_level_sync.sv
ASYNC_FIFO_RTL := $(REPO_ROOT)/rtl/npu/noc/npu_noc_async_fifo.sv
POD_CDC_RTL := $(REPO_ROOT)/rtl/npu/noc/npu_noc_pod_cdc.sv
CDC_MESH_RTL := $(REPO_ROOT)/rtl/npu/noc/npu_noc_cdc_mesh.sv

FIFO_TOP := tb_npu_noc_vc_fifo
FIFO_TB := $(THIS_DIR)/tb/$(FIFO_TOP).sv
FIFO_DIR := $(BUILD_DIR)/verilator/$(FIFO_TOP)
FIFO_BIN := $(FIFO_DIR)/V$(FIFO_TOP)

ROUTER_TOP := tb_npu_noc_lane_router
ROUTER_TB := $(THIS_DIR)/tb/$(ROUTER_TOP).sv
ROUTER_DIR := $(BUILD_DIR)/verilator/$(ROUTER_TOP)
ROUTER_BIN := $(ROUTER_DIR)/V$(ROUTER_TOP)

ERROR_TOP := tb_npu_noc_router_errors
ERROR_TB := $(THIS_DIR)/tb/$(ERROR_TOP).sv
ERROR_DIR := $(BUILD_DIR)/verilator/$(ERROR_TOP)
ERROR_BIN := $(ERROR_DIR)/V$(ERROR_TOP)

ROUTER_COVERAGE_DIR := $(BUILD_DIR)/coverage/$(ROUTER_TOP)
ROUTER_COVERAGE_BIN := $(ROUTER_COVERAGE_DIR)/V$(ROUTER_TOP)
ROUTER_COVERAGE_DATA := $(ROUTER_COVERAGE_DIR)/coverage.dat
ERROR_COVERAGE_DIR := $(BUILD_DIR)/coverage/$(ERROR_TOP)
ERROR_COVERAGE_BIN := $(ERROR_COVERAGE_DIR)/V$(ERROR_TOP)
ERROR_COVERAGE_DATA := $(ERROR_COVERAGE_DIR)/coverage.dat
COVERAGE_DIR := $(BUILD_DIR)/coverage
COVERAGE_DATA := $(COVERAGE_DIR)/coverage.dat
COVERAGE_SUMMARY := $(COVERAGE_DIR)/coverage-summary.txt

FIFO_COVERAGE_DIR = $(BUILD_DIR)/coverage/$(FIFO_TOP)
FIFO_COVERAGE_BIN = $(FIFO_COVERAGE_DIR)/V$(FIFO_TOP)
FIFO_COVERAGE_DATA = $(FIFO_COVERAGE_DIR)/coverage.dat
VIP_COVERAGE_DIR = $(BUILD_DIR)/coverage/$(VIP_TOP)
VIP_COVERAGE_BIN = $(VIP_COVERAGE_DIR)/V$(VIP_TOP)
VIP_COVERAGE_DATA = $(VIP_COVERAGE_DIR)/coverage.dat
MESH_COVERAGE_DIR = $(BUILD_DIR)/coverage/$(MESH_TOP)
MESH_COVERAGE_BIN = $(MESH_COVERAGE_DIR)/V$(MESH_TOP)
MESH_COVERAGE_DATA = $(MESH_COVERAGE_DIR)/coverage.dat
CDC_COVERAGE_DIR = $(BUILD_DIR)/coverage/$(CDC_TOP)
CDC_COVERAGE_BIN = $(CDC_COVERAGE_DIR)/V$(CDC_TOP)
CDC_COVERAGE_DATA = $(CDC_COVERAGE_DIR)/coverage.dat
CDC_MESH_COVERAGE_DIR = $(BUILD_DIR)/coverage/$(CDC_MESH_TOP)
CDC_MESH_COVERAGE_BIN = $(CDC_MESH_COVERAGE_DIR)/V$(CDC_MESH_TOP)
CDC_MESH_COVERAGE_DATA = $(CDC_MESH_COVERAGE_DIR)/coverage.dat
FULL_COVERAGE_DATA := $(COVERAGE_DIR)/full-coverage.dat
FULL_COVERAGE_SUMMARY := $(COVERAGE_DIR)/full-coverage-summary.txt

MESH_TOP := tb_npu_noc_mesh
MESH_TB := $(THIS_DIR)/tb/$(MESH_TOP).sv
MESH_DIR := $(BUILD_DIR)/verilator/$(MESH_TOP)
MESH_BIN := $(MESH_DIR)/V$(MESH_TOP)

CDC_TOP := tb_npu_noc_pod_cdc
CDC_TB := $(THIS_DIR)/tb/$(CDC_TOP).sv
CDC_DIR := $(BUILD_DIR)/verilator/$(CDC_TOP)
CDC_BIN := $(CDC_DIR)/V$(CDC_TOP)

CDC_MESH_TOP := tb_npu_noc_cdc_mesh
CDC_MESH_TB := $(THIS_DIR)/tb/$(CDC_MESH_TOP).sv
CDC_MESH_DIR := $(BUILD_DIR)/verilator/$(CDC_MESH_TOP)
CDC_MESH_BIN := $(CDC_MESH_DIR)/V$(CDC_MESH_TOP)

VIP_TOP := tb_npu_noc_vip
VIP_TB := $(THIS_DIR)/tb/$(VIP_TOP).sv
VIP_DIR := $(BUILD_DIR)/verilator/$(VIP_TOP)
VIP_BIN := $(VIP_DIR)/V$(VIP_TOP)

.PHONY: preflight lint lint-rtl lint-tb lint-vip-filelist cdc-static synth formal formal-deep coverage sim sim-vip \
	sim-fifo sim-router sim-errors sim-mesh sim-cdc sim-cdc-mesh \
	test closure clean

preflight:
	@command -v "$(VERILATOR)" >/dev/null || { echo "ERROR: Verilator is required" >&2; exit 2; }
	@command -v "$(VERILATOR_COVERAGE)" >/dev/null || { echo "ERROR: verilator_coverage is required" >&2; exit 2; }
	@command -v "$(YOSYS)" >/dev/null || { echo "ERROR: Yosys is required" >&2; exit 2; }
	@command -v "$(PYTHON)" >/dev/null || { echo "ERROR: Python is required" >&2; exit 2; }
	@command -v g++ >/dev/null || { echo "ERROR: g++ is required" >&2; exit 2; }
	@command -v tee >/dev/null || { echo "ERROR: tee is required" >&2; exit 2; }
	@$(PYTHON) -c 'import sys; assert sys.version_info >= (3, 9), "Python 3.9 or newer is required"'
	@$(VERILATOR) --version
	@$(YOSYS) -V

lint: lint-rtl lint-tb lint-vip-filelist

lint-vip-filelist:
	cd $(REPO_ROOT) && $(VERILATOR) $(FLAGS) --lint-only \
		--top-module npu_noc_protocol_checker_vip \
		-f verification/npu/noc/npu_noc_vip.f

cdc-static:
	$(PYTHON) $(THIS_DIR)/scripts/check_cdc_structure.py \
		--repo-root $(REPO_ROOT)

lint-rtl:
	$(VERILATOR) $(FLAGS) --lint-only --top-module npu_noc_lane_router \
		$(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) $(ROUTER_RTL)
	$(VERILATOR) $(FLAGS) --lint-only --top-module npu_noc_mesh \
		$(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) $(ROUTER_RTL) \
		$(FABRIC_RTL) $(MESH_RTL)
	$(VERILATOR) $(FLAGS) --lint-only --top-module npu_noc_cdc_mesh \
		$(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) $(ROUTER_RTL) \
		$(FABRIC_RTL) $(MESH_RTL) $(RESET_SYNC_RTL) $(LEVEL_SYNC_RTL) \
		$(ASYNC_FIFO_RTL) $(POD_CDC_RTL) $(CDC_MESH_RTL)
	$(VERILATOR) $(FLAGS) --lint-only --top-module npu_noc_flit_source_vip \
		$(SOURCE_VIP)
	$(VERILATOR) $(FLAGS) --lint-only --top-module npu_noc_flit_sink_vip \
		$(SINK_VIP)
	$(VERILATOR) $(FLAGS) --lint-only --top-module npu_noc_flit_monitor_vip \
		$(MONITOR_VIP)
	$(VERILATOR) $(FLAGS) --lint-only --top-module npu_noc_protocol_checker_vip \
		$(CHECKER_VIP)

lint-tb:
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(FIFO_TOP) \
		$(FIFO_RTL) $(FIFO_TB)
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(ROUTER_TOP) \
		$(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) $(ROUTER_RTL) \
		$(TB_PKG) $(ROUTER_TB)
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(ERROR_TOP) \
		$(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) $(ROUTER_RTL) \
		$(TB_PKG) $(ERROR_TB)
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(MESH_TOP) \
		$(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) $(ROUTER_RTL) \
		$(FABRIC_RTL) $(MESH_RTL) $(TB_PKG) $(MESH_TB)
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(CDC_TOP) \
		$(POD_NOC_PKG) $(NOC_PKG) $(RESET_SYNC_RTL) $(ASYNC_FIFO_RTL) \
		$(POD_CDC_RTL) $(TB_PKG) $(CDC_TB)
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(CDC_MESH_TOP) \
		$(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) $(ROUTER_RTL) \
		$(FABRIC_RTL) $(MESH_RTL) $(RESET_SYNC_RTL) $(LEVEL_SYNC_RTL) \
		$(ASYNC_FIFO_RTL) $(POD_CDC_RTL) $(CDC_MESH_RTL) $(TB_PKG) \
		$(CDC_MESH_TB)
	$(VERILATOR) $(FLAGS) --lint-only --top-module $(VIP_TOP) \
		$(POD_NOC_PKG) $(TB_PKG) $(SOURCE_VIP) $(SINK_VIP) \
		$(MONITOR_VIP) $(CHECKER_VIP) $(VIP_TB)

synth:
	$(YOSYS) -Q -p 'read_verilog -sv $(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) $(ROUTER_RTL); hierarchy -check -top npu_noc_lane_router; proc; opt; check'
	$(YOSYS) -Q -p 'read_verilog -sv $(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) $(ROUTER_RTL) $(FABRIC_RTL) $(MESH_RTL); hierarchy -check -top npu_noc_mesh; proc; opt; check'
	$(YOSYS) -Q -p 'read_verilog -sv $(POD_NOC_PKG) $(NOC_PKG) $(ASYNC_FIFO_RTL) $(POD_CDC_RTL); hierarchy -check -top npu_noc_pod_cdc; proc; opt; check'

formal:
	cd $(REPO_ROOT) && $(YOSYS) -Q -s \
		verification/npu/noc/formal/vc_fifo.ys
	cd $(REPO_ROOT) && $(YOSYS) -Q -s \
		verification/npu/noc/formal/async_fifo.ys
	cd $(REPO_ROOT) && $(YOSYS) -Q -s \
		verification/npu/noc/formal/router_invariants.ys
	cd $(REPO_ROOT) && $(YOSYS) -Q -s \
		verification/npu/noc/formal/escape_dependency.ys

# Optional workstation/nightly extension. The portable release gate uses the
# four-VC 8-step proof above so closure time remains bounded and reproducible.
formal-deep:
	cd $(REPO_ROOT) && $(YOSYS) -Q -s \
		verification/npu/noc/formal/router_invariants_deep.ys

$(FIFO_BIN): $(FIFO_RTL) $(FIFO_TB)
	@mkdir -p $(FIFO_DIR)
	$(VERILATOR) $(FLAGS) --binary -j $(JOBS) --top-module $(FIFO_TOP) \
		--Mdir $(FIFO_DIR) $(FIFO_RTL) $(FIFO_TB)

$(ROUTER_BIN): $(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) $(ROUTER_RTL) \
		$(TB_PKG) $(ROUTER_TB)
	@mkdir -p $(ROUTER_DIR)
	$(VERILATOR) $(FLAGS) --binary -j $(JOBS) --top-module $(ROUTER_TOP) \
		--Mdir $(ROUTER_DIR) $(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) \
		$(ROUTER_RTL) $(TB_PKG) $(ROUTER_TB)

$(ERROR_BIN): $(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) $(ROUTER_RTL) \
		$(TB_PKG) $(ERROR_TB)
	@mkdir -p $(ERROR_DIR)
	$(VERILATOR) $(FLAGS) --binary -j $(JOBS) --top-module $(ERROR_TOP) \
		--Mdir $(ERROR_DIR) $(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) \
		$(ROUTER_RTL) $(TB_PKG) $(ERROR_TB)

$(ROUTER_COVERAGE_BIN): $(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) \
		$(ROUTER_RTL) $(TB_PKG) $(ROUTER_TB)
	@mkdir -p $(ROUTER_COVERAGE_DIR)
	$(VERILATOR) $(FLAGS) --binary -j $(JOBS) $(COVERAGE_FLAGS) \
		--top-module $(ROUTER_TOP) --Mdir $(ROUTER_COVERAGE_DIR) \
		$(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) $(ROUTER_RTL) \
		$(TB_PKG) $(ROUTER_TB)

$(ERROR_COVERAGE_BIN): $(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) \
		$(ROUTER_RTL) $(TB_PKG) $(ERROR_TB)
	@mkdir -p $(ERROR_COVERAGE_DIR)
	$(VERILATOR) $(FLAGS) --binary -j $(JOBS) $(COVERAGE_FLAGS) \
		--top-module $(ERROR_TOP) --Mdir $(ERROR_COVERAGE_DIR) \
		$(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) $(ROUTER_RTL) \
		$(TB_PKG) $(ERROR_TB)

$(FIFO_COVERAGE_BIN): $(FIFO_RTL) $(FIFO_TB)
	@mkdir -p $(FIFO_COVERAGE_DIR)
	$(VERILATOR) $(FLAGS) --binary -j $(JOBS) $(COVERAGE_FLAGS) \
		--top-module $(FIFO_TOP) --Mdir $(FIFO_COVERAGE_DIR) \
		$(FIFO_RTL) $(FIFO_TB)

$(VIP_COVERAGE_BIN): $(POD_NOC_PKG) $(TB_PKG) $(SOURCE_VIP) $(SINK_VIP) \
		$(MONITOR_VIP) $(CHECKER_VIP) $(VIP_TB)
	@mkdir -p $(VIP_COVERAGE_DIR)
	$(VERILATOR) $(FLAGS) --binary -j $(JOBS) $(COVERAGE_FLAGS) \
		--top-module $(VIP_TOP) --Mdir $(VIP_COVERAGE_DIR) \
		$(POD_NOC_PKG) $(TB_PKG) $(SOURCE_VIP) $(SINK_VIP) \
		$(MONITOR_VIP) $(CHECKER_VIP) $(VIP_TB)

$(MESH_COVERAGE_BIN): $(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) \
		$(ROUTER_RTL) $(FABRIC_RTL) $(MESH_RTL) $(TB_PKG) $(MESH_TB)
	@mkdir -p $(MESH_COVERAGE_DIR)
	$(VERILATOR) $(FLAGS) --binary -j $(JOBS) $(COVERAGE_FLAGS) \
		--top-module $(MESH_TOP) --output-split 20000 \
		--output-split-cfuncs 500 --Mdir $(MESH_COVERAGE_DIR) \
		$(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) $(ROUTER_RTL) \
		$(FABRIC_RTL) $(MESH_RTL) $(TB_PKG) $(MESH_TB)

$(CDC_COVERAGE_BIN): $(POD_NOC_PKG) $(NOC_PKG) $(RESET_SYNC_RTL) \
		$(ASYNC_FIFO_RTL) $(POD_CDC_RTL) $(TB_PKG) $(CDC_TB)
	@mkdir -p $(CDC_COVERAGE_DIR)
	$(VERILATOR) $(FLAGS) --binary -j $(JOBS) $(COVERAGE_FLAGS) \
		--top-module $(CDC_TOP) --Mdir $(CDC_COVERAGE_DIR) \
		$(POD_NOC_PKG) $(NOC_PKG) $(RESET_SYNC_RTL) \
		$(ASYNC_FIFO_RTL) $(POD_CDC_RTL) $(TB_PKG) $(CDC_TB)

$(CDC_MESH_COVERAGE_BIN): $(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) \
		$(ROUTER_RTL) $(FABRIC_RTL) $(MESH_RTL) $(RESET_SYNC_RTL) \
		$(LEVEL_SYNC_RTL) $(ASYNC_FIFO_RTL) $(POD_CDC_RTL) \
		$(CDC_MESH_RTL) $(TB_PKG) $(CDC_MESH_TB)
	@mkdir -p $(CDC_MESH_COVERAGE_DIR)
	$(VERILATOR) $(FLAGS) --binary -j $(JOBS) $(COVERAGE_FLAGS) \
		--top-module $(CDC_MESH_TOP) --output-split 20000 \
		--output-split-cfuncs 500 --Mdir $(CDC_MESH_COVERAGE_DIR) \
		$(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) $(ROUTER_RTL) \
		$(FABRIC_RTL) $(MESH_RTL) $(RESET_SYNC_RTL) $(LEVEL_SYNC_RTL) \
		$(ASYNC_FIFO_RTL) $(POD_CDC_RTL) $(CDC_MESH_RTL) $(TB_PKG) \
		$(CDC_MESH_TB)

$(MESH_BIN): $(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) $(ROUTER_RTL) \
		$(FABRIC_RTL) $(MESH_RTL) $(TB_PKG) $(MESH_TB)
	@mkdir -p $(MESH_DIR)
	$(VERILATOR) $(FLAGS) --binary -j $(JOBS) --top-module $(MESH_TOP) \
		--Mdir $(MESH_DIR) $(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) \
		$(ROUTER_RTL) $(FABRIC_RTL) $(MESH_RTL) $(TB_PKG) $(MESH_TB)

$(CDC_BIN): $(POD_NOC_PKG) $(NOC_PKG) $(RESET_SYNC_RTL) \
		$(ASYNC_FIFO_RTL) $(POD_CDC_RTL) $(TB_PKG) $(CDC_TB)
	@mkdir -p $(CDC_DIR)
	$(VERILATOR) $(FLAGS) --binary -j $(JOBS) --top-module $(CDC_TOP) \
		--Mdir $(CDC_DIR) $(POD_NOC_PKG) $(NOC_PKG) $(RESET_SYNC_RTL) \
		$(ASYNC_FIFO_RTL) $(POD_CDC_RTL) $(TB_PKG) $(CDC_TB)

$(CDC_MESH_BIN): $(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) $(ROUTER_RTL) \
		$(FABRIC_RTL) $(MESH_RTL) $(RESET_SYNC_RTL) $(LEVEL_SYNC_RTL) \
		$(ASYNC_FIFO_RTL) $(POD_CDC_RTL) $(CDC_MESH_RTL) $(TB_PKG) \
		$(CDC_MESH_TB)
	@mkdir -p $(CDC_MESH_DIR)
	$(VERILATOR) $(FLAGS) --binary -j $(JOBS) \
		--top-module $(CDC_MESH_TOP) --output-split 20000 \
		--output-split-cfuncs 500 --Mdir $(CDC_MESH_DIR) \
		$(POD_NOC_PKG) $(NOC_PKG) $(FIFO_RTL) $(ROUTER_RTL) \
		$(FABRIC_RTL) $(MESH_RTL) $(RESET_SYNC_RTL) $(LEVEL_SYNC_RTL) \
		$(ASYNC_FIFO_RTL) $(POD_CDC_RTL) $(CDC_MESH_RTL) $(TB_PKG) \
		$(CDC_MESH_TB)

$(VIP_BIN): $(POD_NOC_PKG) $(TB_PKG) $(SOURCE_VIP) $(SINK_VIP) \
		$(MONITOR_VIP) $(CHECKER_VIP) $(VIP_TB)
	@mkdir -p $(VIP_DIR)
	$(VERILATOR) $(FLAGS) --binary -j $(JOBS) --top-module $(VIP_TOP) \
		--Mdir $(VIP_DIR) $(POD_NOC_PKG) $(TB_PKG) $(SOURCE_VIP) \
		$(SINK_VIP) $(MONITOR_VIP) $(CHECKER_VIP) $(VIP_TB)

sim-fifo: $(FIFO_BIN)
	$(FIFO_BIN)

sim-router: $(ROUTER_BIN)
	$(ROUTER_BIN)

sim-errors: $(ERROR_BIN)
	$(ERROR_BIN)

sim-mesh: $(MESH_BIN)
	$(MESH_BIN) +NOC_SEED=$(NOC_SEED0)
	$(MESH_BIN) +NOC_SEED=$(NOC_SEED1)
	$(MESH_BIN) +NOC_SEED=$(NOC_SEED2)
	$(MESH_BIN) +NOC_SEED=$(NOC_SEED3)

sim-cdc: $(CDC_BIN)
	$(CDC_BIN)

sim-cdc-mesh: $(CDC_MESH_BIN)
	$(CDC_MESH_BIN)

sim-vip: $(VIP_BIN)
	$(VIP_BIN)

sim: sim-vip sim-fifo sim-router sim-errors sim-mesh sim-cdc sim-cdc-mesh

coverage: $(ROUTER_COVERAGE_BIN) $(ERROR_COVERAGE_BIN) \
		$(FIFO_COVERAGE_BIN) $(VIP_COVERAGE_BIN) $(MESH_COVERAGE_BIN) \
		$(CDC_COVERAGE_BIN) $(CDC_MESH_COVERAGE_BIN)
	cd $(ROUTER_COVERAGE_DIR) && ./V$(ROUTER_TOP)
	cd $(ERROR_COVERAGE_DIR) && ./V$(ERROR_TOP)
	cd $(FIFO_COVERAGE_DIR) && ./V$(FIFO_TOP)
	cd $(VIP_COVERAGE_DIR) && ./V$(VIP_TOP)
	cd $(MESH_COVERAGE_DIR) && ./V$(MESH_TOP) +NOC_SEED=$(NOC_SEED0)
	cd $(CDC_COVERAGE_DIR) && ./V$(CDC_TOP)
	cd $(CDC_MESH_COVERAGE_DIR) && ./V$(CDC_MESH_TOP)
	test -s $(ROUTER_COVERAGE_DATA)
	test -s $(ERROR_COVERAGE_DATA)
	test -s $(FIFO_COVERAGE_DATA)
	test -s $(VIP_COVERAGE_DATA)
	test -s $(MESH_COVERAGE_DATA)
	test -s $(CDC_COVERAGE_DATA)
	test -s $(CDC_MESH_COVERAGE_DATA)
	$(VERILATOR_COVERAGE) --write $(COVERAGE_DATA) \
		$(ROUTER_COVERAGE_DATA) $(ERROR_COVERAGE_DATA)
	$(VERILATOR_COVERAGE) --report summary $(COVERAGE_DATA) | \
		tee $(COVERAGE_SUMMARY)
	$(PYTHON) $(COVERAGE_CHECKER) $(COVERAGE_SUMMARY) \
		--minimum line=$(COVERAGE_MIN_LINE) \
		--minimum branch=$(COVERAGE_MIN_BRANCH) \
		--minimum expr=$(COVERAGE_MIN_EXPR) \
		--minimum toggle=$(COVERAGE_MIN_TOGGLE)
	$(VERILATOR_COVERAGE) --write $(FULL_COVERAGE_DATA) \
		$(ROUTER_COVERAGE_DATA) $(ERROR_COVERAGE_DATA) \
		$(FIFO_COVERAGE_DATA) $(VIP_COVERAGE_DATA) \
		$(MESH_COVERAGE_DATA) $(CDC_COVERAGE_DATA) \
		$(CDC_MESH_COVERAGE_DATA)
	$(VERILATOR_COVERAGE) --report summary $(FULL_COVERAGE_DATA) | \
		tee $(FULL_COVERAGE_SUMMARY)
	$(PYTHON) $(COVERAGE_CHECKER) $(FULL_COVERAGE_SUMMARY) \
		--minimum line=$(FULL_COVERAGE_MIN_LINE) \
		--minimum branch=$(FULL_COVERAGE_MIN_BRANCH) \
		--minimum expr=$(FULL_COVERAGE_MIN_EXPR) \
		--minimum toggle=$(FULL_COVERAGE_MIN_TOGGLE)

test: preflight lint cdc-static synth formal sim
	$(MAKE) -C $(REPO_ROOT)/simulator/npu/noc test

closure: test coverage

clean:
	rm -rf $(BUILD_DIR)
