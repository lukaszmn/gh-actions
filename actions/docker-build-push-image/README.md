# docker-build-push-image

Generates Docker metadata tags and builds and pushes an image with optional build arguments and Dockerfile override.

Main inputs:
- `image`: full image name
- `context`: Docker build context
- `dockerfile`: optional Dockerfile path
- `build_args`: optional multiline build arguments

## Tags

Every build is pushed as:
- `latest`
- `sha-<7-char short commit sha>`, e.g. `sha-860c190` — unique to the commit, so a deploy can name exactly this build and a rollback can name an earlier one
- `<version>` from a semver git tag (`v1.2.3` → `1.2.3`), on tag builds only

## Outputs

- `tags`: all generated tags (full image references, newline-separated)
- `labels`: generated OCI labels
- `sha_tag`: the `sha-<short>` tag alone (no image name) — pass it to [deploy-docker-compose](../deploy-docker-compose/README.md)'s `app_tag`
