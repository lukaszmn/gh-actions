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
#   NOTES_SCRIPT         ../check-release-changelog/release-notes.sh
#   gh's own: GH_TOKEN, GH_REPO
set -euo pipefail

fail() { echo "::error::$*"; exit 1; }

# The tag checked and the notes written by the same script check-release-changelog runs.
bash "$NOTES_SCRIPT"
version=${VERSION_TAG#v}

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
