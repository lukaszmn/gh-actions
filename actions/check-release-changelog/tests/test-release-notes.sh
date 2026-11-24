#!/usr/bin/env bash
# Runs release-notes.sh (the check, and publish-github-release's notes) on scratch CHANGELOGs.
# Run: bash actions/check-release-changelog/tests/test-release-notes.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
SCRIPT=${1:-$here/../release-notes.sh}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/work"
fail=0
ok() { echo "PASS $1"; }
bad() { echo "FAIL $1"; sed 's/^/  out: /' "$T/out"; fail=1; }

changelog() { printf '%s\n' "$@" > "$T/work/CHANGELOG.md"; }
CL=(
  '# Changelog' ''
  '## [Unreleased]' ''
  '## [3.31] - 2026-11-24' '' '### Added' '- **One** thing.' '' '### Fixed' '- Another.' ''
  '## [3.3] - 2026-05-30' '' '- Old three-three.' ''
  '## [3.30] - 2026-11-21' '' '- Old.'
)
run() { # NAME=VALUE overrides
  local VERSION_TAG=v3.31 VERSION_TAG_PATTERN='^v[0-9]+(\.[0-9]+)*(-[0-9A-Za-z.-]+)?$' \
        CHANGELOG_PATH=CHANGELOG.md
  local kv; for kv in "$@"; do local "${kv%%=*}=${kv#*=}"; done
  rm -f "$T/notes.md"
  # env -i: only what action.yml passes, so set -u catches a read of anything else.
  (cd "$T/work" && env -i PATH="$PATH" VERSION_TAG="$VERSION_TAG" \
    VERSION_TAG_PATTERN="$VERSION_TAG_PATTERN" CHANGELOG_PATH="$CHANGELOG_PATH" \
    NOTES_PATH="$T/notes.md" bash "$SCRIPT") > "$T/out" 2>&1
}
notes() { cat "$T/notes.md"; }

changelog "${CL[@]}"
run; [[ $? == 0 && $(notes) == $'\n### Added\n- **One** thing.\n\n### Fixed\n- Another.' ]] &&
  ok "a tag made by the release script passes; notes are its section only" || bad "3.31"
run VERSION_TAG=v3.3; [[ $? == 0 && $(notes) == $'\n- Old three-three.' ]] &&
  ok "v3.3 takes [3.3], not [3.31] or [3.30]" || bad "3.3"
changelog '## [3x31] - 2026-01-01' '- Wrong.' '## [3.31] - 2026-11-24' '- Right.'
run; [[ $? == 0 && $(notes) == '- Right.' ]] && ok "a dot is not a wildcard" || bad "dot"

# A long section is never refused (SIGPIPE under pipefail, if the check piped into grep -q).
big=(); for ((n = 0; n < 4000; n++)); do big+=("- Entry number $n of a long release, padded out to some width."); done
changelog '## [3.31] - 2026-11-24' "${big[@]}"
bigfail=0; for ((n = 0; n < 10; n++)); do run || bigfail=1; done
[[ $bigfail == 0 ]] && ok "a section of ~250 KB passes, every time" || bad "long section"

refused() { # LABEL EXPECTED-MESSAGE-PART NAME=VALUE...
  local label=$1 msg=$2; shift 2
  run "$@"
  [[ $? != 0 ]] && grep -qF -- "$msg" "$T/out" && ok "refused: $label" || bad "refused: $label"
}
# The hand-made tag: main's CHANGELOG still has everything under [Unreleased].
changelog '## [Unreleased]' '' '### Added' '- Not released yet.' '' '## [3.30] - 2026-11-21' '- Old.'
refused "a tag pushed by hand ([Unreleased] never moved)" "Was v3.31 tagged by hand? Release with the project's release script"
refused "it names the missing section" "no entries under '## [3.31] - <date>'"
changelog '## [Unreleased]' '' '## [3.31] - 2026-11-24' '' '### Added' '' '## [3.30] - 2026-11-21' '- Old.'
refused "a section of headings only" "no entries under '## [3.31] - <date>'"
changelog "${CL[@]}"
refused "a branch name as the tag" "does not look like a version tag" VERSION_TAG=main
refused "an empty tag" "version_tag is empty" VERSION_TAG=
refused "no checkout" "nope/CHANGELOG.md not found" CHANGELOG_PATH=nope/CHANGELOG.md

# action.yml hands the script every variable it reads, by the same name.
action=$here/../action.yml
miss=; for v in $(grep -oE '\$\{?[#!]?[A-Z_][A-Z0-9_]*' "$SCRIPT" | tr -d '${#!' | sort -u); do
  grep -qE "^        $v: " "$action" || miss+=" $v"
done
[[ -z $miss ]] && ok "action.yml sets every variable the script reads" || { echo "FAIL action.yml env lacks:$miss"; fail=1; }

exit $fail
