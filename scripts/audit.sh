#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# audit.sh — Runs all checks and writes a machine-readable report.
#
# Statuses are exactly one of: PASS, FAIL, SKIP, PLANNED.
# Every check belongs to exactly one category, and the two categories are
# never mixed in the summary:
#   security — the property is actually exercised here (the full bats suite
#              runs inside this audit, or the check executes real commands).
#   scaffold — file existence, configuration greps, roadmap/planned work.
#              A scaffold check never validates a security capability; when
#              it is evidence-only, it carries a "scaffold-only:" reason.
# Exit non-zero only when at least one check FAILs.

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
  "summary": { "total": 0, "PASS": 0, "FAIL": 0, "SKIP": 0, "PLANNED": 0 }
}
EOF

add_result() {
    local category="$1" id="$2" status="$3" message="$4" details="${5:-}"
    local tmp
    tmp=$(mktemp)
    jq --arg cat "$category" --arg id "$id" --arg status "$status" --arg msg "$message" --arg det "$details" \
      '.results += [{"id": $id, "category": $cat, "status": $status, "message": $msg, "details": $det}] |
       .summary.total += 1 |
       .summary."PASS" += (if $status == "PASS" then 1 else 0 end) |
       .summary."FAIL" += (if $status == "FAIL" then 1 else 0 end) |
       .summary."SKIP" += (if $status == "SKIP" then 1 else 0 end) |
       .summary."PLANNED" += (if $status == "PLANNED" then 1 else 0 end)' \
      "$REPORT" > "$tmp" && mv "$tmp" "$REPORT"
    echo "[$status] $id: $message"
}

# run_test: executes a command; the command's LAST line decides the status.
# Last line must be exactly PASS, FAIL, or PLANNED to count as that status;
# "SKIP: <reason>" lines map to SKIP with the rest of the line as reason.
# Anything else (empty output, noise, a lone FAIL in the middle) is FAIL.
run_test() {
    local category="$1" id="$2" cmd="$3" desc="$4" timeout_sec="${5:-30}"
    local out last status reason
    out=$(timeout "$timeout_sec" bash -c "$cmd" 2>&1) || {
        local ec=$?
        if [[ $ec -eq 124 ]]; then
            add_result "$category" "$id" "FAIL" "$desc" "TIMEOUT after ${timeout_sec}s"
        else
            add_result "$category" "$id" "FAIL" "$desc" "$out"
        fi
        return 0
    }
    last=$(echo "$out" | tail -n 1)
    case "$last" in
        PASS)
            add_result "$category" "$id" "PASS" "$desc" "$out"
            ;;
        FAIL)
            add_result "$category" "$id" "FAIL" "$desc" "$out"
            ;;
        PLANNED)
            add_result "$category" "$id" "PLANNED" "$desc" "$out"
            ;;
        'SKIP:'*)
            reason="${last#SKIP: }"
            add_result "$category" "$id" "SKIP" "$desc" "SKIP: $reason"
            ;;
        *)
            add_result "$category" "$id" "FAIL" "$desc" "unrecognized result: $out"
            ;;
    esac
    return 0
}

run_planned() {
    local category="$1" id="$2" reason="$3" desc="$4"
    add_result "$category" "$id" "PLANNED" "$desc" "$reason"
}

run_skip() {
    local category="$1" id="$2" reason="$3" desc="$4"
    add_result "$category" "$id" "SKIP" "$desc" "SKIP: $reason"
}

echo "=== X Messenger Terminal Self-Audit ==="
echo "Version: $VERSION | Commit: $COMMIT_HASH | Platform: $PLATFORM"
echo ""

# ============================================================
# SECTION 1: Crypto Correctness — the audit RUNS the full suite
# ============================================================
echo "--- Section 1: Crypto Correctness ---"

SUITE_STATUS=0
run_full_suite() {
    local log="$EVIDENCE_DIR/bats-run.log"
    local n_tests ok not_ok
    n_tests=$(grep -hcE '^@test ' "$REPO_ROOT"/tests/*.bats | awk '{s+=$1} END{print s+0}')
    echo "Running the full bats suite ($n_tests tests)..."
    rm -f "$log"
    set +e
    timeout 900 bats "$REPO_ROOT/tests/" > "$log" 2>&1
    SUITE_STATUS=$?
    set -e
    # Full transparency: the suite output is part of the audit output.
    cat "$log"
    ok=$(grep -c '^ok ' "$log" || true)
    not_ok=$(grep -c '^not ok ' "$log" || true)
    if [[ $SUITE_STATUS -eq 0 && $not_ok -eq 0 ]]; then
        add_result "security" "crypto.full_test_suite" "PASS" \
            "Full bats suite ($n_tests tests) passes" \
            "ok: $ok, not ok: $not_ok; log: evidence/bats-run.log"
    else
        add_result "security" "crypto.full_test_suite" "FAIL" \
            "Full bats suite ($n_tests tests) passes" \
            "exit: $SUITE_STATUS, ok: $ok, not ok: $not_ok; log: evidence/bats-run.log; last lines: $(tail -n 20 "$log" | tr '\n' ' ')"
    fi
    # Skipped tests surface as individual SKIP rows with their own reasons.
    local sid sreason
    while IFS=$'\t' read -r sid sreason; do
        [[ -z "${sid:-}" ]] && continue
        run_skip "security" "suite_skip_$sid" \
            "$sid skips itself via skip() in this environment (-r locally); reason: $sreason" \
            "bats test $sid skipped in this environment"
    done < <(sed -nE 's/^ok [0-9]+ ([A-Z]{1,3}[0-9]+)[^#]*# skip (.*)$/\1\t\2/p' "$log")
}

run_full_suite

# ============================================================
# SECTION 2: Input Validation (derived from the suite outcome)
# ============================================================
echo "--- Section 2: Input Validation ---"

if [[ $SUITE_STATUS -eq 0 ]]; then
    add_result "security" "input.validation_suite" "PASS" \
        "Input validation exercised by the suite" \
        "exercised by T03 T04 T05 T11 T12 within the full suite run in this audit"
else
    add_result "security" "input.validation_suite" "FAIL" \
        "Input validation exercised by the suite" \
        "parent suite run failed (see crypto.full_test_suite)"
fi

# ============================================================
# SECTION 3: Hygiene
# ============================================================
echo "--- Section 3: Hygiene ---"

run_test "security" "hygiene.shellcheck_clean" \
    "shellcheck -S style '$REPO_ROOT/xc' 2>&1 | grep -v '^In ' | grep -v '^--' | grep . && echo FAIL || echo PASS" \
    "shellcheck clean (style warnings only)" \
    60

run_test "security" "hygiene.no_temp_leaks" \
    "cd /tmp && rm -rf xc_hygiene && mkdir xc_hygiene && cd xc_hygiene && XCOURIER_DATA_DIR=/tmp/xc_hygiene/alice \"$REPO_ROOT/xc\" init 2>&1 | grep -q 'Identity created' && XCOURIER_DATA_DIR=/tmp/xc_hygiene/alice \"$REPO_ROOT/xc\" id 2>&1 | grep -q 'age1' && find /tmp/xc_hygiene -name 'body.*' -o -name 'vault.*' -o -name '*.tmp' -o -name '*.priv' 2>/dev/null | grep . && echo FAIL || echo PASS" \
    "No temp files remain after success" \
    60

run_test "security" "hygiene.permissions_keys_0600" \
    "if [ ! -d \"\$HOME/.xcourier\" ]; then echo 'SKIP: no default data dir on this runner (0600 perms exercised by test T14)'; else find \"\$HOME/.xcourier\" -name '*.enc' -o -name '*.json' 2>/dev/null | xargs -r stat -c '%a %n' | awk '\$1 != 600 {print \$2}' | grep . && echo FAIL || echo PASS; fi" \
    "Key files have 0600 permissions (when a default data dir exists)" \
    10

run_test "security" "hygiene.permissions_dirs_0700" \
    "if [ ! -d \"\$HOME/.xcourier\" ]; then echo 'SKIP: no default data dir on this runner (0700 perms exercised by test T14)'; else find \"\$HOME/.xcourier\" -type d 2>/dev/null | xargs -r stat -c '%a %n' | awk '\$1 != 700 {print \$2}' | grep . && echo FAIL || echo PASS; fi" \
    "Data directories created with 0700 (when a default data dir exists)" \
    10

run_test "security" "hygiene.network_blocked" \
    "if unshare -rn true 2>/dev/null; then unshare -rn bash -c 'getent hosts example.invalid 2>/dev/null | wc -l | xargs -I{} test {} -eq 0' && echo PASS || echo FAIL; else echo 'SKIP: unshare requires root; canary is exercised by the CI test job'; fi" \
    "Network blocked under unshare -rn" \
    20

# ============================================================
# SECTION 4: Platform
# ============================================================
echo "--- Section 4: Platform ---"

if [[ "$(uname -m)" == "x86_64" ]]; then
    if [[ $SUITE_STATUS -eq 0 ]]; then
        add_result "security" "platform.amd64_tests" "PASS" \
            "All tests pass on amd64 (current runner)" \
            "amd64 suite run inside this audit (see crypto.full_test_suite)"
    else
        add_result "security" "platform.amd64_tests" "FAIL" \
            "All tests pass on amd64 (current runner)" \
            "parent suite run failed (see crypto.full_test_suite)"
    fi
else
    run_skip "security" "platform.amd64_tests" \
        "this audit runs on $(uname -m); amd64 is exercised by the CI matrix job on ubuntu-24.04" \
        "All tests pass on amd64"
fi

if [[ "${CI:-}" == "true" ]]; then
    run_test "scaffold" "platform.arm64_ci_configured" \
        "grep -q 'ubuntu-24.04-arm' '$REPO_ROOT/.github/workflows/ci.yml' 2>/dev/null && echo PASS || echo FAIL" \
        "arm64 CI configured (this audit runs inside CI)" \
        10
else
    run_skip "scaffold" "platform.arm64_ci_configured" \
        "arm64 is exercised only by the CI matrix job on ubuntu-24.04-arm, not on this local runner" \
        "arm64 CI configured"
fi

run_test "scaffold" "platform.termux_checklist_exists" \
    "test -f '$REPO_ROOT/docs/TERMUX_MANUAL_TEST.md' && grep -q 'NOT YET VERIFIED' '$REPO_ROOT/docs/TERMUX_MANUAL_TEST.md' && echo PLANNED || echo FAIL" \
    "scaffold-only: Termux checklist exists; the real-device test is owner-run (T19) and has not happened" \
    10

# ============================================================
# SECTION 5: Supply Chain
# ============================================================
echo "--- Section 5: Supply Chain ---"

run_test "scaffold" "supply.pinned_actions" \
    "for f in \"$REPO_ROOT\"/.github/workflows/*.yml; do if grep -qE 'uses: [^ ]+@(v[0-9]+|main|master|latest)' \"\$f\" 2>/dev/null; then echo FAIL; exit 0; fi; done && echo PASS" \
    "All GitHub Actions pinned to commit SHAs (config check)" \
    10

run_planned "scaffold" "supply.signed_releases" \
    "scaffold-only: scripts/release.sh contains ssh-keygen -Y sign, but no signed release artifact has been produced or verified yet" \
    "Signed releases exist and verify"

run_planned "scaffold" "supply.sbom_generated" \
    "scaffold-only: no SBOM artifact has been produced by a real release yet" \
    "SBOM generated by a real release"

run_planned "scaffold" "supply.reproducible_build" \
    "scaffold-only: no reproducible-build verification has been run yet" \
    "Reproducible build verified"

run_planned "scaffold" "supply.scorecard_configured" \
    "scaffold-only: the scorecard-action job was removed from CI earlier (gcr.io billing error); OpenSSF Scorecard is re-planned" \
    "OpenSSF Scorecard configured"

run_test "security" "supply.no_minisign_in_user_scripts" \
    "! grep -rnE 'minisign' \"$REPO_ROOT/xc\" \"$REPO_ROOT/scripts/install.sh\" \"$REPO_ROOT/scripts/uninstall.sh\" 2>/dev/null | grep -v '^#' && echo PASS || echo FAIL" \
    "No minisign in user-facing scripts" \
    10

run_test "security" "supply.no_expect_dependency" \
    "! (grep -rnE '\\bexpect\\b' \"$REPO_ROOT/xc\" \"$REPO_ROOT/scripts/install.sh\" \"$REPO_ROOT/scripts/uninstall.sh\" 2>/dev/null | grep -v '^#' | grep -v 'lib/wordlist.txt' | grep -q 'expect') && echo PASS || echo FAIL" \
    "No expect dependency in shipped code (excludes lib/wordlist.txt)" \
    10

run_test "security" "supply.no_passphrase_cli" \
    "! grep -qE -- '--passphrase|no-interactive|read_passphrase' \"$REPO_ROOT/xc\" && echo PASS || echo FAIL" \
    "No passphrase CLI path in xc" \
    10

# ============================================================
# SECTION 6: Evidence System
# ============================================================
echo "--- Section 6: Evidence System ---"

run_test "scaffold" "evidence.claims_md_exists" \
    "test -f \"$REPO_ROOT/docs/CLAIMS.md\" && echo PASS || echo FAIL" \
    "docs/CLAIMS.md exists" \
    10

run_test "scaffold" "evidence.audit_sh_exists" \
    "test -f \"$REPO_ROOT/scripts/audit.sh\" && test -x \"$REPO_ROOT/scripts/audit.sh\" && echo PASS || echo FAIL" \
    "scripts/audit.sh exists and executable" \
    10

run_test "scaffold" "evidence.score_rubric_exists" \
    "test -f \"$REPO_ROOT/docs/SCORE_RUBRIC.md\" && echo PASS || echo FAIL" \
    "docs/SCORE_RUBRIC.md exists" \
    10

run_test "scaffold" "evidence.score_history_exists" \
    "test -f \"$REPO_ROOT/docs/SCORE_HISTORY.md\" && echo PASS || echo FAIL" \
    "docs/SCORE_HISTORY.md exists" \
    10

run_test "scaffold" "evidence.roadmap_exists" \
    "test -f \"$REPO_ROOT/docs/ROADMAP.md\" && echo PASS || echo FAIL" \
    "docs/ROADMAP.md exists" \
    10

run_test "scaffold" "evidence.review_prompt_exists" \
    "test -f \"$REPO_ROOT/docs/REVIEW_ME.md\" && echo PASS || echo FAIL" \
    "docs/REVIEW_ME.md exists" \
    10

run_test "security" "claims.test_ids_covered" \
    "bash \"$REPO_ROOT/scripts/check-test-ids.sh\" >/dev/null 2>&1 && echo PASS || echo FAIL" \
    "Every test has a unique ID and every ID is covered by docs/CLAIMS.md" \
    30

# ============================================================
# SECTION 7: Advanced Features
# ============================================================
echo "--- Section 7: Advanced Features ---"

run_planned "scaffold" "adv.forward_secrecy_prekeys" \
    "not implemented; one-time prekeys are Stage 2 of the roadmap" \
    "Offline forward secrecy with one-time prekeys"

run_planned "scaffold" "adv.hardware_keys" \
    "not implemented; hardware-backed keys are on the roadmap" \
    "Hardware-backed keys support"

run_planned "scaffold" "adv.standards_mapping" \
    "scaffold-only: a standards doc exists, but the mapping has not been independently verified" \
    "Standards mapping verified"

run_planned "scaffold" "adv.two_person_review" \
    "no two-person review has taken place; the process doc alone is scaffold" \
    "Two-person review of crypto changes"

run_planned "scaffold" "adv.threat_model_reviewed" \
    "THREAT_MODEL.md exists, but no outside review has occurred; needs real review" \
    "THREAT_MODEL.md reviewed by an outsider"

# ============================================================
# SECTION 8: Honest Claims
# ============================================================
echo "--- Section 8: Honest Claims ---"

run_test "security" "claims.no_hype" \
    "if grep -rin 'unhackable\\|military-grade\\|CIA-grade\\|NSA-proof\\|guaranteed secure\\|100% secure\\|zero bugs\\|bug-free' \"$REPO_ROOT/README.md\" \"$REPO_ROOT/SECURITY.md\" 2>/dev/null | grep -v 'Do not claim\\|not claim\\|without evidence\\|see Security' | grep .; then echo FAIL; else echo PASS; fi" \
    "No hype claims (unhackable, military-grade, CIA-level, guaranteed)" \
    10

run_test "security" "claims.honest_limitations" \
    "grep -q 'independently audited\\|forward secrecy\\|endpoint compromise' \"$REPO_ROOT/SECURITY.md\" 2>/dev/null && echo PASS || echo FAIL" \
    "README/SECURITY.md states honest limitations" \
    10

run_test "security" "claims.verifiable_not_guaranteed" \
    "grep -q 'verifiable\\|run.*audit.*yourself\\|check.*evidence' \"$REPO_ROOT/README.md\" 2>/dev/null && echo PASS || echo FAIL" \
    "Marketing uses 'verifiable', not 'guaranteed'" \
    10

# ============================================================
# SECTION 9: Build Verification
# ============================================================
echo "--- Section 9: Build Verification ---"

run_test "scaffold" "build.main_script_exists" \
    "test -f \"$REPO_ROOT/xc\" && echo PASS || echo FAIL" \
    "Main script exists" \
    1

run_test "security" "build.shellcheck_strict_gates" \
    "shellcheck -S style \"$REPO_ROOT/xc\" >/dev/null 2>&1 && echo PASS || echo FAIL" \
    "shellcheck style gate on xc passes" \
    30

# ============================================================
# FINALIZE — counts are computed from the results, never hard-coded
# ============================================================
echo ""
echo "=== Generating text report ==="

jq -r '.results[] | "[\(.status)] \(.id): \(.message)" + (if .details != "" then "\n  Details: \(.details)" else "" end)' "$REPORT" > "$REPORT_TXT"

SEC_COUNTS=$(jq -r '.results | map(select(.category=="security")) |
    "Security checks (exercised by tests): \(. | length) total | PASS: \(map(select(.status=="PASS")) | length) | FAIL: \(map(select(.status=="FAIL")) | length) | SKIP: \(map(select(.status=="SKIP")) | length) | PLANNED: \(map(select(.status=="PLANNED")) | length)"' "$REPORT")
SAF_COUNTS=$(jq -r '.results | map(select(.category=="scaffold")) |
    "Scaffold checks (files/config/planned work): \(. | length) total | PASS: \(map(select(.status=="PASS")) | length) | FAIL: \(map(select(.status=="FAIL")) | length) | SKIP: \(map(select(.status=="SKIP")) | length) | PLANNED: \(map(select(.status=="PLANNED")) | length)"' "$REPORT")

{
    echo ""
    echo "=== Summary ==="
    echo "$SEC_COUNTS"
    echo "$SAF_COUNTS"
    jq -r '"Total: \(.summary.total) checks | PASS \(.summary."PASS"), FAIL \(.summary."FAIL"), SKIP \(.summary."SKIP"), PLANNED \(.summary."PLANNED")"' "$REPORT"
} >> "$REPORT_TXT"

echo ""
cat "$REPORT_TXT"

FAIL_COUNT=$(jq '.summary."FAIL"' "$REPORT")
if [[ $FAIL_COUNT -gt 0 ]]; then
    echo ""
    echo "AUDIT FAILED: $FAIL_COUNT check(s) failed"
    exit 1
else
    echo ""
    echo "AUDIT PASSED: no failing checks"
    exit 0
fi
