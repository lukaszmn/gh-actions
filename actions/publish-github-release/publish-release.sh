#!/usr/bin/env bash
# Publishes the GitHub release of a version tag, with that version's CHANGELOG section as its
# notes, and optional files. The CHANGELOG is only READ: the project's release script has already
# moved [Unreleased] to "## [X.Y.Z] - <date>" in the tagged commit (see README.md).
#
# Inputs, from the environment (action.yml sets them):
#   VERSION_TAG          the tag, e.g. v1.2.3 — the version is the tag without its leading v
#   VERSION_TAG_PATTERN  regex VERSION_TAG must match
#   RELEASE_NAME         the title; {tag} and {version} are replaced
#   CHANGELOG_PATH       the changelog to read
#   FILES                files to attach: one path or glob per line, each must match a file
#   NOTES_PATH           where the notes are written
#   gh's own: GH_TOKEN, GH_REPO
set -euo pipefail

fail() { echo "::error::$*"; exit 1; }

[[ -n $VERSION_TAG ]] || fail "version_tag is empty."
grep -qE -- "$VERSION_TAG_PATTERN" <<< "$VERSION_TAG" ||
  fail "version_tag '$VERSION_TAG' does not look like a version tag (expected to match: $VERSION_TAG_PATTERN). If that is a branch name, gate the job with: if: startsWith(github.ref, 'refs/tags/')"
version=${VERSION_TAG#v}

[[ -f $CHANGELOG_PATH ]] || fail "$CHANGELOG_PATH not found: check out the repository before this action."
# The version's section, up to the next version's heading. index() == 1, not a regex: the dots
# of the version would match any character.
awk -v heading="## [$version] - " '
  index($0, heading) == 1 { in_section = 1; next }
  in_section && /^## \[/ { exit }
  in_section { print }
' "$CHANGELOG_PATH" > "$NOTES_PATH"
# Only "### Added" and the like, or nothing at all, says nothing: refused like a missing section.
# One grep reading to the end, no pipe into grep -q: that quits at the first match, and under
# pipefail the SIGPIPE of the grep feeding it fails a long section at random.
grep -v -e '^#' -e '^[[:space:]]*$' "$NOTES_PATH" > /dev/null ||
  fail "$CHANGELOG_PATH has no entries under '## [$version] - <date>': the release script moves [Unreleased] there before tagging."

files=()
if [[ -n ${FILES//[[:space:]]/} ]]; then
  shopt -s nullglob
  while IFS= read -r pattern; do
    # Leading and trailing blanks off; a blank line is skipped.
    pattern=${pattern#"${pattern%%[![:space:]]*}"}
    pattern=${pattern%"${pattern##*[![:space:]]}"}
    [[ -n $pattern ]] || continue
    # Unquoted to expand the glob, with IFS empty so that a space in a name doesn't split it.
    IFS=
    # shellcheck disable=SC2206
    matches=( $pattern )
    IFS=$' \t\n'
    (( ${#matches[@]} > 0 )) || fail "files: '$pattern' matches no file."
    for match in "${matches[@]}"; do
      # A name without wildcards is kept as it is even when there is no such file.
      [[ -f $match ]] || fail "files: '$match' is not a file."
      files+=("$match")
    done
  done <<< "$FILES"
  shopt -u nullglob
fi

title=${RELEASE_NAME//\{tag\}/$VERSION_TAG}
title=${title//\{version\}/$version}
[[ -n $title ]] || fail "release_name is empty."

# A re-run (all jobs re-run to redeploy, say) finds the release there: it is brought up to date
# rather than failing the run. A view that fails for another reason (auth, network) lands in
# create, which then fails with gh's own message.
if gh release view "$VERSION_TAG" > /dev/null 2>&1; then
  # Files first, so that a draft is complete before it is published.
  if (( ${#files[@]} > 0 )); then
    gh release upload "$VERSION_TAG" "${files[@]}" --clobber
  fi
  # --draft=false: a create killed while uploading leaves a draft behind, which view finds too.
  # Publishing a draft whose tag is gone would make GitHub tag the default branch's head, so the
  # tag is verified as on create (gh checks it only with --tag given).
  gh release edit "$VERSION_TAG" --tag "$VERSION_TAG" --verify-tag --draft=false --title "$title" \
    --notes-file "$NOTES_PATH"
  echo "Updated the release $VERSION_TAG ($title)."
else
  # --verify-tag: a tag that is not on GitHub fails, rather than gh creating one at the default
  # branch's head.
  gh release create "$VERSION_TAG" ${files[@]+"${files[@]}"} --title "$title" \
    --notes-file "$NOTES_PATH" --verify-tag
  echo "Created the release $VERSION_TAG ($title)."
fi
