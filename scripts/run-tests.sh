#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# run-tests.sh — Runs all tests in network-less namespace
# This script is called from CI under `unshare -rn`

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log_info() { echo "[INFO] $*"; }
log_ok() { echo "[OK] $*"; }
log_err() { echo "[ERR] $*"; }

# Canary test: confirm network is actually blocked
log_info "Running network canary test..."
if timeout 5 bash -c "echo > /dev/tcp/8.8.8.8/53" 2>/dev/null; then
    log_err "Network canary FAILED — network is NOT blocked"
    exit 1
fi
log_ok "Network canary passed — network is blocked"

# Run bats tests
log_info "Running bats tests..."
if bats tests/; then
    log_ok "All bats tests passed"
else
    log_err "Some bats tests failed"
    exit 1
fi

# Run audit script (generates evidence)
log_info "Running audit script..."
if ./scripts/audit.sh; then
    log_ok "Audit passed"
else
    log_err "Audit failed"
    exit 1
fi

log_ok "All tests passed in network-less namespace"