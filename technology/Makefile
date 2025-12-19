.PHONY: help sta-interfaces profiles opensta clean

PYTHON ?= python3

help:
	@echo "Technology targets:"
	@echo "  make sta-interfaces - validate profile values and all interface Liberty scenarios"
	@echo "  make profiles       - compare profiles.yaml with Liberty timing arcs"
	@echo "  make opensta        - parse, link, constrain, and report all scenarios"
	@echo "  make clean          - remove generated interface-STA output"

sta-interfaces: profiles opensta

profiles:
	$(PYTHON) -m pytest -q -s -o cache_dir=work/.pytest_cache interfaces/tests/test_interface_liberty_profiles.py

opensta:
	$(PYTHON) scripts/run_sta_interfaces.py

clean:
	rm -rf work
