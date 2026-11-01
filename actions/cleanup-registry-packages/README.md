# cleanup-registry-packages

Deletes old GitHub package versions for multiple package names and keeps the newest `N` versions for each package.

Main inputs:
- `package_names`: newline-separated package names or image references
- `min_versions_to_keep`: number of newest versions to keep
- `cleanup_token`: token allowed to list and delete package versions

**v2 (breaking):** the token input was `github_token` — renamed to `cleanup_token`, because it is not the workflow's `GITHUB_TOKEN` (which cannot delete user-owned versions). Callers still on `@v1` are unaffected.

```yaml
    - uses: lukaszmn/gh-actions/actions/cleanup-registry-packages@<sha or tag>
      with:
        package_names: |
          ghcr.io/owner/app-api
          ghcr.io/owner/app-nginx
        min_versions_to_keep: '3'
        cleanup_token: ${{ secrets.GHCR_CLEANUP_TOKEN }}
```

### Tokens: one per job, named for the job

| Secret | Classic PAT scopes | Passed to | Ends up on the server |
|---|---|---|---|
| `GHCR_PULL_TOKEN` | `read:packages` | deploy-docker-compose `ghcr_pull_token` | yes (`docker login` stores it) |
| `GHCR_CLEANUP_TOKEN` | `read:packages`, `delete:packages` | cleanup-registry-packages `cleanup_token` | no — stays in GitHub |

`GITHUB_TOKEN` cannot delete versions of packages owned by a **user** (403 "Resource not
accessible by integration"), hence a PAT; GitHub Packages (the registry and its REST API)
accepts only classic PATs. The cleanup lists versions before deleting, so it needs
`read:packages` as well as `delete:packages`. Keep the
delete-capable token out of the deploy, so a compromised server cannot wipe the registry.
If the secret is environment-scoped, the job needs `environment:` set or it resolves to `''`.

Alternatives:
```yaml
    - name: Cleanup registry ${{ env.NGINX_IMAGE }}
      uses: actions/delete-package-versions@v5
      with:
        package-name: ${{ env.NGINX_IMAGE }}
        package-type: container
        min-versions-to-keep: 3
        token: ${{ secrets.GHCR_CLEANUP_TOKEN }}   # user-owned packages: a PAT, not GITHUB_TOKEN

    - name: Keep recent backend images, skip release-like tags
      uses: snok/container-retention-policy@v3.0.0
      with:
        image-names: myapp-backend
        cut-off: 10 days ago UTC
        keep-at-least: 2
        account-type: personal
        skip-tags: latest,prod,v*
        token: ${{ secrets.GHCR_DELETE_TOKEN }}
```
