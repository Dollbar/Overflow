.PHONY: help check npu-gemm-vector-lint npu-gemm-vector-sim \
	npu-gemm-vector-test npu-gemm-vector-waves

help:
	@echo "Repository targets:"
	@echo "  make check                  - run repository consistency checks"
	@echo "  make npu-gemm-vector-lint   - lint the GEMM/vector verification scope"
	@echo "  make npu-gemm-vector-sim    - run GEMM/vector self-checking RTL tests"
	@echo "  make npu-gemm-vector-test   - run all GEMM/vector verification gates"
	@echo "  make npu-gemm-vector-waves  - generate GEMM/vector directed VCD files"

check:
	python3 scripts/check_repository.py

npu-gemm-vector-lint:
	$(MAKE) -C verification/npu/gemm_vector lint

npu-gemm-vector-sim:
	$(MAKE) -C verification/npu/gemm_vector sim

npu-gemm-vector-test:
	$(MAKE) -C verification/npu/gemm_vector test

npu-gemm-vector-waves:
	$(MAKE) -C verification/npu/gemm_vector waves
