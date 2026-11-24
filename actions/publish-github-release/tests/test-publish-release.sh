#!/usr/bin/env bash
# Runs publish-release.sh against a fake `gh` that logs its argv (and the notes it was given),
# in a scratch working directory holding a CHANGELOG and files.
# Run: bash actions/publish-github-release/tests/test-publish-release.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
SCRIPT=${1:-$here/../publish-release.sh}
# The notes script where action.yml points (github.action_path is the action's folder).
NOTES_SCRIPT=${2:-$(sed -n 's|^        NOTES_SCRIPT: \${{ github.action_path }}|'"$here/.."'|p' "$here/../action.yml")}
[[ -f $NOTES_SCRIPT ]] || { echo "FAIL action.yml's NOTES_SCRIPT is no file: '$NOTES_SCRIPT'"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/work"
cat > "$T/bin/gh" <<'G'
#!/usr/bin/env bash
{ printf 'ARGV:'; printf ' [%s]' "$@"; echo; } >> "$FAKE_LOG"
if [[ "$1 $2" == "release view" ]]; then [[ -n ${FAKE_EXISTS:-} ]]; exit; fi
# What a create or an edit would publish as the body.
for ((i = 1; i <= $#; i++)); do
  if [[ ${!i} == --notes-file ]]; then j=$((i + 1)); printf 'NOTES:\n'; cat "${!j}"; printf 'END\n'; fi
done >> "$FAKE_LOG"
exit 0
G
chmod +x "$T/bin/gh"
export FAKE_LOG="$T/log"
fail=0
ok() { echo "PASS $1"; }
bad() { echo "FAIL $1"; sed 's/^/  out: /' "$T/out"; sed 's/^/  gh:  /' "$FAKE_LOG"; fail=1; }

changelog() { printf '%s\n' "$@" > "$T/work/CHANGELOG.md"; }
CL=(
  '# Changelog' ''
  '## [Unreleased]' ''
  '## [3.31] - 2026-11-24' '' '### Added' '- **One** thing.' '' '### Fixed' '- Another.' ''
  '## [3.3] - 2026-05-30' '' '- Old three-three.' ''
  '## [3.30] - 2026-11-21' '' '- Old.'
)
run() { # NAME=VALUE overrides
  : > "$FAKE_LOG"
  local VERSION_TAG=v3.31 VERSION_TAG_PATTERN='^v[0-9]+(\.[0-9]+)*(-[0-9A-Za-z.-]+)?$' \
        RELEASE_NAME='Release {tag}' CHANGELOG_PATH=CHANGELOG.md FILES='' FAKE_EXISTS=''
  local kv; for kv in "$@"; do local "${kv%%=*}=${kv#*=}"; done
  # env -i: only what action.yml passes, so set -u catches a read of anything else.
  (cd "$T/work" && env -i PATH="$T/bin:$PATH" HOME="$T" VERSION_TAG="$VERSION_TAG" \
    VERSION_TAG_PATTERN="$VERSION_TAG_PATTERN" RELEASE_NAME="$RELEASE_NAME" \
    CHANGELOG_PATH="$CHANGELOG_PATH" FILES="$FILES" NOTES_PATH="$T/notes.md" \
    NOTES_SCRIPT="$NOTES_SCRIPT" FAKE_EXISTS="$FAKE_EXISTS" FAKE_LOG="$FAKE_LOG" \
    bash "$SCRIPT") > "$T/out" 2>&1
}
gh_calls() { grep '^ARGV' "$FAKE_LOG"; }
notes() { sed -n '/^NOTES:$/,/^END$/p' "$FAKE_LOG" | sed '1d;$d'; }

changelog "${CL[@]}"

# A new release: created from the tag on GitHub, titled, with exactly the version's section.
run; rc=$?
[[ $rc == 0 && $(gh_calls) == $'ARGV: [release] [view] [v3.31]\nARGV: [release] [create] [v3.31] [--title] [Release v3.31] [--notes-file] ['"$T"'/notes.md] [--verify-tag]' ]] &&
  ok "new release: view, then create --verify-tag with the title" || bad "new release"
[[ $(notes) == $'\n### Added\n- **One** thing.\n\n### Fixed\n- Another.' ]] &&
  ok "notes: the 3.31 section only, up to the next heading" || bad "notes 3.31"

# The version's dots are literal, and [3.3] is not a prefix match of [3.31] nor the reverse.
run VERSION_TAG=v3.3; [[ $? == 0 && $(notes) == $'\n- Old three-three.' ]] &&
  ok "v3.3 takes [3.3], not [3.31] or [3.30]" || bad "3.3 section"
changelog '## [3x31] - 2026-01-01' '- Wrong.' '## [3.31] - 2026-11-24' '- Right.'
run; [[ $? == 0 && $(notes) == '- Right.' ]] && ok "a dot is not a wildcard" || bad "dot wildcard"
changelog "${CL[@]}"

# A re-run: the release is there, so it is edited (title + notes), never created again.
run FAKE_EXISTS=1; rc=$?
[[ $rc == 0 && $(gh_calls) == $'ARGV: [release] [view] [v3.31]\nARGV: [release] [edit] [v3.31] [--tag] [v3.31] [--verify-tag] [--draft=false] [--title] [Release v3.31] [--notes-file] ['"$T"'/notes.md]' ]] &&
  ok "re-run: edit (publishing a leftover draft, its tag verified), no create, no upload" || bad "re-run"

# Titles: {tag} and {version}.
run RELEASE_NAME='MediaDok {version}'
gh_calls | grep -qF '[--title] [MediaDok 3.31]' && ok "{version} is the tag without v" || bad "{version}"
run RELEASE_NAME='{tag} ({version})'
gh_calls | grep -qF '[--title] [v3.31 (3.31)]' && ok "{tag} and {version} together" || bad "{tag}"

# Files: globs expanded, a space in a name kept whole, blank lines and padding ignored.
mkdir -p "$T/work/dist"; touch "$T/work/dist/a.apk" "$T/work/dist/b c.exe" "$T/work/notes.txt"
run FILES=$'dist/*\n\n  notes.txt  \n'
gh_calls | grep -qF '[create] [v3.31] [dist/a.apk] [dist/b c.exe] [notes.txt] [--title]' &&
  ok "files: glob and plain name, a space in a name kept" || bad "files on create"
run FILES='dist/b c.exe'
gh_calls | grep -qF '[create] [v3.31] [dist/b c.exe] [--title]' &&
  ok "files: a plain name with a space is one file" || bad "space in a plain name"
run FILES='dist/*' FAKE_EXISTS=1
[[ $(gh_calls | sed -n 2p) == 'ARGV: [release] [upload] [v3.31] [dist/a.apk] [dist/b c.exe] [--clobber]' &&
   $(gh_calls | sed -n 3p) == 'ARGV: [release] [edit] [v3.31] '* ]] &&
  ok "re-run with files: upload --clobber, then publish" || bad "files on re-run"

# A long section (GitHub takes notes up to 125 000 characters): the check that it holds an entry
# must not die of SIGPIPE when it stops reading at the first one. 10 runs, as it is a race.
big=(); for ((n = 0; n < 4000; n++)); do big+=("- Entry number $n of a long release, padded out to some width."); done
changelog '## [3.31] - 2026-11-24' "${big[@]}"
bigfail=0; for ((n = 0; n < 10; n++)); do run || bigfail=1; done
[[ $bigfail == 0 ]] && ok "a section of ~250 KB is published, never refused" || bad "long section"
changelog "${CL[@]}"

# action.yml hands the script every variable it reads, by the same name.
action=$here/../action.yml
# Both scripts: publish-release.sh runs the notes script in its own environment.
miss=; for v in $(cat "$SCRIPT" "$NOTES_SCRIPT" | grep -oE '\$\{?[#!]?[A-Z_][A-Z0-9_]*' | tr -d '${#!' | sort -u) GH_TOKEN GH_REPO; do
  grep -qE "^        $v: " "$action" || miss+=" $v"
done
[[ -z $miss ]] && ok "action.yml sets every variable the script reads" || { echo "FAIL action.yml env lacks:$miss"; fail=1; }

# Refusals: each fails before gh publishes anything.
refused() { # LABEL EXPECTED-MESSAGE-PART NAME=VALUE...
  local label=$1 msg=$2; shift 2
  run "$@"
  [[ $? != 0 ]] && grep -qF -- "$msg" "$T/out" && ! gh_calls | grep -qE '\[(create|edit|upload)\]' &&
    ok "refused: $label" || bad "refused: $label"
}
refused "a branch name as the tag" "does not look like a version tag" VERSION_TAG=main
refused "an empty tag" "version_tag is empty" VERSION_TAG=
refused "no section for the version" "no entries under '## [3.32] - <date>'" VERSION_TAG=v3.32
refused "a glob matching nothing" "files: 'dist/*.dmg' matches no file" FILES='dist/*.dmg'
refused "a missing plain file" "files: 'missing.zip' is not a file" FILES='missing.zip'
refused "a directory" "files: 'dist' is not a file" FILES='dist'
refused "an empty title" "release_name is empty" RELEASE_NAME=
refused "no checkout" "CHANGELOG.md not found" CHANGELOG_PATH=CHANGELOG.md CHANGELOG_PATH=nope/CHANGELOG.md
changelog '## [Unreleased]' '' '## [3.31] - 2026-11-24' '' '### Added' '' '## [3.30] - 2026-11-21' '- Old.'
refused "a section of headings only" "no entries under '## [3.31] - <date>'"
changelog '## [Unreleased]' '- Not released yet.' '' '## [3.30] - 2026-11-21' '- Old.'
refused "[Unreleased] is never taken for the version" "no entries under '## [3.31] - <date>'"

exit $fail
