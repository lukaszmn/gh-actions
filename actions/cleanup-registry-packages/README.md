# cleanup-registry-packages

Deletes old GitHub package versions for multiple package names and keeps the newest `N` versions for each package.

Main inputs:
- `package_names`: newline-separated package names or image references
- `min_versions_to_keep`: number of newest versions to keep
- `github_token`: token allowed to delete package versions

Alternatives:
```yaml
    - name: Cleanup registry ${{ env.NGINX_IMAGE }}
      uses: actions/delete-package-versions@v5
      with:
        package-name: ${{ env.NGINX_IMAGE }}
        package-type: container
        min-versions-to-keep: 3
        token: ${{ secrets.GITHUB_TOKEN }}

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
