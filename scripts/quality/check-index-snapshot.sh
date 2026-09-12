#!/usr/bin/env bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
export GIT_INDEX_FILE="$(git rev-parse --path-format=absolute --git-path index)"
temporary_worktree="$(mktemp -d "${TMPDIR:-/tmp}/ojd-pre-commit.XXXXXX")"

cleanup() {
  git -C "$repository_root" worktree remove --force "$temporary_worktree" >/dev/null 2>&1 ||
    rm -rf "$temporary_worktree"
}
trap cleanup EXIT INT TERM

tree="$(git write-tree)"
parent=()
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  parent=(-p HEAD)
fi
snapshot="$({
  printf '%s\n' 'pre-commit index snapshot'
} | GIT_AUTHOR_NAME=OpenJoystickDriver GIT_AUTHOR_EMAIL=hooks@localhost \
  GIT_COMMITTER_NAME=OpenJoystickDriver GIT_COMMITTER_EMAIL=hooks@localhost \
  git commit-tree "$tree" "${parent[@]}")"

git worktree add --detach --quiet "$temporary_worktree" "$snapshot"
(
  unset GIT_DIR GIT_INDEX_FILE GIT_PREFIX GIT_WORK_TREE
  cd "$temporary_worktree"
  ./scripts/ojd check fast
)
