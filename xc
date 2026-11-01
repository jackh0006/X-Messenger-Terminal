#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# X Messenger Terminal — xc
# Offline encrypted message courier using age + OpenSSH signatures

set -euo pipefail
# Nothing xc writes may ever be readable by others, files or dirs alike.
umask 077

VERSION="0.1.0"
DATA_DIR="${XCOURIER_DATA_DIR:-$HOME/.xcourier}"
IDENTITY_DIR="$DATA_DIR/identity"
CONTACTS_DIR="$DATA_DIR/contacts"
PREKEYS_DIR="$DATA_DIR/prekeys"
REPLAY_DIR="$DATA_DIR/replay"
VAULT_DIR="$DATA_DIR/vault"

declare -A BUCKETS=(["1k"]=1024 ["4k"]=4096 ["16k"]=16384 ["64k"]=65536)
BUCKET_ORDER=("1k" "4k" "16k" "64k")

if [[ -z "${NO_COLOR:-}" ]]; then
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[1;33m'
	BLUE='\033[0;34m'
	NC='\033[0m'
else
	RED=''
	GREEN=''
	YELLOW=''
	BLUE=''
	NC=''
fi

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
# [WARN]/[ERR] go to STDERR: errors printed on stdout have leaked into
# command-substitution results before (a die message was captured as a
# message payload and signed). Only normal UX lines go to stdout.
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_err() { echo -e "${RED}[ERR]${NC} $*" >&2; }

die() {
	log_err "$*"
	exit 1
}
confirm() {
	read -rp "$1 [y/N] " ans
	[[ "$ans" =~ ^[Yy]$ ]]
}

ensure_data_dirs() {
	mkdir -p "$IDENTITY_DIR" "$CONTACTS_DIR" "$PREKEYS_DIR" "$REPLAY_DIR" "$VAULT_DIR"
	chmod 700 "$DATA_DIR" "$IDENTITY_DIR" "$CONTACTS_DIR" "$PREKEYS_DIR" "$REPLAY_DIR" "$VAULT_DIR" 2>/dev/null || true
}

require_tool() { command -v "$1" >/dev/null 2>&1 || die "Required tool '$1' not found. Install: $2"; }

# Key protection at rest is interactive only. age prompts for the passphrase
# on the real terminal (/dev/tty). The passphrase never travels in argv, is
# never written to a file, and is never placed in an exported environment
# variable by this script. Tests exercise these prompts through a local
# pseudo-terminal driver (tests/helpers/) that is never shipped or installed.

require_tty() {
	if ! { : </dev/tty; } 2>/dev/null; then
		die "xc needs your passphrase and you have no terminal to type it in. Run xc directly in a terminal window; it will prompt you there."
	fi
}

generate_identity() {
	ensure_data_dirs
	require_tty
	age-keygen -o "$IDENTITY_DIR/age.priv" 2>/dev/null
	age-keygen -y "$IDENTITY_DIR/age.priv" >"$IDENTITY_DIR/age.pub"
	ssh-keygen -t ed25519 -N "" -f "$IDENTITY_DIR/ssh" -C "xc-identity-$(date +%s)" >/dev/null
	chmod 600 "$IDENTITY_DIR/age.priv" "$IDENTITY_DIR/ssh"
	# age asks for the passphrase on the terminal itself: Enter, then Confirm,
	# once per file (age key, then SSH signing key).
	age -p -a -e -o "$IDENTITY_DIR/age.priv.enc" "$IDENTITY_DIR/age.priv"
	age -p -a -e -o "$IDENTITY_DIR/ssh.enc" "$IDENTITY_DIR/ssh"
	shred -u "$IDENTITY_DIR/age.priv" "$IDENTITY_DIR/ssh" 2>/dev/null || rm -f "$IDENTITY_DIR/age.priv" "$IDENTITY_DIR/ssh"
	chmod 600 "$IDENTITY_DIR/age.priv.enc" "$IDENTITY_DIR/ssh.enc"
	log_ok "Identity created and encrypted"
}

load_identity() {
	require_tty
	[[ -f "$IDENTITY_DIR/age.pub" ]] || die "No identity. Run 'xc init'."
	local tmpd
	tmpd=$(mktemp -d "$DATA_DIR/vault.XXXXXX")
	chmod 700 "$tmpd"
	if ! age -d -o "$tmpd/age.priv" <"$IDENTITY_DIR/age.priv.enc" 2>/dev/null; then
		rm -rf "$tmpd"
		die "Incorrect passphrase"
	fi
	if ! age -d -o "$tmpd/ssh.priv" <"$IDENTITY_DIR/ssh.enc" 2>/dev/null; then
		rm -rf "$tmpd"
		die "Incorrect passphrase"
	fi
	chmod 600 "$tmpd/age.priv" "$tmpd/ssh.priv"
	AGE_PUBKEY=$(cat "$IDENTITY_DIR/age.pub")
	SSH_PUBKEY=$(cat "$IDENTITY_DIR/ssh.pub")
	AGE_PRIVKEY_FILE="$tmpd/age.priv"
	SSH_PRIVKEY_FILE="$tmpd/ssh.priv"
	IDENTITY_TMPDIR="$tmpd"
}

cleanup_identity() { rm -rf "${IDENTITY_TMPDIR:-/run/xc-cleanup-nonexistent}"; }

get_fingerprint() { ssh-keygen -lf "$IDENTITY_DIR/ssh.pub" | awk '{print "SHA256:" substr($2, index($2, ":") + 1)}' | head -1; }

# 6-word fingerprint from BIP39 wordlist (first 1626 words, lowercase)
# Deterministic: SHA256 fingerprint -> 6 words
# 6-word fingerprint from BIP39 wordlist (first 1626 words, lowercase)
# Deterministic: SHA256 fingerprint -> 6 words
fingerprint_words() {
	local fp="$1"
	fp="${fp#SHA256:}"
	local raw hex indices=()
	raw=$(printf '%s' "$fp" | base64 -d 2>/dev/null) || return 1
	hex=$(printf '%s' "$raw" | xxd -p -c 256)
	local i bitval=0 bits=0
	for ((i = 0; i < ${#hex}; i += 2)); do
		byte=$((16#${hex:i:2}))
		bitval=$(((bitval << 8) | byte))
		bits=$((bits + 8))
		while ((bits >= 11)); do
			bits=$((bits - 11))
			indices+=($(((bitval >> bits) & 0x7FF)))
			((${#indices[@]} == 6)) && break 2
		done
	done
	# BIP39 English wordlist (first 2048 words, using first 1626 for 11-bit index)
	local words
	words=$(
		cat <<'WORDLIST'
abandon ability able about above absent absorb abstract absurd abuse access accident account accuse achieve acid acquire across act action actor actress actual adapt add addict address adjust admit adult advance advice aerobic affair afford afraid agency agree ahead aim air airport aisle alarm album alcohol alert alien all alley allow almost alone alpha already also alter always amateur amazing among amount amuse analyst anchor ancient anger angle angry animal ankle announce annual another answer antenna antique anxiety any apart apology appear apple approve april arch arctic area arena argue arm armed armor army around arrange arrest arrive arrow art artefact artist artwork ask aspect assault asset assist assume asthma athlete atom attach attack attend attitude attract auction audit august aunt author auto autumn average avocado avoid awake aware away awesome awful awkward axis baby bachelor bacon badge bag balance balcony ball bamboo banana banner bar barely bargain barrel base basic basket battle beach bean beauty because become beef before begin behave behind believe below belt bench benefit best betray better between beyond bicycle bid bike bind biology bird birth bitter black blade blame blanket blast bleak bless blind blood blossom blouse blue blur blush board boat body boil bomb bone bonus book boost border boring borrow boss bottom bounce box boy bracket brain branch brand brass brave bread breeze brick bridge brief bright bring brisk broad broken brother brown brush bubble buddy budget buffalo build bulb bulb bundle bush business busy butter buyer buzz cabin cable cactus cage cake call calm camera camp can canal cancel candy cannon canoe canvas canyon capable capital captain car carbon card cargo carpet carry cart case cash casino castle casual cat catch category cattle caught cause caution cave ceiling cell cement census century cereal certain chair chalk champion change chaos chapter charge chase cheap check cheese chef cherry chest chicken chief child chimney choice choose chronic chuck chunk churn cigar cinnamon circle citizen city civil claim clap clarify claw clay clean clerk clever click client cliff climb clinic clip clock clog close cloth cloud clown club clump cluster clutch coach coast coconut code coffee coil coin collect color column combine come comfort comic common company concert conduct confirm congress connect consider control convince cook cool copper copy coral core corn correct cost cotton couch country couple course cousin cover coyote crack cradle craft cram crane crash crater crawl crazy cream credit creek crew cricket crime crisp critic crop cross crouch crowd crucial cruel cruise crumble crunch crush cry crystal cube culture cup cupboard curious current curtain curve cushion custom cute cycle dad damage damp dance danger daring dash daughter dawn day deal debate debris decade december decide decline decorate decrease deer defense define defy degree delay deliver demand demise denial dentist deny depart depend deposit depth deputy derive describe desert design desk despair destroy detail detect develop device devote diagram dial diamond diary dice diesel diet differ digital dignity dilemma dinner dinosaur direct dirt disagree discover disease dish dismiss disorder display distance divert divide divorce dizzy doctor document dog doll dolphin domain donate donkey donor door dose double dove draft dragon drama draw dream dress drift drill drink drip drive drop drum dry duck dumb dune during dust dutch duty dwarf dynamic eager eagle early earn earth easily east easy echo ecology economy edge edit educate effort egg eight either elbow elder electric elegant element elephant elevator elite else embark embody emerge emotion employ empower empty enable enact end endless endorse enemy energy enforce engage engine enhance enjoy enlist enough enrich enter entire entry envelope episode equal equip era erase erode erosion error erupt escape essay essence estate ethics evidence evil evoke evolve exact example excess exchange excite exclude excuse execute exhaust exhibit exile exist exit exotic expand expect expire explain expose express extend extra eye eyebrow fabric face faculty fade faint faith fall false fame family famous fan fancy farm fashion fat fatal father fatigue favorite feature february federal fee feed feel female fence festival fetch fever few fiber fiction field figure file film filter final find fine finger finish fire firm first fiscal fish fit fitness fix flag flame flash flat flavor flee flight flip float flock floor flower fluid flush fly foam focus fog foil fold follow food foot force forest forget fork fortune forum forward fossil foster found fox fragile frame frequent fresh friend fringe frog front frost frown frozen fruit fuel fun funny furnace fury future gadget gain galaxy gallery game gap garage garbage garden garlic garment gas gaze gear gender genre gentle genuine gesture get ghost giant gift giraffe girl give glad glance glass glide glimpse globe gloom glory glove glow glue goat goddess gold good goose gorilla gospel gossip govern gown grab grace grain grant grape grass gravity great green grid grief grit grocery group grow grunt guard guess guide guilt guitar gun gym habit hair half hammer hamster hand happy harbor hard harsh harvest hat have hawk hazard head health heart heavy hedgehog height hello helmet help hen hero hidden high hill hint hip hire history hobby hockey hold hole holiday hollow home honey hood hope horn horror horse hospital host hotel hour hover hub huge human humble humor hundred hungry hunt hurdle hurry husband hybrid ice icon idea identify idle ignore ill illegal illness image imitate immense immune impact impose improve impulse inch include income increase index indicate indoor industry infant inflict inform inhale inherit initial inject injury inmate inner innocent input inquire insane insect inside inspire install intact interest into invest invite involve iron island isolate issue item ivory jacket jaguar jar jazz jeans jelly jewel job join joke journey joy judge juice jump jungle junior junk kangaroo keen keep ketchup key kick kid kidney kind kingdom kiss kit kitchen kite kitten kiwi knee knife knock know lab label labor ladder lake lamp language laptop large later laugh laundry lava law lawn lawsuit layer lazy leader leaf learn leave lecture left leg legal legend leisure lemon lend length lens leopard lesson letter level liberal library license life lift light like limb limit link lion liquid list live lizard load loan lobster local lock logic lonely long loop lottery loud lounge love loyal lucky luggage lumber lunar lunch luxury lyrics machine mad magic magnet maid mail main major make mammal man manage mandate mango mansion manual maple marathon margin marine market marriage mask mass master match material math matrix matter maximum maze meadow mean measure meat mechanic medal media melody melt member mention menu mercy merge merit merry mesh message metal method middle midnight milk million mimic mind minimum minor minute miracle mirror misery miss mistake mix mixed mixture mobile model modify mom moment monday money monitor monkey monster month moon moral more morning mosquito mother motion motor mountain mouse move movie much muffin mule multiply muscle museum mushroom music must mutual myself mystery myth naive name napkin narrow nasty nation nature near neck need negative neglect neither nephew nerve nest net network neutral never news next nice night noble noise nominee noodle normal north nose notable note nothing notice novel now nuclear number nurse nut oak obey object oblige obscure observe obtain obvious occur ocean october odor off offer office often oil okay old olive olympic omit once one onion online only open opera opinion oppose option orange orbit order ordinary organ orient original orphan ostrich other outdoor outer output outside oval oven over own owner oxygen oyster ozone pact paddle page pair palace palm panda panel panic panther paper parade parent park parrot party pass patch path patient pattern pause pave payment peace peanut pear peasant pelican pen penalty pencil people pepper perfect permit person pet phone photo phrase physical piano picnic picture piece pig pigeon pill pilot pink pioneer pipe pistol pitch pizza place planet plastic plate play please pledge pluck plug plunge poem poet point polar pole police pond pony pool popular portion position possible post potato pottery poverty powder power practice praise predict prefer prepare present pretty prevent price pride primary print priority prison private prize problem process promote proof property prosper protect proud provide public pudding pull pulp pulse pumpkin punch pupil puppy purchase purity purpose purse push put puzzle pyramid quality quantum quarter question quick quit quiz quote rabbit raccoon race rack radar radio rail rain raise rally ramp ranch random range rapid rare rate rather raven raw razor ready real reason rebel rebuild recall receive recipe record recycle reduce reflect reform refuse region regret regular reject relax release relief rely remain remember remind remove render renew rent reopen repair repeat replace report require rescue resemble resist resource response result retire return reunion reveal review reward rhythm rib ribbon rice rich ride ridge rifle right rigid ring riot ripple risk ritual rival river road roast robot robust rocket romance roof rookie room rose rotate rough round route royal rubber rude rug rule run rural sad saddle sadness safe sail salad salmon salon salt salute same sample sand satisfy satoshi sauce sausage save say scale scan scare scatter scene scheme school science scissors scorpion scout scrap screen script scrub sea search season seat second secret section security seed seek segment select sell seminar senior sense sentence series service session settle seven shadow shaft shallow share shed shell sheriff shield shift shine ship shiver shock shoe shoot shop short shoulder shove shrimp shrug shuffle shy sibling sick side siege sight sign silent silk silly silver similar simple since sing siren sister situate six size skate sketch ski skill skin skirt skull slab slam sleep slender slice slide slight slim slogan slot slow slush small smart smile smoke smooth snack snake snap sniff snow soap soccer social sock soda soft solar soldier solid solution solve someone song soon sorry sort soul sound soup source south space spare spatial spawn speak special speed spell spend sphere spice spider spike spin spirit split spoil sponsor spoon sport spot spray spread spring spy square squeeze squirrel stable stadium staff stage stairs stamp stand start state stay steel stem step stereo stick still sting stock stomach stone stool story stove strategy street strike strong struggle student stuff stumble style subject submit subway success such sudden suffer sugar suggest suit summer sun sunny sunset super supply supreme sure surface surge surprise surround survey suspect sustain swallow swamp swap swarm swear sweet swift swim swing switch sword symbol symptom syndrome system table tackle tag tail talent talk tank tape target task taste tattoo taxi teach team tell ten tenant tennis tent term test text thank that theme then theory there they thing this thought three thrive throw thumb thunder ticket tide tiger tilt timber time tiny tip tired tissue title toast tobacco today toddler toe together toilet token tomato tomorrow tone tongue tonight tool tooth top topic topple torch total tourist toward tower town toy track trade traffic tragic train transfer trap trash travel tray treat tree trend trial tribe trick trigger trim trip trophy trouble truck true truly trumpet trust truth try tube tuition tumble tuna tunnel turkey turn turtle twelve twenty twice twin twist two type typical ugly umbrella unable uncles uncover under undo unfair unfold unhappy uniform unique unit universe unknown unlock until unusual unveil update upgrade uphold upon upper upset urban urge usage use used useful useless usual utility vacant vacuum vague valid valley valve vanish vegetable vendor venue verb verify version very vessel veteran viable vibrant vicious victory video view village vintage violin virtual virus visa visit visual vital vivid vocal voice void volcano volume vote voyage wage wagon wait walk wall walnut want warfare warm warrior wash waste water wave way wealth weapon wear weather web wedding weekend weird welcome west wet whale what wheat wheel when where which while whip whisper wide width wife wild will win window wine wing wink winner winter wire wisdom wise wish witness wolf woman wonder wood wool word work world worry worth wrap wreck wrestle wrist write wrong yard year yellow yes yesterday you young youth zebra zero zone zoo
WORDLIST
	)
	local result=()
	for idx in "${indices[@]}"; do
		result+=("${words[idx]}")
	done
	echo "${result[*]}"
}
verify_contact() {
	local name="$1"
	local f="$CONTACTS_DIR/$name.json"
	[[ -f "$f" ]] || die "Contact not found"
	echo "Fingerprint: $(jq -r .fingerprint "$f")"
	confirm "Mark verified?" || die "Cancelled"
	jq '.verified=true' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
	log_ok "Contact '$name' verified"
}

pad_to_bucket() {
	# Prints base64 of: 8 lowercase-hex length header || message || random pad,
	# so the plaintext reaches exactly the chosen bucket size (including header).
	# The length is counted in BYTES (${#} counts characters, which breaks on
	# multibyte input), so the header always matches the true payload size.
	local in="$1"
	local len bucket="" b sz pad
	len=$(printf '%s' "$in" | wc -c | tr -d ' ')
	for b in "${BUCKET_ORDER[@]}"; do
		((8 + len <= BUCKETS[$b])) && {
			bucket=$b
			break
		}
	done
	[[ -n "$bucket" ]] || die "Message too large (max $((BUCKETS[64k] - 8)) bytes)"
	sz=$((BUCKETS[$bucket] - 8))
	pad=$((sz - len))
	{
		printf '%08x' "$len"
		printf '%s' "$in"
		head -c "$pad" /dev/urandom
	} | base64 -w0
}

unpad_message() {
	# ARG: base64 of padded bucket. Writes the original message to stdout.
	# The decoded blob is materialised in a 0600 scratch file: piping it into
	# `head` risks a SIGPIPE kill under set -o pipefail, and the random pad
	# may contain NUL bytes which command substitution would strip. Only the
	# message body (never the pad, which can hold NULs) passes through a
	# shell variable, and only up to the byte length the header states.
	local b64="$1" tmp n
	tmp=$(mktemp "${DATA_DIR:-/tmp}/unpad.XXXXXX")
	printf '%s' "$b64" | base64 -d >"$tmp" || {
		rm -f "$tmp"
		return 1
	}
	n=$((16#$(head -c 8 "$tmp")))
	((n >= 0 && n <= BUCKETS[64k])) || {
		rm -f "$tmp"
		return 1
	}
	dd if="$tmp" bs=1 skip=8 count="$n" 2>/dev/null
	rm -f "$tmp"
}

sign_message() { printf '%s' "$1" | ssh-keygen -Y sign -f "$2" -n "x-courier" | base64 -w0; }

# verify_signature MSG SIG_B64 SSH_PUBKEY — uses `ssh-keygen -Y verify` only.
verify_signature() {
	local msg="$1" sig="$2" pub="$3" tmpd ok=0
	[[ "$pub" == ssh-ed25519\ * || "$pub" == ssh-rsa\ * ]] || return 1
	tmpd=$(mktemp -d)
	printf '* %s\n' "$pub" >"$tmpd/signers"
	printf '%s' "$sig" | base64 -d >"$tmpd/sig" 2>/dev/null || {
		rm -rf "$tmpd"
		return 1
	}
	chmod 600 "$tmpd/sig" "$tmpd/signers"
	printf '%s' "$msg" | ssh-keygen -Y verify -f "$tmpd/signers" -I '*' -n "x-courier" -s "$tmpd/sig" >/dev/null 2>&1 && ok=1
	rm -rf "$tmpd"
	[[ $ok -eq 1 ]]
}

make_signed_bundle() {
	local pt="$1"
	local recip_fp="$2"
	local expiry="${3:-}"
	local payload msg_id ts sender_fp canon sig
	payload=$(pad_to_bucket "$pt") || die "Message too large (max $((BUCKETS[64k] - 8)) bytes)"
	msg_id=$(head -c16 /dev/urandom | xxd -p -c 32) || die "msg_id RNG failed"
	ts=$(date -u +%Y-%m-%dT%H:%M:%SZ) || die "date failed"
	sender_fp=$(get_fingerprint) || die "fingerprint failed"
	canon=$(jq -c -S -n --arg v 1 --arg mid "$msg_id" --arg ts "$ts" --arg sfp "$sender_fp" --arg rfp "$recip_fp" --arg exp "$expiry" --arg pl "$payload" '{v:1, msg_id:$mid, timestamp:$ts, sender_fp:$sfp, recipient_fp:$rfp, expiry:$exp, payload:$pl}') || die "canon build failed"
	sig=$(sign_message "$canon" "$SSH_PRIVKEY_FILE") || die "sign failed"
	printf '%s' "$canon" | jq --arg sig "$sig" '. + {sig: $sig}' || die "sig embed failed"
}

verify_signed_bundle() {
	local b="$1"
	local sender_ssh="$2"
	local sig canon exp rfp payload
	sig=$(printf '%s' "$b" | jq -r .sig)
	canon=$(printf '%s' "$b" | jq -c -S 'del(.sig)')
	verify_signature "$canon" "$sig" "$sender_ssh" || return 1
	exp=$(printf '%s' "$b" | jq -r .expiry)
	if [[ "$exp" != "null" && -n "$exp" ]]; then
		[[ $(date -u +%s) -lt $(date -u -d "$exp" +%s) ]] || die "Message expired"
	fi
	rfp=$(printf '%s' "$b" | jq -r .recipient_fp)
	[[ "$rfp" == "$(get_fingerprint)" ]] || die "Not for this recipient"
	printf '%s' "$b" | jq -r .payload
}

replay_check() {
	local h
	h=$(echo -n "$1" | sha256sum | cut -d' ' -f1)
	[[ -f "$REPLAY_DIR/seen.hashes" ]] && grep -q "^$h$" "$REPLAY_DIR/seen.hashes"
}
replay_mark() {
	local h
	h=$(echo -n "$1" | sha256sum | cut -d' ' -f1)
	echo "$h" >>"$REPLAY_DIR/seen.hashes"
}

cmd_init() {
	[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && {
		echo "Usage: xc init"
		echo "Creates your age + SSH keys and encrypts them with a passphrase."
		echo "You will be asked to type the passphrase in this terminal."
		exit 0
	}
	[[ $# -gt 0 ]] && die "Unknown: $1. xc init takes no options. Keys are encrypted with a passphrase you type when prompted."
	[[ -f "$IDENTITY_DIR/age.pub" ]] && die "Identity exists. Use 'xc wipe'."
	generate_identity
}

cmd_id() {
	local qr=false
	[[ "${1:-}" == "--qr" ]] && qr=true
	load_identity
	local fp
	fp=$(get_fingerprint)
	echo "Age: $AGE_PUBKEY"
	echo "SSH: $SSH_PUBKEY"
	echo "Fingerprint: $fp"
	echo "6-word: $(fingerprint_words "$fp")"
	$qr && echo "age:$AGE_PUBKEY|ssh:$SSH_PUBKEY|fp:$fp" | qrencode -t UTF8
	cleanup_identity
}

cmd_add() {
	local name=$1
	[[ "$name" =~ ^[A-Za-z0-9_-]{1,32}$ ]] || die "Invalid name"
	[[ -f "$CONTACTS_DIR/$name.json" ]] && die "Contact exists"
	local data
	case ${2:-paste} in
	paste) data=$(cat) ;;
	file)
		[[ -f "$3" ]] || die "File not found"
		data=$(cat "$3")
		;;
	qr) die "QR not implemented" ;;
	*) die "Unknown method" ;;
	esac
	local ap
	ap=$(echo "$data" | grep -o 'age1[0-9a-z]*' | head -1)
	local sp
	sp=$(echo "$data" | grep -oE 'ssh-ed25519 [A-Za-z0-9+/]+' | head -1)
	local fp
	fp=$(echo "$data" | grep -oE 'SHA256:[A-Za-z0-9+/=]{40,64}' | head -1)
	[[ -n "$ap" && -n "$sp" && -n "$fp" ]] || die "Invalid data: need an age key, an ssh-ed25519 key and a SHA256:... fingerprint (from 'xc id')"
	[[ "$ap" =~ ^age1[0-9a-z]{58}$ ]] || die "Invalid age pubkey"
	[[ "$sp" =~ ^ssh-ed25519\ [A-Za-z0-9+/]+=*$ ]] || die "Invalid SSH pubkey"
	cat >"$CONTACTS_DIR/$name.json" <<EOF
{"name":"$name","age_pub":"$ap","ssh_pub":"$sp","fingerprint":"$fp","verified":false}
EOF
	chmod 600 "$CONTACTS_DIR/$name.json"
	echo "Added '$name' (unverified). Fingerprint: $fp"
	echo "Verify in person, then: xc verify $name"
}

cmd_verify() { verify_contact "$1"; }

cmd_send() {
	local recip="" expires=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--expires)
			expires="${2:-}"
			shift 2
			;;
		*)
			recip="${1:-}"
			shift
			;;
		esac
	done
	[[ -n "$recip" ]] || die "Usage: xc send <friend> [--expires <ISO date>]"
	local cf="$CONTACTS_DIR/$recip.json"
	[[ -f "$cf" ]] || die "Contact not found: $recip"
	[[ $(jq -r .verified "$cf") == "true" ]] || die "Contact '$recip' is not verified. Meet in person, compare fingerprints, then run: xc verify $recip"
	local msg
	msg=$(cat)
	[[ -n "$msg" ]] || die "No message on stdin"
	# Early size check: reject oversize BEFORE any passphrase prompt or
	# key work. Plain words per spec. Must match the bucket limit exactly.
	local msg_bytes
	msg_bytes=$(printf '%s' "$msg" | wc -c | tr -d ' ')
	((msg_bytes <= BUCKETS[64k] - 8)) || die "This message is too long. Maximum is 64 KiB."
	load_identity
	local rap rfp bundle
	rap=$(jq -r .age_pub "$cf")
	rfp=$(jq -r .fingerprint "$cf")
	bundle=$(make_signed_bundle "$msg" "$rfp" "$expires") || die "bundle build failed"
	printf 'X-COURIER/1\n' >message.courier.tmp
	printf '%s' "$bundle" | age -e -r "$rap" >>message.courier.tmp || die "age encrypt failed"
	mv message.courier.tmp message.courier
	cleanup_identity
	# Post-seal assertion: the payload that went into age (base64 of the
	# padded bucket) must decode to exactly one of the bucket sizes.
	# We can't check the final courier size because age encryption adds
	# random IV/salt — identical inputs give different ciphertexts.
	local pl_b64
	pl_b64=$(jq -r .payload <<<"$bundle") || die "bundle payload extract failed"
	local pl_decoded
	pl_decoded=$(printf '%s' "$pl_b64" | base64 -d 2>/dev/null | wc -c | tr -d ' ')
	# Check against bucket sizes (numeric constants, not globs)
	if [[ "$pl_decoded" -eq ${BUCKETS[1k]} || "$pl_decoded" -eq ${BUCKETS[4k]} || "$pl_decoded" -eq ${BUCKETS[16k]} || "$pl_decoded" -eq ${BUCKETS[64k]} ]]; then
		: # valid bucket size
	else
		die "INTERNAL ERROR: payload decoded size $pl_decoded is not a valid bucket (logic bug)"
	fi
	{
		printf '[OK] Sealed to %s: message.courier\n' "$recip"
		printf '[INFO] Payload bucket: %s bytes\n' "$msg_bytes"
	}
}

cmd_read() {
	local file="${1:-}"
	[[ -n "$file" ]] || die "Usage: xc read <file|->"
	# The courier body is binary age ciphertext: it must never pass through
	# a shell variable (command substitution strips NUL bytes). The whole
	# input is materialised to a 0600 scratch file first; only the text
	# header is inspected and the body is sliced inside the file.
	local body_scratch body_tmp
	[[ -d "$DATA_DIR" ]] || die "No data directory. Run 'xc init' first."
	body_scratch=$(mktemp "$DATA_DIR/body.XXXXXX")
	if [[ "$file" == "-" ]]; then
		cat >"$body_scratch"
	else
		[[ -f "$file" ]] || {
			rm -f "$body_scratch"
			die "Not found: $file"
		}
		cp -- "$file" "$body_scratch"
	fi
	if ! head -1 "$body_scratch" | grep -q '^X-COURIER/1'; then
		rm -f "$body_scratch"
		die "Not a .courier file"
	fi
	body_tmp="$body_scratch.tmp"
	tail -c +13 "$body_scratch" >"$body_tmp" && mv "$body_tmp" "$body_scratch"
	load_identity
	local bundle sfp found f payload pt mid
	bundle=$(age -d -i "$AGE_PRIVKEY_FILE" <"$body_scratch") || {
		rm -f "$body_scratch"
		cleanup_identity
		die "This file cannot be opened with your keys: it is not for you, was made for a different identity, or was corrupted"
	}
	rm -f "$body_scratch"
	sfp=$(printf '%s' "$bundle" | jq -r .sender_fp)
	found=""
	for f in "$CONTACTS_DIR"/*.json; do
		[[ -f "$f" ]] || continue
		[[ "$(jq -r .fingerprint "$f")" == "$sfp" ]] && {
			found=$f
			break
		}
	done
	[[ -n "$found" ]] || die "Unknown sender (fingerprint $sfp). Add the sender with 'xc add' before opening their mail."
	payload=$(verify_signed_bundle "$bundle" "$(jq -r .ssh_pub "$found")") || die "Signature check FAILED. Do not trust this message."
	[[ -n "${XCDEBUG:-}" ]] && printf 'DBG bundle_len=%s payload_len=%s payload_head=%s\n' "${#bundle}" "${#payload}" "${payload:0:12}" >&2
	[[ $(jq -r .verified "$found") == "true" ]] || log_warn "Sender '$(jq -r .name "$found")' is not yet verified; signature came from their registered key."
	pt=$(unpad_message "$payload")
	mid=$(printf '%s' "$bundle" | jq -r .msg_id)
	if replay_check "$mid"; then
		rm -f "$body_scratch" 2>/dev/null || true
		cleanup_identity
		die "Replay detected: this exact message was already opened"
	fi
	replay_mark "$mid"
	cleanup_identity
	echo "$pt"
	log_ok "Decrypted from $sfp (msg_id $mid)"
}

cmd_doctor() {
	log_info "Doctor"
	for t in age age-keygen ssh-keygen ssh qrencode zbarimg; do
		if command -v "$t" >/dev/null; then log_ok "$t"; else log_warn "$t missing"; fi
	done
	if [[ -d "$DATA_DIR" ]] && [[ $(stat -c %a "$DATA_DIR") == "700" ]]; then log_ok "Data dir 700"; else log_warn "Data dir perms"; fi
	if unshare -rn true 2>/dev/null; then log_ok "unshare -rn works"; else log_warn "unshare -rn needs root"; fi
	if [[ -z "${HISTFILE:-}" ]]; then log_ok "HISTFILE unset"; else log_warn "HISTFILE set"; fi
}

cmd_selftest() {
	# No passphrase is involved here: full round-trip testing lives in tests/
	# and is driven with a pseudo-terminal through tests/helpers/pty_drive.py.
	log_info "Self-test"
	local fails=0 t
	bash -n "$0" || fails=1
	for t in age age-keygen ssh-keygen ssh qrencode zbarimg jq; do
		command -v "$t" >/dev/null || {
			log_err "missing tool: $t"
			fails=1
		}
	done
	# Padding invariants: the header length decodes to the message length.
	local pb pt nb
	pb=$(pad_to_bucket "hello")
	pt=$(unpad_message "$pb")
	[[ "$pt" == "hello" ]] || {
		log_err "unpad broken"
		fails=1
	}
	nb=$(printf '%s' "$pt" | wc -c | tr -d ' ')
	[[ "$nb" == "5" ]] || {
		log_err "padding header broken"
		fails=1
	}
	# Replay cache round trip in a throwaway dir.
	local rd
	rd=$(mktemp -d)
	REPLAY_DIR="$rd" replay_mark "id-a"
	if REPLAY_DIR="$rd" replay_check "id-a"; then log_ok "replay cache works"; else
		log_err "replay cache broken"
		fails=1
	fi
	rm -rf "$rd"
	if [[ $fails -eq 0 ]]; then log_ok "Self-test passed"; else die "Self-test failed"; fi
}

show_menu() {
	cat <<'EOF'
  X-COURIER

  What do you want to do?

   1  Write a secret message
   2  Open a secret message
   3  Add a friend
   4  Show my ID to a friend
   5  Check everything is OK
   0  Leave

  Type a number and press Enter:
EOF
	read -r c
	case $c in 1) echo "NYI" ;; 2) echo "NYI" ;; 3) echo "NYI" ;; 4) cmd_id ;; 5) cmd_doctor ;; 0) exit ;; *) echo "Invalid" ;; esac
}

main() {
	local cmd="${1:-menu}"
	shift || true
	case $cmd in
	--help | help)
		cat <<EOF
X Messenger Terminal — Offline Encrypted Courier

Usage: xc <command> [options]
Commands: init, id, add, verify, send, read, doctor, selftest, wipe, rotate, prekeys, qr-send, qr-read
Examples: xc init; xc id --qr; echo "msg" | xc send alice; xc read file.courier
EOF
		exit 0
		;;
	init) cmd_init "$@" ;; id) cmd_id "$@" ;; add) cmd_add "$@" ;; verify) cmd_verify "$@" ;;
	send) cmd_send "$@" ;; read) cmd_read "$@" ;; doctor) cmd_doctor ;; selftest) cmd_selftest ;; wipe) cmd_wipe ;; rotate) cmd_rotate ;; prekeys) cmd_prekeys ;; qr-send) cmd_qr_send ;; qr-read) cmd_qr_read ;;
	--version) echo "X Messenger Terminal $VERSION" ;;
	menu | "") show_menu ;;
	*) die "Unknown: $cmd. Run 'xc --help'." ;;
	esac
}

trap cleanup_identity EXIT INT TERM HUP
cmd_wipe() {
	echo "NOT IMPLEMENTED: wipe" >&2
	exit 1
}

cmd_rotate() {
	echo "NOT IMPLEMENTED: rotate" >&2
	exit 1
}

cmd_prekeys() {
	echo "NOT IMPLEMENTED: prekeys" >&2
	exit 1
}

cmd_qr_send() {
	echo "NOT IMPLEMENTED: qr-send" >&2
	exit 1
}

cmd_qr_read() {
	echo "NOT IMPLEMENTED: qr-read" >&2
	exit 1
}

main "$@"
