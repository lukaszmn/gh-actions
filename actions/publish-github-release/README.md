# publish-github-release

Creates the GitHub release of a version tag, with that version's CHANGELOG section as its notes
and optional files attached. On a re-run, when the release is already there, it updates the title
and notes and replaces the files instead of failing; a draft left by a create that was killed
while uploading is completed and published.

It **only reads** the CHANGELOG. It is for projects whose release script has already moved
`## [Unreleased]` to `## [X.Y.Z] - <date>` in the commit it tags, so nothing has to be committed
to main after the release (and pulled again). `create-github-release` is the other way round: it
renames the section in the workflow and pushes a commit to main.

```yaml
release:
  if: startsWith(github.ref, 'refs/tags/')
  runs-on: ubuntu-latest
  permissions:
    contents: write
  steps:
    - uses: actions/checkout@v5
    - uses: lukaszmn/gh-actions/actions/publish-github-release@v2.2.0
      with:
        version_tag: ${{ github.ref_name }}
        github_token: ${{ github.token }}
        # release_name: MyApp {version}   # default "Release {tag}"
        # files: dist/*                   # one path or glob per line
```

Inputs:
- `version_tag` (required): the tag, e.g. `v1.2.3`. The section read is `## [1.2.3] - …` (the tag
  without its `v`), up to the next `## [` heading. Validated against `version_tag_pattern` first,
  so a branch name (`main`, from a run that a tag did not trigger) fails.
- `github_token` (required): for `gh`; needs `contents: write`.
- `release_name`: the title. `{tag}` becomes `v1.2.3`, `{version}` becomes `1.2.3`. Default
  `Release {tag}`.
- `changelog_path`: default `CHANGELOG.md`.
- `files`: files to attach, one path or glob per line. Every line must match a file, or the step
  fails before anything is published.

Output: `notes_path`, the notes file it wrote (in `RUNNER_TEMP`).

It fails, publishing nothing, when the section is missing or holds only `###` headings. The
release script should refuse that before it tags. The check and the notes come from
`../check-release-changelog/release-notes.sh`: run `check-release-changelog` first in the
workflow, and a tag pushed by hand stops before anything is built, with the same rule.

## No checkout inside

The job checks out the repository itself, before this step. `actions/checkout` cleans the
workspace, so a checkout inside the action would delete the files the job built or downloaded to
attach.

## Created with `--verify-tag`

`gh release create` without it creates a missing tag at the default branch's head. With it, a tag
that is not on GitHub fails the step.

## Tests

`bash actions/publish-github-release/tests/test-publish-release.sh` runs the script against a
fake `gh`.
