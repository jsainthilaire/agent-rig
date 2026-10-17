.PHONY: check

check:
	for script in bin/agent-rig bin/*.sh providers/*/provider.sh providers/*/review.sh tests/*.sh tests/*/*.sh; do bash -n "$$script" || exit 1; done
	python3 tests/validate.py
	python3 tests/reviewers.py
	python3 tests/installer.py
	python3 tests/models.py
	bash tests/update.sh
	bash tests/codex/install.sh
	bash tests/codex/uninstall.sh
	bash tests/codex/migration.sh
	bash tests/claude/install.sh
	bash tests/claude/models.sh
	python3 providers/claude/benchmarks/evaluate.py --check
	python3 tests/claude/benchmarks.py
