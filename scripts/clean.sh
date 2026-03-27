#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${repo_root}/build"

echo "Cleaning build artifacts in ${build_dir}..."
rm -rf "${build_dir}"
echo "Build artifacts removed."

echo ""
echo "Logs live outside the repo at:"
echo "  ~/.local/state/project-switcher/logs"
echo "To remove logs, run:"
echo "  rm -rf ~/.local/state/project-switcher/logs"
