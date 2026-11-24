#!/usr/bin/env bash
# The release notes of a version tag: its CHANGELOG section, "## [X.Y.Z] - <date>", which the
# project's release script moved out of [Unreleased] in the commit it tagged. Fails when the tag
# is not a version, or the section is missing or says nothing. Shared by check-release-changelog
# (first thing in a release workflow: a tag pushed by hand stops there) and publish-github-release
# (the notes it publishes), so the two can't disagree.
#
# Inputs, from the environment:
#   VERSION_TAG          the tag, e.g. v1.2.3 — the version is the tag without its leading v
#   VERSION_TAG_PATTERN  regex VERSION_TAG must match
#   CHANGELOG_PATH       the changelog to read
#   NOTES_PATH           where the notes are written
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
  fail "$CHANGELOG_PATH has no entries under '## [$version] - <date>'. Was $VERSION_TAG tagged by hand? Release with the project's release script, which moves [Unreleased] there before it tags (delete this tag first)."
