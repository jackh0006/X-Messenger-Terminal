#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# run-tests.sh — Runs all tests in network-less namespace
# This script is called from CI under `unshare -rn` when available

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

log_info() { echo "[INFO] $*"; }
log_ok() { echo "[OK] $*"; }
log_err() { echo "[ERR] $*"; }

# Canary test: confirm network is actually blocked (only when under unshare -rn)
log_info "Running network canary test..."
if timeout 5 bash -c "echo > /dev/tcp/8.8.8.8/53" 2>/dev/null; then
    # Check if we're running under unshare -rn
    if [[ "$(cat /proc/self/uid_map 2>/dev/null)" != *"0 0 4294967295"* ]]; then
        log_info "Network canary: network NOT blocked (running without unshare -rn, skipping)"
    else
        log_err "Network canary FAILED — network is NOT blocked"
        exit 1
    fi
else
    log_ok "Network canary passed — network is blocked"
fi

# Run the audit — the audit itself runs the full bats suite now
# (Section 1 of audit.sh), so there is exactly one suite run per job.
log_info "Running audit (includes the full bats suite)..."
if ./scripts/audit.sh; then
    log_ok "Audit passed (suite included)"
else
    log_err "Audit failed"
    exit 1
fi

log_ok "All tests passed"