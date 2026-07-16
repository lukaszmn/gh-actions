# resolve-app-version

Resolves a deployable version string from the current ref. Version tags are used as-is; any other ref (typically a branch deployed via `workflow_dispatch`) gets a short commit SHA appended, so a branch deploy still identifies the exact commit it shipped.

Requires no checkout — it reads the ref and SHA from the runner environment.

Main inputs:
- `sha_length`: number of commit-SHA characters to append for non-tag refs (default `7`)

Outputs:
- `version`: resolved version string

Resolution:

| Ref | `version` |
| --- | --- |
| `refs/tags/v2.1` | `v2.1` |
| `refs/heads/main` | `main-a1b2c3d` |

Example workflow usage:

```yaml
steps:
  - name: Resolve app version
    id: version
    uses: lukaszmn/gh-actions/actions/resolve-app-version@v1

  - name: Build and push image
    uses: lukaszmn/gh-actions/actions/docker-build-push-image@v1
    with:
      image: ghcr.io/owner/app
      context: ./client
      build_args: |
        APP_VERSION=${{ steps.version.outputs.version }}
```

Pair it with a tags-only guard on any release job so branch deploys don't cut a release named after the branch:

```yaml
release:
  if: startsWith(github.ref, 'refs/tags/')
```
