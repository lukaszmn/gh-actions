#!/usr/bin/env bash
# Tests ssh-pinned.sh (host key pinning, shell quoting) with throwaway host keys; no
# network, no server. Run: bash actions/deploy-docker-compose/tests/test-ssh-pinned.sh
set -u
source "${1:-$(dirname "$0")/../ssh-pinned.sh}"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cd "$W"
for t in ed25519 ecdsa rsa; do ssh-keygen -q -t $t -N '' -f hk_$t; done
# fake ssh-keyscan output: "host type key"
scan() { for t in "$@"; do printf 'example.org %s\n' "$(cut -d' ' -f1,2 hk_$t.pub)"; done; }
ed=$(ssh-keygen -lf hk_ed25519.pub | awk '{print $2}')
ec=$(ssh-keygen -lf hk_ecdsa.pub | awk '{print $2}')
fail=0
check() { # name expected_rc expected_line_count input-fp scan-types...
  local name=$1 erc=$2 elines=$3 fp=$4; shift 4
  out=$(scan "$@" | pin_known_hosts "$fp" 2>err); rc=$?
  n=$(printf '%s' "$out" | grep -c . || true)
  if [[ $rc == "$erc" && $n == "$elines" ]]; then echo "PASS $name"; else echo "FAIL $name rc=$rc lines=$n"; cat err; fail=1; fi
}
check "bare ed25519 fp, server has 3 keys"   0 1 "$ed" ecdsa rsa ed25519
check "whole ssh-keygen -lf line"            0 1 "$(ssh-keygen -lf hk_ed25519.pub)" ecdsa rsa ed25519
check "padding = accepted"                   0 1 "${ed}=" ed25519
check "ecdsa fp picks ecdsa"                 0 1 "$ec" ecdsa rsa ed25519
check "two fps (rotation) both present"      0 2 "$ed $ec" ecdsa rsa ed25519
check "wrong fp"                             1 0 "SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" ecdsa rsa ed25519
check "right fp, but key not served (MITM)"  1 0 "$ed" ecdsa rsa
check "nothing scanned"                      1 0 "$ed"
check "no SHA256 token (MD5 given)"          2 0 "MD5:aa:bb:cc" ed25519
check "fingerprint prefix only must not match" 1 0 "${ed:0:20}" ed25519
# matched line is exactly the ed25519 one
line=$(scan ecdsa rsa ed25519 | pin_known_hosts "$ed" 2>/dev/null)
[[ "$line" == "example.org $(cut -d' ' -f1,2 hk_ed25519.pub)" ]] && echo "PASS exact line kept" || { echo "FAIL exact line"; fail=1; }
# comment lines from keyscan are skipped
out=$( { echo "# example.org:22 SSH-2.0-OpenSSH"; scan ed25519; } | pin_known_hosts "$ed" 2>/dev/null); [[ $(grep -c . <<<"$out") == 1 ]] && echo "PASS comments skipped" || { echo FAIL comments; fail=1; }
# sh_quote round-trips nasty values through sh
for v in "plain" "it's" "a b" '$(touch PWNED)' '`id`' "multi
line" "'" "''" "\\" ""; do
  got=$(sh -c "x=$(sh_quote "$v"); printf '%s' \"\$x\"")
  [[ "$got" == "$v" ]] || { echo "FAIL sh_quote [$v] -> [$got]"; fail=1; }
done
[[ -e PWNED ]] && { echo "FAIL injection"; fail=1; } || echo "PASS sh_quote round-trip, no injection"
exit $fail
