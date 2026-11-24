# check-release-changelog

Fails unless the CHANGELOG has an entry under the version tag's own section,
`## [X.Y.Z] - <date>`, the section a project's release script writes into the commit it tags. It
is the same check `publish-github-release` makes before publishing (one script,
`release-notes.sh`, used by both), run at the START of the release workflow. A tag pushed by hand
then stops there, before anything is built or deployed, rather than at the very end.

```yaml
detect-changes:
  steps:
    - uses: actions/checkout@v5          # or an action that checks out
    - if: startsWith(github.ref, 'refs/tags/')
      uses: lukaszmn/gh-actions/actions/check-release-changelog@v2.2.0
      with:
        version_tag: ${{ github.ref_name }}
```

Inputs: `version_tag` (required), `changelog_path` (default `CHANGELOG.md`),
`version_tag_pattern` (as in `publish-github-release`). Output: `notes_path`, the section written
as release notes.

It fails when:
- the tag does not match the pattern (a branch name, from a run a tag did not trigger);
- the CHANGELOG is not there (no checkout yet);
- there is no `## [X.Y.Z] - ` heading for the version, or the section holds only `###` headings.

The message says what to do: delete the tag, and release with the project's release script.

## Tests

`bash actions/check-release-changelog/tests/test-release-notes.sh`
