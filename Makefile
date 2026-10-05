.PHONY: check

check:
	for script in bin/agent-rig tests/*.sh; do bash -n "$$script" || exit 1; done
	python3 tests/validate.py
	bash tests/install.sh
	bash tests/uninstall.sh
