# create-github-release

Checks out the repository, updates the changelog for a tag, optionally commits the changelog change, and creates a GitHub release.

Main inputs:
- `version_tag`: release tag such as `v1.2.3`
- `github_token`: token used for checkout, push, and release creation
- `target_branch`: branch that receives the changelog commit

Notes:
- softprops/action-gh-release@v3 is current standard — actions/create-release is deprecated (2022)
