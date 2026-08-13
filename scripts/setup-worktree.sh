#!/usr/bin/env bash

set -euo pipefail

for command_name in git lake make python3; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

repository_root=$(git rev-parse --show-toplevel)
git_common_dir=$(git rev-parse --path-format=absolute --git-common-dir)
cd "$repository_root"

if command -v shasum >/dev/null 2>&1; then
  manifest_key=$(shasum -a 256 lake-manifest.json | awk '{print $1}')
else
  manifest_key=$(sha256sum lake-manifest.json | awk '{print $1}')
fi

cache_root="$git_common_dir/codex-cache/lake-packages/$manifest_key"
shared_packages="$cache_root/packages"
ready_file="$cache_root/.ready"
lock_dir="$cache_root/.setup-lock"

mkdir -p "$cache_root" "$shared_packages" .lake

if [[ -e .lake/packages && ! -L .lake/packages ]]; then
  if find .lake/packages -mindepth 1 -print -quit | grep -q .; then
    echo ".lake/packages already contains data; refusing to replace it" >&2
    exit 1
  fi
  rmdir .lake/packages
fi

if [[ -L .lake/packages ]]; then
  current_target=$(readlink .lake/packages)
  if [[ "$current_target" != "$shared_packages" ]]; then
    unlink .lake/packages
  fi
fi

if [[ ! -e .lake/packages ]]; then
  ln -s "$shared_packages" .lake/packages
fi

if [[ ! -f "$ready_file" ]]; then
  acquired_lock=false
  for _ in $(seq 1 300); do
    if mkdir "$lock_dir" 2>/dev/null; then
      acquired_lock=true
      break
    fi
    if [[ -f "$ready_file" ]]; then
      break
    fi
    sleep 0.2
  done

  if [[ "$acquired_lock" == true ]]; then
    release_lock() {
      rmdir "$lock_dir" 2>/dev/null || true
    }
    trap release_lock EXIT INT TERM
    lake --keep-toolchain update
    touch "$ready_file"
    release_lock
    trap - EXIT INT TERM
  elif [[ ! -f "$ready_file" ]]; then
    echo "Timed out waiting for the shared Lake package cache lock: $lock_dir" >&2
    exit 1
  fi
fi

lake build --wfail
