#!/usr/bin/env bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
unset GIT_DIR GIT_INDEX_FILE GIT_PREFIX GIT_WORK_TREE
zero_oid="$(printf '%040d' 0)"
temporary_worktree=""

cleanup() {
  if [[ -n "$temporary_worktree" ]]; then
    git -C "$repository_root" worktree remove --force "$temporary_worktree" >/dev/null 2>&1 ||
      rm -rf "$temporary_worktree"
  fi
}
trap cleanup EXIT INT TERM

declare -A validated=()
while read -r _local_ref local_oid _remote_ref _remote_oid; do
  [[ "$local_oid" == "$zero_oid" ]] && continue

  commit="$(git rev-parse --verify "$local_oid^{commit}")" || {
    echo "Cannot validate pushed object $local_oid as a commit." >&2
    exit 1
  }
  [[ -n "${validated[$commit]:-}" ]] && continue

  temporary_worktree="$(mktemp -d "${TMPDIR:-/tmp}/ojd-pre-push.XXXXXX")"
  git worktree add --detach --quiet "$temporary_worktree" "$commit"
  mkdir -p "$temporary_worktree/.build"
  if [[ -d "$repository_root/.build/schema-validator" ]]; then
    ln -s "$repository_root/.build/schema-validator" \
      "$temporary_worktree/.build/schema-validator"
  fi
  (
    unset GIT_DIR GIT_INDEX_FILE GIT_PREFIX GIT_WORK_TREE
    cd "$temporary_worktree"
    source scripts/platform/environment.sh
    just check
  )
  git -C "$repository_root" worktree remove --force "$temporary_worktree"
  temporary_worktree=""
  validated[$commit]=1
done
