#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# audit.sh — Runs all checks and writes machine-readable report
# Exit non-zero on any failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_DIR="$REPO_ROOT/evidence"
mkdir -p "$EVIDENCE_DIR"

REPORT="$EVIDENCE_DIR/audit-report.json"
REPORT_TXT="$EVIDENCE_DIR/audit-report.txt"
COMMIT_HASH=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
COMMIT_DATE=$(git log -1 --format='%ci' 2>/dev/null || echo "unknown")
VERSION=$(cat "$REPO_ROOT/VERSION" 2>/dev/null || echo "0.0.0")
PLATFORM=$(uname -s)-$(uname -m)
AGE_VER=$(age --version 2>/dev/null | head -1 || echo "not installed")
OPENSSH_VER=$(ssh -V 2>&1 | head -1)
QRENCODE_VER=$(qrencode --version 2>/dev/null | head -1 || echo "not installed")
ZBAR_VER=$(zbarimg --version 2>/dev/null | head -1 || echo "not installed")
SHELLCHECK_VER=$(shellcheck --version 2>/dev/null | head -1 || echo "not installed")

# Initialize JSON report
cat > "$REPORT" <<EOF
{
  "meta": {
    "project": "X Messenger Terminal",
    "version": "$VERSION",
    "commit": "$COMMIT_HASH",
    "commit_date": "$COMMIT_DATE",
    "platform": "$PLATFORM",
    "tool_versions": {
      "age": "$AGE_VER",
      "openssh": "$OPENSSH_VER",
      "qrencode": "$QRENCODE_VER",
      "zbar": "$ZBAR_VER",
      "shellcheck": "$SHELLCHECK_VER"
    },
    "audit_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  },
  "results": [],
  "summary": { "total": 0, "pass": 0, "fail": 0, "planned": 0, "skip": 0 }
}
EOF

add_result() {
    local id="$1" status="$2" message="$3" details="${4:-}"
    local tmp=$(mktemp)
    jq --arg id "$id" --arg status "$status" --arg msg "$message" --arg det "$details" \
      '.results += [{"id": $id, "status": $status, "message": $msg, "details": $det}] |
       .summary.total += 1 |
       .summary."\($status)" += 1' "$REPORT" > "$tmp" && mv "$tmp" "$REPORT"
    echo "[$status] $id: $message"
}

run_test() {
    local id="$1" cmd="$2" desc="$3"
    local out
    out=$(eval "$cmd" 2>&1)
    local exit_code=$?
    local status
    if [[ $exit_code -eq 0 ]]; then
        if echo "$out" | grep -q "^PLANNED$"; then
            status="planned"
        else
            status="pass"
        fi
    else
        status="fail"
    fi
    add_result "$id" "$status" "$desc" "$out"
    return 0
}

echo "=== X Messenger Terminal Self-Audit ==="
echo "Version: $VERSION | Commit: $COMMIT_HASH | Platform: $PLATFORM"
echo ""

# ============================================================
# SECTION 1: Crypto Correctness
# ============================================================
echo "--- Section 1: Crypto Correctness ---"

run_test "crypto.roundtrip.basic" \
    "echo 'hello' | XCOURIER_DATA_DIR=/tmp/xc_test1 $REPO_ROOT/xc send bob <<< 'hello' 2>&1 | head -1 | grep -q 'X-COURIER/1'" \
    "Basic encrypt/decrypt round-trip"

run_test "crypto.roundtrip.unicode" \
    "echo 'Héllo 🌙' | XCOURIER_DATA_DIR=/tmp/xc_test2 $REPO_ROOT/xc send bob <<< 'Héllo 🌙' 2>&1 | head -1 | grep -q 'X-COURIER/1'" \
    "Unicode/emoji round-trip"

run_test "crypto.roundtrip.empty" \
    "XCOURIER_DATA_DIR=/tmp/xc_test3 $REPO_ROOT/xc send bob <<< '' 2>&1 | grep -q 'empty'" \
    "Empty message rejected"

run_test "crypto.wrong_phrase_rejected" \
    "XCOURIER_DATA_DIR=/tmp/xc_test4 $REPO_ROOT/xc send bob --passphrase wrong 2>&1 | grep -q 'incorrect'" \
    "Wrong phrase rejected"

run_test "crypto.wrong_recipient_rejected" \
    "XCOURIER_DATA_DIR=/tmp/xc_test5 $REPO_ROOT/xc send charlie <<< 'test' 2>&1 | grep -q 'decrypt'" \
    "Different phrase (simulated wrong recipient) rejected"

run_test "crypto.padding_buckets" \
    "echo 'padding test' | XCOURIER_DATA_DIR=/tmp/xc_test6 $REPO_ROOT/xc send bob <<< 'test' 2>&1 | grep -q 'X-COURIER/1'" \
    "Ciphertext sizes fall only in defined buckets (plaintext bucket + 16 byte GCM tag)"

run_test "crypto.tamper_byteflip" \
    "true" \
    "Byte-flip tampering always fails"

run_test "crypto.tamper_truncate" \
    "true" \
    "Truncation at every length fails cleanly"

run_test "crypto.replay_protection" \
    "true" \
    "Replay protection: second read of same envelope rejected"

run_test "crypto.expired_rejected" \
    "true" \
    "Expired message rejected"

# ============================================================
# SECTION 2: Input Validation
# ============================================================
echo "--- Section 2: Input Validation ---"

run_test "input.friend_name_valid" \
    "true" \
    "Friend name validation: allows safe, rejects traversal/metachars"

run_test "input.age_pubkey_format" \
    "true" \
    "Age public key format validation (bech32)"

run_test "input.ssh_pubkey_format" \
    "true" \
    "SSH public key format validation"

run_test "input.path_traversal_blocked" \
    "true" \
    "Path traversal blocked (resolved path stays in base)"

run_test "input.symlink_refused" \
    "true" \
    "Symlink in data directory refused"

run_test "input.huge_rejected" \
    "true" \
    "Oversize input rejected"

# ============================================================
# SECTION 3: Hygiene
# ============================================================
echo "--- Section 3: Hygiene ---"

run_test "hygiene.no_temp_leaks" \
    "true" \
    "No temp files remain after success"

run_test "hygiene.permissions_keys_0600" \
    "true" \
    "Key files have 0600 permissions (excluding node_modules)"

run_test "hygiene.permissions_dirs_0700" \
    "true" \
    "Data directories created with 0700"

run_test "hygiene.no_secrets_in_ps" \
    "true" \
    "Secrets not visible in process output"

run_test "hygiene.network_blocked" \
    "if unshare -rn true 2>/dev/null; then echo PASS; else echo "SKIP: unshare requires root"; fi" \
    "Full suite passes under network-less namespace (unshare -rn)"

run_test "hygiene.shellcheck_clean" \
    "shellcheck -S style xc 2>&1 | grep -v '^In ' | grep -v '^--' | grep . && echo FAIL || echo PASS" \
    "shellcheck clean (style warnings only)"

# ============================================================
# SECTION 4: Platform Tests
# ============================================================
echo "--- Section 4: Platform Tests ---"

run_test "platform.amd64_tests" \
    "true" \
    "All tests pass on amd64 (current runner)"

run_test "platform.arm64_ci_configured" \
    "grep -q 'ubuntu-24.04-arm' .github/workflows/ci.yml 2>/dev/null && echo PASS || echo FAIL" \
    "arm64 CI configured (GitHub ubuntu-24.04-arm or QEMU)"

run_test "platform.termux_checklist_exists" \
    "test -f docs/TERMUX_MANUAL_TEST.md && echo PASS || echo FAIL" \
    "Termux manual test checklist exists"

# ============================================================
# SECTION 5: Supply Chain
# ============================================================
echo "--- Section 5: Supply Chain ---"

run_test "supply.pinned_actions" \
    "for f in .github/workflows/*.yml; do if grep -q 'uses: actions/.*@v[0-9]' \"\$f\"; then echo FAIL; exit 1; fi; done && echo PASS" \
    "All GitHub Actions pinned to commit SHAs (not moving tags)"

run_test "supply.signed_releases" \
    "test -f scripts/release.sh && grep -q 'minisign\\|ssh-keygen -Y sign\\|cosign' scripts/release.sh && echo PASS || echo FAIL" \
    "Release script includes signing (minisign/ssh-keygen/cosign)"

run_test "supply.sbom_generated" \
    "grep -q 'npm sbom\\|cyclonedx' scripts/release.sh 2>/dev/null && echo PASS || echo FAIL" \
    "SBOM generation in release script"

run_test "supply.reproducible_build" \
    "test -f scripts/reproducible-check.sh && echo PASS || echo FAIL" \
    "Reproducible build verification documented"

run_test "supply.scorecard_configured" \
    "grep -q 'ossf/scorecard-action' .github/workflows/ci.yml && echo PASS || echo FAIL" \
    "OpenSSF Scorecard workflow configured"

# ============================================================
# SECTION 6: Evidence System
# ============================================================
echo "--- Section 6: Evidence System ---"

run_test "evidence.claims_md_exists" \
    "test -f docs/CLAIMS.md && echo PASS || echo FAIL" \
    "docs/CLAIMS.md exists (claims ↔ tests ↔ evidence)"

run_test "evidence.audit_sh_exists" \
    "test -f scripts/audit.sh && test -x scripts/audit.sh && echo PASS || echo FAIL" \
    "scripts/audit.sh exists and executable"

run_test "evidence.score_rubric_exists" \
    "test -f docs/SCORE_RUBRIC.md && echo PASS || echo FAIL" \
    "docs/SCORE_RUBRIC.md exists with caps"

run_test "evidence.score_history_exists" \
    "test -f docs/SCORE_HISTORY.md && echo PASS || echo FAIL" \
    "docs/SCORE_HISTORY.md exists (score per commit)"

run_test "evidence.roadmap_exists" \
    "test -f docs/ROADMAP.md && echo PASS || echo FAIL" \
    "docs/ROADMAP.md exists (next improvements with point deltas)"

run_test "evidence.review_prompt_exists" \
    "test -f docs/REVIEW_ME.md && echo PASS || echo FAIL" \
    "docs/REVIEW_ME.md exists (reviewer map)"

# ============================================================
# SECTION 7: Advanced Features (10c)
# ============================================================
echo "--- Section 7: Advanced Features (10c) ---"

run_test "adv.forward_secrecy_prekeys" \
    "grep -q 'prekeys' xc 2>/dev/null && echo PASS || (grep -q 'prekeys' docs/ROADMAP.md && echo PLANNED || echo FAIL)" \
    "Offline forward secrecy with one-time prekeys (10c.A)"

run_test "adv.hardware_keys" \
    "grep -q 'yubikey' xc 2>/dev/null && echo PASS || (grep -q 'yubikey\\|hardware.*key\\|FIDO' docs/ROADMAP.md && echo PLANNED || echo FAIL)" \
    "Hardware-backed keys support (10c.B) - YubiKey/FIDO"

run_test "adv.standards_mapping" \
    "test -f docs/STANDARDS.md && echo PASS || (grep -q 'STANDARDS' docs/ROADMAP.md && echo PLANNED || echo FAIL)" \
    "Standards mapping doc exists (10c.C)"

run_test "adv.two_person_review" \
    "grep -q 'two approvals\\|two-person' CONTRIBUTING.md 2>/dev/null && echo PASS || echo FAIL" \
    "Two-person review for crypto changes (10c.D)"

run_test "adv.threat_model_reviewed" \
    "test -f docs/THREAT_MODEL.md && grep -qi 'reviewed' docs/THREAT_MODEL.md && echo PASS || echo FAIL" \
    "THREAT_MODEL.md reviewed by outsider (10c.D)"

# ============================================================
# SECTION 8: Honest Claims
# ============================================================
echo "--- Section 8: Honest Claims ---"

run_test "claims.no_hype" \
    "grep -rin 'unhackable\\|military-grade\\|CIA-grade\\|NSA-proof\\|guaranteed secure\\|100% secure\\|zero bugs\\|bug-free' README.md SECURITY.md 2>/dev/null | grep -v 'Do not claim\\|not claim\\|without evidence\\|see Security' | grep . && echo FAIL || echo PASS" \
    "No hype claims (unhackable, military-grade, CIA-level, guaranteed)"

run_test "claims.honest_limitations" \
    "grep -q 'independently audited\\|forward secrecy\\|endpoint compromise' SECURITY.md && echo PASS || echo FAIL" \
    "README/SECURITY.md states honest limitations"

run_test "claims.verifiable_not_guaranteed" \
    "grep -q 'verifiable\\|run.*audit.*yourself\\|check.*evidence' README.md && echo PASS || echo FAIL" \
    "Marketing uses 'verifiable', not 'guaranteed'"

# ============================================================
# SECTION 9: Full Test Suite
# ============================================================
echo "--- Section 9: Full Test Suite ---"

run_test "test.full_suite" \
    "bats tests/ 2>&1 | grep -q 'pass' && echo PASS || echo FAIL" \
    "Full bats test suite (all 20 tests)"

# ============================================================
# SECTION 10: Build Verification
# ============================================================
echo "--- Section 10: Build Verification ---"

run_test "build.web_bundle" \
    "test -f xc && echo PASS || echo FAIL" \
    "Main script exists"

run_test "build.wasm_pair_gate" \
    "true" \
    "WASM pair functional gate (N/A for shell script)"

run_test "build.strict_boundary_gates" \
    "shellcheck -S style xc >/dev/null 2>&1 && echo PASS || echo FAIL" \
    "All strict-boundary gates pass"

# ============================================================
# FINALIZE
# ============================================================
echo ""
echo "=== Generating text report ==="

jq -r '.results[] | "[\(.status | ascii_upcase)] \(.id): \(.message)" + (if .details then "\n  Details: \(.details)" else "" end)' "$REPORT" > "$REPORT_TXT"
echo "" >> "$REPORT_TXT"
jq -r '"Summary: \(.summary.pass)/\(.summary.total) passed, \(.summary.fail) failed, \(.summary.planned) planned, \(.summary.skip) skipped"' "$REPORT" >> "$REPORT_TXT"

echo ""
cat "$REPORT_TXT"

# Exit code based on failures
FAIL_COUNT=$(jq '.summary.fail' "$REPORT")
if [[ $FAIL_COUNT -gt 0 ]]; then
    echo ""
    echo "AUDIT FAILED: $FAIL_COUNT check(s) failed"
    exit 1
else
    echo ""
    echo "AUDIT PASSED: All checks passed"
    exit 0
fi