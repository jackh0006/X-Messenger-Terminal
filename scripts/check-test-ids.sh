#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# check-test-ids.sh — Every bats test has a unique ID and every ID is covered.
#
# Fails when any of the following is true:
#   - a bat test name does not start with a unique ID token (e.g. T01, FZ02, FQ03)
#   - an ID token is duplicated across any tests/*.bats file
#   - a test ID is missing from the Test ID(s) column of docs/CLAIMS.md
#   - CLAIMS.md Test ID(s) references an ID that does not exist in tests/
#
# A bare "—" (or "-") in the Test ID(s) column is a legal placeholder for
# planned claims that have no test yet.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAIMS="$REPO_ROOT/docs/CLAIMS.md"

test_ids=$(mktemp)      # id + filename pairs from tests/
claims_ids=$(mktemp)    # ID tokens found in the Claim column
errors=0
trap 'rm -f "$test_ids" "$claims_ids"' EXIT

if [[ ! -f "$CLAIMS" ]]; then
    echo "docs/CLAIMS.md missing"
    exit 1
fi

# ---------------------------------------------------------------
# 1) Every @test name must start with an ID token; IDs must be unique.
# ---------------------------------------------------------------
for f in "$REPO_ROOT""/tests/"*.bats; do
    base=$(basename "$f")
    while IFS= read -r line; do
        id=$(printf '%s\n' "$line" | sed -E 's/^@test "([A-Z]{1,3}[0-9]+).*/\1/')
        name=$(printf '%s\n' "$line" | sed -E 's/^@test "//; s/"$//')
        if ! printf '%s\n' "$id" | grep -qE '^[A-Z]{1,3}[0-9]+$'; then
            echo "FAIL: test without unique ID in $base: $name"
            errors=$((errors + 1))
            continue
        fi
        printf '%s\t%s\n' "$id" "$base" >> "$test_ids"
    done < <(grep -hE '^@test ' "$f")
done

dups=$(cut -f1 "$test_ids" | sort | uniq -d | tr '\n' ' ')
if [[ -n "${dups// /}" ]]; then
    for d in $dups; do
        where=$(awk -F'\t' -v id="$d" '$1 == id { printf "%s ", $2 }' "$test_ids")
        echo "FAIL: duplicate test ID $d (in $where)"
        errors=$((errors + 1))
    done
fi

# ---------------------------------------------------------------
# 2) Every test ID must appear in the Test ID(s) column of CLAIMS.md.
# ---------------------------------------------------------------
total_tests=$(wc -l < "$test_ids" | tr -d ' ')

while IFS=$'\t' read -r id file; do
    # Look only inside the Test ID(s) column (4th pipe-delimited field,
    # including the leading empty field from the opening '|').
    hit=$(awk -F'|' -v id="$id" '$4 ~ ("(^|[^A-Z-])" id "($|[^0-9])") { found = 1 } END { if (found) print "yes" }' "$CLAIMS")
    if [[ -z "$hit" ]]; then
        echo "FAIL: test $id ($file) is not referenced in docs/CLAIMS.md"
        errors=$((errors + 1))
    fi
done < "$test_ids"

# ---------------------------------------------------------------
# 3) Every ID CLAIMS.md references must exist in tests/.
# ---------------------------------------------------------------
awk -F'|' 'NR > 2 && $4 != "" { print $4 }' "$CLAIMS" \
    | grep -oE '[A-Z]{1,3}[0-9]+' | sort -u > "$claims_ids" || true

while IFS= read -r cid; do
    [[ -z "$cid" ]] && continue
    if ! cut -f1 "$test_ids" | grep -qx "$cid"; then
        echo "FAIL: docs/CLAIMS.md references test $cid, which does not exist in tests/"
        errors=$((errors + 1))
    fi
done < "$claims_ids"

# ---------------------------------------------------------------
echo ""
if [[ $errors -gt 0 ]]; then
    echo "check-test-ids: $errors problem(s) found across $total_tests tests"
    exit 1
fi
echo "check-test-ids: PASS — $total_tests tests, unique IDs, all covered by docs/CLAIMS.md"
exit 0
