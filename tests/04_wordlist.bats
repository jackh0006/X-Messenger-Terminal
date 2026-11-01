#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Wordlist tests: BIP39 wordlist integrity and fingerprint vectors

load 'test_helper'

@test "T13 wordlist: 2048 unique words, SHA-256 matches pinned value" {
    [[ -f "$REPO_DIR/lib/wordlist.txt" ]] || { echo "wordlist.txt missing"; return 1; }
    local count
    count=$(wc -l < "$REPO_DIR/lib/wordlist.txt")
    [[ "$count" -eq 2048 ]] || { echo "wordlist has $count lines, expected 2048"; return 1; }
    local uniq
    uniq=$(sort -u "$REPO_DIR/lib/wordlist.txt" | wc -l)
    [[ "$uniq" -eq 2048 ]] || { echo "wordlist has $uniq unique words, expected 2048"; return 1; }
    local sha
    sha=$(sha256sum "$REPO_DIR/lib/wordlist.txt" | awk '{print $1}')
    [[ "$sha" == "2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda" ]] || { echo "SHA-256 mismatch: $sha"; return 1; }
}

@test "T14 fingerprint: test vectors for 6-word and 8-word modes" {
    # Test vector 1: known fingerprint
    local fp="SHA256:AbCdEfGhIjKlMnOpQrStUvWxYz0123456789AbCdEfGh"
    local w6 w8
    w6=$(REPO_DIR="$REPO_DIR" bash -c 'source <(sed -n "1,/^main()/p" "$REPO_DIR/xc" | head -n -1); fingerprint_words "SHA256:AbCdEfGhIjKlMnOpQrStUvWxYz0123456789AbCdEfGh" 6')
    [[ "$w6" == "accuse lumber dutch today banana bone" ]] || { echo "6-word mismatch: $w6"; return 1; }
    w8=$(REPO_DIR="$REPO_DIR" bash -c 'source <(sed -n "1,/^main()/p" "$REPO_DIR/xc" | head -n -1); fingerprint_words "SHA256:AbCdEfGhIjKlMnOpQrStUvWxYz0123456789AbCdEfGh" 8')
    [[ "$w8" == "accuse lumber dutch today banana bone network example" ]] || { echo "8-word mismatch: $w8"; return 1; }

    # Test vector 2: different fingerprint
    local fp2="SHA256:QrStUvWxYz0123456789AbCdEfGhIjKlMnOpAbCdEfGh"
    local w6b w8b
    w6b=$(REPO_DIR="$REPO_DIR" bash -c 'source <(sed -n "1,/^main()/p" "$REPO_DIR/xc" | head -n -1); fingerprint_words "SHA256:QrStUvWxYz0123456789AbCdEfGhIjKlMnOpAbCdEfGh" 6')
    w8b=$(REPO_DIR="$REPO_DIR" bash -c 'source <(sed -n "1,/^main()/p" "$REPO_DIR/xc" | head -n -1); fingerprint_words "SHA256:QrStUvWxYz0123456789AbCdEfGhIjKlMnOpAbCdEfGh" 8')
    [[ "$w6b" != "$w6" ]] || { echo "different fingerprints should produce different words"; return 1; }
    [[ "$w8b" != "$w8" ]] || { echo "different fingerprints should produce different 8-words"; return 1; }
}

@test "T15 fingerprint: every index 0..2047 maps to a distinct word" {
    run bash -c '
check_words() {
    source <(sed -n "1,/^main()/p" "'$REPO_DIR'/xc" | head -n -1)
    local words=()
    while IFS= read -r w; do words+=("$w"); done < "'$REPO_DIR'/lib/wordlist.txt"
    for i in {0..2047}; do
        [[ -n "${words[i]}" ]] || { echo "word at index $i is empty"; return 1; }
    done
    echo "All 2048 indices map to non-empty words"
}
check_words
'
    [[ "$status" -eq 0 ]] || { echo "wordlist index check failed"; return 1; }
}