.PHONY: help sta-interfaces sta-kd28 profiles opensta kd28-profiles kd28-opensta clean

PYTHON ?= python3

help:
	@echo "Technology targets:"
	@echo "  make sta-interfaces - validate profile values and all interface Liberty scenarios"
	@echo "  make sta-kd28       - validate KD28 SRAM profile values and Liberty scenarios"
	@echo "  make profiles       - compare profiles.yaml with Liberty timing arcs"
	@echo "  make opensta        - parse, link, constrain, and report all scenarios"
	@echo "  make clean          - remove generated interface-STA output"

sta-interfaces: profiles opensta

sta-kd28: kd28-profiles kd28-opensta

profiles:
	$(PYTHON) -m pytest -q -s -o cache_dir=work/.pytest_cache interfaces/tests/test_interface_liberty_profiles.py

opensta:
	$(PYTHON) scripts/run_sta_interfaces.py

kd28-profiles:
	$(PYTHON) -m pytest -q -s -o cache_dir=work/.pytest_cache kd28/tests/test_kd28_sram_library.py

kd28-opensta:
	$(PYTHON) scripts/run_sta_kd28.py

clean:
	rm -rf work
