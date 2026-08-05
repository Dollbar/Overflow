VERILATOR ?= verilator
PYTHON ?= python3
JOBS ?= 4

THIS_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(THIS_DIR)/../../..)
BUILD_DIR := $(THIS_DIR)/build
FILELIST := $(THIS_DIR)/npu_pod_noc_system.f
FILELIST_ENTRIES := $(shell sed -e '/^[[:space:]]*$$/d' $(FILELIST))
RTL_DEPS := $(addprefix $(REPO_ROOT)/,$(FILELIST_ENTRIES))
TB_PKG := $(THIS_DIR)/pkg/npu_pod_noc_system_tb_pkg.sv
PROTOCOL_CHECKER := \
	$(REPO_ROOT)/verification/npu/common/vip/npu_ready_valid_protocol_checker.sv
TB := $(THIS_DIR)/tb/tb_npu_2x4_pod_noc_system.sv
STRUCTURE_CHECKER := $(THIS_DIR)/scripts/check_joint_structure.py
TOP := tb_npu_2x4_pod_noc_system
RTL_TOP := npu_2x4_pod_noc_system
SIM_DIR := $(BUILD_DIR)/verilator/$(TOP)
SIM_BIN := $(SIM_DIR)/V$(TOP)
FLAGS := --language 1800-2017 -Wall --timing --no-sched-zero-delay --assert

.PHONY: preflight structure lint lint-rtl lint-tb sim closure clean

preflight:
	@command -v "$(VERILATOR)" >/dev/null || { \
		echo "ERROR: VERILATOR='$(VERILATOR)' is not executable or on PATH" >&2; exit 2; }
	@command -v g++ >/dev/null || { echo "ERROR: g++ is required" >&2; exit 2; }
	@$(PYTHON) -c 'import sys; assert sys.version_info >= (3, 9), "Python 3.9 or newer is required"'
	@$(VERILATOR) --version

lint: lint-rtl lint-tb

structure:
	$(PYTHON) $(STRUCTURE_CHECKER) --repo-root $(REPO_ROOT)

lint-rtl:
	cd $(REPO_ROOT) && $(VERILATOR) $(FLAGS) --lint-only \
		--top-module $(RTL_TOP) -f verification/npu/pod_noc/npu_pod_noc_system.f

lint-tb:
	cd $(REPO_ROOT) && $(VERILATOR) $(FLAGS) --lint-only \
		--top-module $(TOP) -f verification/npu/pod_noc/npu_pod_noc_system.f \
		verification/npu/pod_noc/pkg/npu_pod_noc_system_tb_pkg.sv \
		verification/npu/common/vip/npu_ready_valid_protocol_checker.sv \
		verification/npu/pod_noc/tb/tb_npu_2x4_pod_noc_system.sv

$(SIM_BIN): $(FILELIST) $(RTL_DEPS) $(TB_PKG) $(PROTOCOL_CHECKER) $(TB)
	@mkdir -p $(SIM_DIR)
	cd $(REPO_ROOT) && $(VERILATOR) $(FLAGS) --binary -j $(JOBS) \
		--top-module $(TOP) --Mdir $(SIM_DIR) \
		-f verification/npu/pod_noc/npu_pod_noc_system.f \
		verification/npu/pod_noc/pkg/npu_pod_noc_system_tb_pkg.sv \
		verification/npu/common/vip/npu_ready_valid_protocol_checker.sv \
		verification/npu/pod_noc/tb/tb_npu_2x4_pod_noc_system.sv

sim: $(SIM_BIN)
	$(SIM_BIN)

closure: preflight structure lint sim

clean:
	rm -rf $(BUILD_DIR)
