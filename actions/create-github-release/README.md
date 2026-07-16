# create-github-release

Checks out the repository, updates the changelog for a tag, optionally commits the changelog change, and creates a GitHub release.

Main inputs:
- `version_tag`: release tag such as `v1.2.3`
- `github_token`: token used for checkout, push, and release creation
- `target_branch`: branch that receives the changelog commit
- `version_tag_pattern`: regex `version_tag` must match (default `^v[0-9]+(\.[0-9]+)*(-[0-9A-Za-z.-]+)?$`)

Notes:
- softprops/action-gh-release@v3 is current standard — actions/create-release is deprecated (2022)

## version_tag must be a version

`version_tag` is validated before anything is checked out or written, so a bad value fails the
job instead of corrupting the changelog.

The trap this guards against: a workflow passing `version_tag: ${{ github.ref_name }}` gets a
*branch* name whenever the run was not triggered by a tag — e.g. a push to `main`, or a
`workflow_dispatch` from a branch. That cuts a tag literally named `main` and rolls the curated
`## [Unreleased]` changelog section into a `## [main]` release that does not exist.

`${{ github.ref_name }}` is only a version when a tag triggered the run. Gate the release job
accordingly:

```yaml
release:
  if: startsWith(github.ref, 'refs/tags/')
  steps:
    - uses: lukaszmn/gh-actions/actions/create-github-release@v1
      with:
        version_tag: ${{ github.ref_name }}
        github_token: ${{ secrets.GITHUB_TOKEN }}
```

If a workflow deploys on pushes to `main` and never triggers on tags, that guard could never be
true — such a workflow should not call this action at all. Tag and release separately.
