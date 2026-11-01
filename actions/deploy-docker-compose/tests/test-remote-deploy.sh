#!/usr/bin/env bash
# Drives remote-deploy.sh the way the pinned path does (assignments + script on stdin to
# `sh -s`), with a fake `docker` that logs its argv, its stdin and APP_TAG from its env.
# Run: bash actions/deploy-docker-compose/tests/test-remote-deploy.sh
# (SHELL_UNDER_TEST="busybox sh" or bash to try another remote shell; default sh.
#  MODE=legacy runs it as the appleboy path does: `$SHELL -c "<assignments + script>"`.)
set -u
here=$(dirname "$0")
SCRIPT=${1:-$here/../remote-deploy.sh}; HELPERS=${2:-$here/../ssh-pinned.sh}
source "$HELPERS"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/srv"
cat > "$T/bin/docker" <<'D'
#!/bin/sh
{ printf 'ARGV:'; printf ' [%s]' "$@"; printf ' APP_TAG_ENV=[%s] DEPLOY_VARS_IN_ENV=%s' "${APP_TAG-<unset>}" "$(env | grep -c '^DEPLOY_')"; echo; } >> "$FAKE_LOG"
case "$1" in login) printf 'STDIN:' >> "$FAKE_LOG"; cat >> "$FAKE_LOG"; echo >> "$FAKE_LOG";; esac
[ "$1 $2 ${4-}" = "compose -f pull" ] && [ -n "${FAKE_PULL_FAIL:-}" ] && exit 1
# a command that reads stdin must not eat the rest of the script
[ "$1 ${4-}" = "compose up" ] && cat >/dev/null
exit 0
D
chmod +x "$T/bin/docker"
export FAKE_LOG="$T/log"
fail=0
run() { # env assignments as NAME=VALUE args
  : > "$FAKE_LOG"
  local DEPLOY_PATH="$T/srv" DEPLOY_COMPOSE_FILE=docker-compose.yml DEPLOY_REGISTRY=ghcr.io \
        DEPLOY_REGISTRY_USERNAME=lukaszmn DEPLOY_REGISTRY_TOKEN='s3cr3t-tok' DEPLOY_APP_TAG=''
  local kv; for kv in "$@"; do local "${kv%%=*}=${kv#*=}"; done
  local payload
  payload=$(for name in DEPLOY_PATH DEPLOY_COMPOSE_FILE DEPLOY_REGISTRY DEPLOY_REGISTRY_USERNAME DEPLOY_REGISTRY_TOKEN DEPLOY_APP_TAG; do
      printf '%s=%s\n' "$name" "$(sh_quote "${!name}")"; done; cat "$SCRIPT")
  if [[ ${MODE:-stdin} == stdin ]]; then
    # the pinned path: `ssh … 'sh -s'` with the payload on stdin
    printf '%s\n' "$payload" | env -u APP_TAG PATH="$T/bin:$PATH" ${SHELL_UNDER_TEST:-sh} -s > "$T/out" 2>&1
  else
    # the appleboy path: drone-ssh sends the payload as the exec command, run as `$SHELL -c`
    env -u APP_TAG PATH="$T/bin:$PATH" ${SHELL_UNDER_TEST:-sh} -c "$payload" > "$T/out" 2>&1
  fi
}
ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; cat "$T/out" "$FAKE_LOG"; fail=1; }
fresh() { printf '%b' "$1" > "$T/srv/.env"; chmod 640 "$T/srv/.env"; touch "$T/srv/docker-compose.yml"; }

fresh 'POSTGRES_PASSWORD=x\nAPP_TAG=latest\nPAID_EMAIL=a@b\n'
run; [[ $? == 0 && "$(cat "$T/srv/.env")" == $'POSTGRES_PASSWORD=x\nAPP_TAG=latest\nPAID_EMAIL=a@b' ]] && ok "no app_tag: .env untouched" || bad "no app_tag"
grep -q 'APP_TAG_ENV=\[<unset>\]' "$FAKE_LOG" && ! grep -q 'APP_TAG_ENV=\[[^<]' "$FAKE_LOG" && ok "no app_tag: APP_TAG not in compose's env" || bad "env leak"
! grep -q 'DEPLOY_VARS_IN_ENV=[1-9]' "$FAKE_LOG" && ok "no DEPLOY_* variable exported to docker" || bad "DEPLOY_* exported"
grep -q '^STDIN:s3cr3t-tok$' "$FAKE_LOG" && ! grep '^ARGV' "$FAKE_LOG" | grep -q s3cr3t && ok "password via stdin only" || bad "password handling"
grep -q 'ARGV: \[compose\] \[-f\] \[docker-compose.yml\] \[up\] \[-d\]' "$FAKE_LOG" && grep -q 'ARGV: \[image\] \[prune\] \[-f\]' "$FAKE_LOG" && ok "login, pull, up -d, prune all ran (up -d reads stdin)" || bad "sequence"

fresh 'A=1\nAPP_TAG=sha-0000000\nB=2\n'
run DEPLOY_APP_TAG=sha-abc1234; [[ "$(cat "$T/srv/.env")" == $'A=1\nAPP_TAG=sha-abc1234\nB=2' ]] && ok "existing line replaced in place" || bad "replace"
grep -q 'ARGV: \[compose\] \[-f\] \[docker-compose.yml\] \[pull\] APP_TAG_ENV=\[sha-abc1234\]' "$FAKE_LOG" && ok "pull sees the new tag" || bad "pull env"
[[ $(stat -c %a "$T/srv/.env") == 640 ]] && ok "mode kept" || bad "mode"
run DEPLOY_APP_TAG=sha-abc1234; [[ "$(cat "$T/srv/.env")" == $'A=1\nAPP_TAG=sha-abc1234\nB=2' ]] && ok "idempotent" || bad "idempotent"

fresh 'A=1\nAPP_TAG_OLD=keep\nB=2'   # no trailing newline, look-alike key
run DEPLOY_APP_TAG=v1.2.3; [[ "$(cat "$T/srv/.env")" == $'A=1\nAPP_TAG_OLD=keep\nB=2\nAPP_TAG=v1.2.3' ]] && ok "appended; look-alike key and last line kept" || bad "append"

fresh 'APP_TAG=a\nX=1\nexport APP_TAG=b\n APP_TAG =c\n'
run DEPLOY_APP_TAG=sha-1111111; [[ "$(cat "$T/srv/.env")" == $'APP_TAG=sha-1111111\nX=1' ]] && ok "duplicates collapsed to one" || bad "dupes"

fresh 'A=1\nAPP_TAG=sha-old0000\n'
export FAKE_PULL_FAIL=1
run DEPLOY_APP_TAG=sha-new0000; rc=$?
[[ $rc != 0 && "$(cat "$T/srv/.env")" == $'A=1\nAPP_TAG=sha-old0000' ]] && ok "failed pull: deploy fails, .env still names the running tag" || bad "pull failure"
! grep -q '\[up\]' "$FAKE_LOG" && ok "failed pull: no up -d" || bad "up after failed pull"
unset FAKE_PULL_FAIL

tagfail=0
for t in 'bad tag' '-x' '.x' "a\$(touch $T/PWNED)" 'a;b' "$(printf 'ok\nAPP_TAG=evil')" "$(printf 'x%.0s' {1..129})"; do
  fresh 'APP_TAG=keep\n'
  run "DEPLOY_APP_TAG=$t"; rc=$?
  [[ $rc != 0 && "$(cat "$T/srv/.env")" == 'APP_TAG=keep' && ! -e $T/PWNED ]] || { bad "invalid tag accepted: [$t]"; tagfail=1; }
done; [[ $tagfail == 0 ]] && ok "invalid tags rejected, .env untouched"

# A symlinked .env is written through, not replaced by a copy of the secrets.
mkdir -p "$T/secret"; printf 'POSTGRES_PASSWORD=x\nAPP_TAG=old\n' > "$T/secret/app.env"; chmod 600 "$T/secret/app.env"
rm -f "$T/srv/.env"; ln -s "$T/secret/app.env" "$T/srv/.env"
run DEPLOY_APP_TAG=sha-2222222
[[ -L "$T/srv/.env" && "$(cat "$T/secret/app.env")" == $'POSTGRES_PASSWORD=x\nAPP_TAG=sha-2222222' && $(stat -c %a "$T/secret/app.env") == 600 ]] \
  && ok "symlinked .env: link kept, target updated, mode kept" || bad "symlinked .env"
rm -f "$T/srv/.env"
# A read-only .env is not overwritten behind its back (the deploy fails instead).
if [[ $(id -u) != 0 ]]; then
  fresh 'APP_TAG=keep\n'; chmod 400 "$T/srv/.env"
  run DEPLOY_APP_TAG=sha-3333333; rc=$?
  [[ $rc != 0 && "$(cat "$T/srv/.env")" == 'APP_TAG=keep' ]] && ok "read-only .env: deploy fails, file untouched" || bad "read-only .env"
  chmod 600 "$T/srv/.env"
fi
[[ -z "$(ls "${TMPDIR:-/tmp}" | grep '^env.app-tag\.' || true)" ]] && ok "no temp copy of .env left behind" || bad "temp copy left"
fresh 'X=1\n'; run DEPLOY_REGISTRY_TOKEN=; [[ $? != 0 ]] && grep -q 'no registry credential' "$T/out" && ok "empty credential fails loudly" || bad "empty cred"
rm "$T/srv/.env"; touch "$T/srv/docker-compose.yml"; run; [[ $? != 0 ]] && grep -q '.env missing' "$T/out" && ok ".env missing fails" || bad "env missing"
fresh 'X=1\n'; run DEPLOY_PATH=; [[ $? != 0 ]] && grep -q 'deploy_path is empty' "$T/out" && ok "empty deploy_path fails" || bad "empty path"
fresh 'X=1\n'; run "DEPLOY_PATH=$T/srv/it's \$(touch $T/PWNED2)"; [[ ! -e $T/PWNED2 ]] && ok "quoted path: no injection" || bad "path injection"
exit $fail
