# Every bedrock repo shares this file. Each language adds `.just/<language>.just`,
# so `just <task>` runs the task for every language the repo has. Put project
# recipes in `project.just`; a recipe there named `project-<task>`, such as
# `project-verify`, runs after the languages' <task>.

set shell := ["bash", "-euo", "pipefail", "-c"]

mod? typescript ".just/typescript.just"
mod? rust ".just/rust.just"
mod? swift ".just/swift.just"
mod? cpp ".just/cpp.just"
mod? jvm ".just/jvm.just"
mod? go ".just/go.just"

import? "project.just"

languages := "typescript rust swift cpp jvm go"

# List the recipes.
default:
    @just --list --list-submodules

# Install the pinned tools and point git at .githooks.
setup: (each "setup")
    @if [[ -z "${CI:-}" ]]; then git config core.hooksPath .githooks; fi

# Format every file in place.
format: (each "format")

# Fail if a file is not formatted.
format-check: (each "format-check")

# Type-check or build without running anything.
typecheck: (each "typecheck")

# Run every linter.
lint: lint-markdown lint-hooks (each "lint")

# Apply the fixes the linters can make.
lint-fix: lint-markdown-fix (each "lint-fix")

# Run the tests.
test: (each "test")

# Report what the linters cannot see: suppressions, foreign tools, and drift.
guard: guard-base (each "guard")

# Run every check CI runs.
verify: guard-base lint-markdown lint-hooks (each "verify")

# The checks the pre-commit hook runs.
pre-commit: guard-base (each "pre-commit")

[private]
each recipe:
    #!/usr/bin/env bash
    set -euo pipefail
    for language in {{ languages }}; do
        if [[ -f ".just/$language.just" ]]; then
            {{ just_executable() }} "$language::{{ recipe }}"
        fi
    done
    # project.just extends a task with a recipe named project-<task>.
    case " $({{ just_executable() }} --summary) " in
        *" project-{{ recipe }} "*) {{ just_executable() }} "project-{{ recipe }}" ;;
    esac

[private]
lint-markdown *args:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -x node_modules/.bin/markdownlint-cli2 ]]; then
        exec bun run markdownlint-cli2 {{ args }}
    elif command -v markdownlint-cli2 >/dev/null; then
        exec markdownlint-cli2 {{ args }}
    elif [[ -n "${CI:-}" ]]; then
        echo "markdownlint-cli2 is not installed" >&2
        exit 1
    fi
    echo "Skipped Markdown: markdownlint-cli2 is not installed. CI runs it."

[private]
lint-markdown-fix: (lint-markdown "--fix")

[private]
lint-hooks:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v shellcheck >/dev/null; then
        exec shellcheck .githooks/*
    elif [[ -n "${CI:-}" ]]; then
        echo "shellcheck is not installed" >&2
        exit 1
    fi
    echo "Skipped hooks: shellcheck is not installed. CI runs it."

[private]
guard-base:
    #!/usr/bin/env bash
    set -euo pipefail
    status=0
    for agent in CLAUDE.md GEMINI.md; do
        if [[ "$(readlink "$agent" || true)" != AGENTS.md ]]; then
            echo "$agent: make it a symlink to AGENTS.md" >&2
            status=1
        fi
    done
    for path in .husky .lefthook.yml .pre-commit-config.yaml .simple-git-hooks.json lefthook.yaml lefthook.yml Makefile; do
        if [[ -e "$path" ]]; then
            echo "$path: replaced by justfile and .githooks; move what it still does into project.just" >&2
            status=1
        fi
    done
    if [[ -z "${CI:-}" && "$(git config core.hooksPath || true)" != .githooks ]]; then
        echo "git hooks are off: run just setup" >&2
        status=1
    fi
    exit "$status"
