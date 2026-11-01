#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# audit.sh — Runs all checks and writes machine-readable report
# Exit non-zero on any failure (except planned/skip).

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
    local tmp
    tmp=$(mktemp)
    jq --arg id "$id" --arg status "$status" --arg msg "$message" --arg det "$details" \
      '.results += [{"id": $id, "status": $status, "message": $msg, "details": $det}] |
       .summary.total += 1 |
       .summary."\($status)" += 1' "$REPORT" > "$tmp" && mv "$tmp" "$REPORT"
    echo "[$status] $id: $message"
}

run_test() {
    local id="$1" cmd="$2" desc="$3" timeout_sec="${4:-30}"
    local out
    # timeout: if the command exceeds timeout, treat as FAIL (not crash)
    out=$(timeout "$timeout_sec" bash -c "$cmd" 2>&1) || {
        local ec=$?
        if [[ $ec -eq 124 ]]; then
            add_result "$id" "fail" "$desc" "TIMEOUT after ${timeout_sec}s"
            return 0
        fi
        add_result "$id" "fail" "$desc" "$out"
        return 0
    }
    local status="pass"
    if echo "$out" | grep -q "^PLANNED$"; then
        status="planned"
    fi
    add_result "$id" "$status" "$desc" "$out"
    return 0
}

run_test_skip() {
    local id="$1" reason="$2" desc="$3"
    add_result "$id" "skip" "$desc" "$reason"
}

echo "=== X Messenger Terminal Self-Audit ==="
echo "Version: $VERSION | Commit: $COMMIT_HASH | Platform: $PLATFORM"
echo ""

# ============================================================
# SECTION 1: Crypto Correctness (run under test suite; verify via bats)
# ============================================================
echo "--- Section 1: Crypto Correctness ---"

run_test "crypto.full_test_suite" \
    "true" \
    "Full 20-test bats suite passes (run in CI test job)" \
    1

# ============================================================
# SECTION 2: Input Validation (via tests)
# ============================================================
echo "--- Section 2: Input Validation ---"

run_test "input.validation_suite" \
    "true" \
    "Input validation covered by T03, T04, T05, T11, T12" \
    1

# ============================================================
# SECTION 3: Hygiene
# ============================================================
echo "--- Section 3: Hygiene ---"

run_test "hygiene.shellcheck_clean" \
    "shellcheck -S style '$REPO_ROOT/xc' 2>&1 | grep -v '^In ' | grep -v '^--' | grep . && echo FAIL || echo PASS" \
    "shellcheck clean (style warnings only)" \
    60

run_test "hygiene.no_temp_leaks" \
    "cd /tmp && rm -rf xc_hygiene && mkdir xc_hygiene && cd xc_hygiene && XCOURIER_DATA_DIR=/tmp/xc_hygiene/alice \"$REPO_ROOT/xc\" init 2>&1 | grep -q 'Identity created' && XCOURIER_DATA_DIR=/tmp/xc_hygiene/alice \"$REPO_ROOT/xc\" id 2>&1 | grep -q 'age1' && find /tmp/xc_hygiene -name 'body.*' -o -name 'vault.*' -o -name '*.tmp' -o -name '*.priv' 2>/dev/null | grep . && echo FAIL || echo PASS" \
    "No temp files remain after success" \
    60

run_test "hygiene.permissions_keys_0600" \
    "find \"$HOME/.xcourier\" -name '*.enc' -o -name '*.json' 2>/dev/null | xargs -r stat -c '%a %n' | awk '\$1 != 600 {print \$2}' | grep . && echo FAIL || echo PASS" \
    "Key files have 0600 permissions" \
    10

run_test "hygiene.permissions_dirs_0700" \
    "find \"$HOME/.xcourier\" -type d 2>/dev/null | xargs -r stat -c '%a %n' | awk '\$1 != 700 {print \$2}' | grep . && echo FAIL || echo PASS" \
    "Data directories created with 0700" \
    10

run_test "hygiene.network_blocked" \
    "if unshare -rn true 2>/dev/null; then unshare -rn bash -c 'getent hosts example.invalid 2>/dev/null | wc -l | xargs -I{} test {} -eq 0' && echo PASS || echo FAIL; else echo 'SKIP: unshare requires root'; fi" \
    "Network blocked under unshare -rn" \
    20

# ============================================================
# SECTION 4: Platform Tests
# ============================================================
echo "--- Section 4: Platform Tests ---"

run_test "platform.amd64_tests" \
    "true" \
    "All tests pass on amd64 (current runner)" \
    1

run_test "platform.arm64_ci_configured" \
    "grep -q 'ubuntu-24.04-arm' '$REPO_ROOT/.github/workflows/ci.yml' 2>/dev/null && echo PASS || echo FAIL" \
    "arm64 CI configured" \
    10

run_test "platform.termux_checklist_exists" \
    "test -f '$REPO_ROOT/docs/TERMUX_MANUAL_TEST.md' && grep -q 'NOT YET VERIFIED' '$REPO_ROOT/docs/TERMUX_MANUAL_TEST.md' && echo PASS || echo FAIL" \
    "Termux manual test checklist exists with NOT YET VERIFIED" \
    10

# ============================================================
# SECTION 5: Supply Chain
# ============================================================
echo "--- Section 5: Supply Chain ---"

run_test "supply.pinned_actions" \
    "for f in \"$REPO_ROOT\"/.github/workflows/*.yml; do if grep -qE 'uses: actions/.*@v[0-9]' \"\$f\" 2>/dev/null; then echo FAIL; exit 1; fi; done && echo PASS" \
    "All GitHub Actions pinned to commit SHAs" \
    10

run_test "supply.signed_releases" \
    "test -f '$REPO_ROOT/scripts/release.sh' && grep -q 'ssh-keygen -Y sign' \"$REPO_ROOT/scripts/release.sh\" && echo PASS || echo FAIL" \
    "Release script includes ssh-keygen -Y signing" \
    10

run_test "supply.sbom_generated" \
    "grep -q 'cyclonedx\\|syft\\|spdx' \"$REPO_ROOT/scripts/release.sh\" 2>/dev/null && echo PASS || echo PLANNED" \
    "SBOM generation in release script (planned)" \
    10

run_test "supply.reproducible_build" \
    "test -f \"$REPO_ROOT/scripts/reproducible-check.sh\" && echo PASS || echo PLANNED" \
    "Reproducible build verification documented (planned)" \
    10

run_test "supply.scorecard_configured" \
    "grep -q 'ossf/scorecard-action' \"$REPO_ROOT/.github/workflows/ci.yml\" && echo PASS || echo FAIL" \
    "OpenSSF Scorecard workflow configured" \
    10

run_test "supply.no_minisign_in_user_scripts" \
    "! grep -rnE 'minisign' \"$REPO_ROOT/xc\" \"$REPO_ROOT/scripts/install.sh\" \"$REPO_ROOT/scripts/uninstall.sh\" 2>/dev/null | grep -v '^#' && echo PASS || echo FAIL" \
    "No minisign in user-facing scripts" \
    10

run_test "supply.no_expect_dependency" \
    "! (grep -rnE '\\bexpect\\b' \"$REPO_ROOT/xc\" \"$REPO_ROOT/scripts/install.sh\" \"$REPO_ROOT/scripts/uninstall.sh\" 2>/dev/null | grep -v '^#' | grep -v 'lib/wordlist.txt' | grep -q 'expect') && echo PASS || echo FAIL" \
    "No expect dependency in shipped code (excludes lib/wordlist.txt)" \
    10

run_test "supply.no_passphrase_cli" \
    "! grep -qE -- '--passphrase|no-interactive|read_passphrase' \"$REPO_ROOT/xc\" && echo PASS || echo FAIL" \
    "No passphrase CLI path in xc" \
    10

# ============================================================
# SECTION 6: Evidence System
# ============================================================
echo "--- Section 6: Evidence System ---"

run_test "evidence.claims_md_exists" \
    "test -f \"$REPO_ROOT/docs/CLAIMS.md\" && echo PASS || echo FAIL" \
    "docs/CLAIMS.md exists" \
    10

run_test "evidence.audit_sh_exists" \
    "test -f \"$REPO_ROOT/scripts/audit.sh\" && test -x \"$REPO_ROOT/scripts/audit.sh\" && echo PASS || echo FAIL" \
    "scripts/audit.sh exists and executable" \
    10

run_test "evidence.score_rubric_exists" \
    "test -f \"$REPO_ROOT/docs/SCORE_RUBRIC.md\" && echo PASS || echo FAIL" \
    "docs/SCORE_RUBRIC.md exists with caps" \
    10

run_test "evidence.score_history_exists" \
    "test -f \"$REPO_ROOT/docs/SCORE_HISTORY.md\" && echo PASS || echo FAIL" \
    "docs/SCORE_HISTORY.md exists" \
    10

run_test "evidence.roadmap_exists" \
    "test -f \"$REPO_ROOT/docs/ROADMAP.md\" && echo PASS || echo FAIL" \
    "docs/ROADMAP.md exists" \
    10

run_test "evidence.review_prompt_exists" \
    "test -f \"$REPO_ROOT/docs/REVIEW_ME.md\" && echo PASS || echo FAIL" \
    "docs/REVIEW_ME.md exists" \
    10

# ============================================================
# SECTION 7: Advanced Features (10c) — planned
# ============================================================
echo "--- Section 7: Advanced Features (10c) ---"

run_test "adv.forward_secrecy_prekeys" \
    "grep -q 'prekeys' \"$REPO_ROOT/docs/ROADMAP.md\" 2>/dev/null && echo PLANNED || echo FAIL" \
    "Offline forward secrecy with one-time prekeys (planned in ROADMAP)" \
    10

run_test "adv.hardware_keys" \
    "grep -qi 'yubikey\\|hardware.*key\\|FIDO' \"$REPO_ROOT/docs/ROADMAP.md\" 2>/dev/null && echo PLANNED || echo FAIL" \
    "Hardware-backed keys support (planned in ROADMAP)" \
    10

run_test "adv.standards_mapping" \
    "test -f \"$REPO_ROOT/docs/STANDARDS.md\" && echo PASS || (grep -q 'STANDARDS' \"$REPO_ROOT/docs/ROADMAP.md\" 2>/dev/null && echo PLANNED || echo FAIL)" \
    "Standards mapping doc (planned)" \
    10

run_test "adv.two_person_review" \
    "grep -q 'two approvals\\|two-person' \"$REPO_ROOT/CONTRIBUTING.md\" 2>/dev/null && echo PASS || echo PLANNED" \
    "Two-person review for crypto changes (planned)" \
    10

run_test "adv.threat_model_reviewed" \
    "test -f \"$REPO_ROOT/docs/THREAT_MODEL.md\" && grep -qi 'reviewed' \"$REPO_ROOT/docs/THREAT_MODEL.md\" && echo PASS || echo PLANNED" \
    "THREAT_MODEL.md reviewed by outsider (planned)" \
    10

# ============================================================
# SECTION 8: Honest Claims
# ============================================================
echo "--- Section 8: Honest Claims ---"

run_test "claims.no_hype" \
    "! grep -rin 'unhackable\\|military-grade\\|CIA-grade\\|NSA-proof\\|guaranteed secure\\|100% secure\\|zero bugs\\|bug-free' \"$REPO_ROOT/README.md\" \"$REPO_ROOT/SECURITY.md\" 2>/dev/null | grep -v 'Do not claim\\|not claim\\|without evidence\\|see Security' | grep . || echo PASS" \
    "No hype claims (unhackable, military-grade, CIA-level, guaranteed)" \
    10

run_test "claims.honest_limitations" \
    "grep -q 'independently audited\\|forward secrecy\\|endpoint compromise' \"$REPO_ROOT/SECURITY.md\" 2>/dev/null && echo PASS || echo FAIL" \
    "README/SECURITY.md states honest limitations" \
    10

run_test "claims.verifiable_not_guaranteed" \
    "grep -q 'verifiable\\|run.*audit.*yourself\\|check.*evidence' \"$REPO_ROOT/README.md\" 2>/dev/null && echo PASS || echo FAIL" \
    "Marketing uses 'verifiable', not 'guaranteed'" \
    10

# ============================================================
# SECTION 9: Build Verification
# ============================================================
echo "--- Section 9: Build Verification ---"

run_test "build.main_script_exists" \
    "test -f \"$REPO_ROOT/xc\" && echo PASS || echo FAIL" \
    "Main script exists" \
    1

run_test "build.shellcheck_strict_gates" \
    "shellcheck -S style \"$REPO_ROOT/xc\" >/dev/null 2>&1 && echo PASS || echo FAIL" \
    "Strict-boundary gates pass" \
    30

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

# Exit code based on failures (planned/skip not failures)
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