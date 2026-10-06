.PHONY: check

check:
	for script in bin/agent-rig providers/*/provider.sh tests/*.sh tests/*/*.sh; do bash -n "$$script" || exit 1; done
	python3 tests/validate.py
	bash tests/codex/install.sh
	bash tests/codex/uninstall.sh
	bash tests/codex/migration.sh
	bash tests/claude/install.sh
	bash tests/claude/models.sh
	python3 providers/claude/benchmarks/evaluate.py --check
	python3 tests/claude/benchmarks.py
