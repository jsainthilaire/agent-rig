# Repository Guidelines

## Project Structure & Module Organization

- `bin/agent-rig` implements the shared installation lifecycle: provider selection, manifests, backups, locks, and rollback.
- `providers/codex/` and `providers/claude/` contain native agent definitions, workflows, presets, templates, model guidance, and provider adapters (`provider.sh`). Keep native format handling inside its provider.
- `tests/` contains shared validation and installer checks; `tests/codex/` and `tests/claude/` cover provider behavior. Claude benchmark cases and fixtures live in `providers/claude/benchmarks/`.
- `README.md` documents installation, customization, and development.

## Build, Test, and Development Commands

No compilation step is required. The installer needs Bash 3.2+ and standard Unix utilities; development checks also require Make and Python 3.11+.

- `make check`: run shell syntax checks, source validation, installer regressions, and offline benchmark checks.
- `python3 tests/validate.py`: validate agent definitions, preset references, Markdown links, and source formatting.
- `python3 tests/installer.py`: check confirmation prompts and terminal presentation in disposable destinations.
- `bash tests/codex/install.sh`: run focused Codex installation checks; use the other scripts under `tests/` for removal, migration, and Claude behavior.
- `bin/agent-rig install --provider codex --target /path/to/project --dry-run`: preview installation without writing; the target must exist.

## Coding Style & Naming Conventions

Match existing code: four-space indentation in Bash and Python, tabs for Make recipes, and `snake_case` functions and variables. Keep shell code compatible with Bash 3.2, quote path expansions, and never source project data. Use lowercase role/workflow filenames and `.preset` files. Preserve LF endings, final newlines, and whitespace-clean lines. No dedicated formatter or linter is configured; source validation enforces formatting checks.

## Testing Guidelines

Tests use Bash assertion helpers, Python assertions, and `unittest`; no numerical coverage threshold is configured. Name Python test methods `test_*` and organize shell regressions by behavior. Add regression cases for changed behavior, especially preservation of user configuration, provider isolation, conflict handling, and rollback. Use disposable fixtures, never actual provider installations. Run `make check` before submitting; offline checks do not establish live delegation or model access.

## Commit & Pull Request Guidelines

Existing commits use short, lowercase imperative subjects, such as `improve installer` and `add claude support`. Follow that style with a specific scope. PRs should explain the problem, resulting behavior, affected providers, and checks run. Link relevant issues and include terminal output or screenshots when presentation changes. Update documentation alongside user-facing behavior changes.
