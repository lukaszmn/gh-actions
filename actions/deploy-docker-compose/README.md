# deploy-docker-compose

Connects to a remote server over SSH, logs in to a container registry, pulls updated images, and restarts a Docker Compose stack.

The compose file and its `.env` live on the server in `deploy_path`; the action refuses to run if either is missing.

## Inputs

| Input | Required | Default | |
|---|---|---|---|
| `host` | yes | | SSH host, optionally `host:port` |
| `username` | yes | | SSH user |
| `ssh_key` | yes | | private key for that user |
| `deploy_path` | yes | | directory on the server holding the compose file and `.env` |
| `registry` | no | `ghcr.io` | registry to `docker login` to |
| `registry_username` | yes | | registry user |
| `registry_password` | one of these two | `''` | registry password/token |
| `ghcr_pull_token` | one of these two | `''` | read-only token; replaces `registry_password` when set |
| `compose_file` | no | `docker-compose.yml` | relative to `deploy_path` |
| `host_fingerprint` | no | `''` | pins the server's SSH host key |
| `app_tag` | no | `''` | image tag written to the server's `.env` as `APP_TAG` |

Every input added after v1 (`host_fingerprint`, `ghcr_pull_token`, `app_tag`) is optional, and leaving it out behaves as before.

## `host_fingerprint` — verify the server

Without it the server's host key is **not verified** (the run prints a warning), so anyone able to intercept the connection could pose as the server and receive the registry credential.

Get the value on the server:

```sh
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
# 256 SHA256:AbCd…xyz root@vps (ED25519)
```

Store the `SHA256:…` field (or the whole line) as a repository/environment variable and pass it:

```yaml
host_fingerprint: ${{ vars.VPS_HOST_FINGERPRINT }}
```

When it is set, the action scans the server's host keys, keeps only the one whose fingerprint matches, fails **before connecting** if none does, and connects with OpenSSH under `StrictHostKeyChecking=yes` against that single key. Several fingerprints may be given, whitespace-separated, while rotating a host key. Any of the server's key types works (Ed25519, ECDSA, RSA).

This path uses the runner's OpenSSH rather than `appleboy/ssh-action`: that action's own `fingerprint` option compares against whichever host key its Go client negotiates, which is ECDSA or RSA before Ed25519, so an Ed25519 fingerprint fails on a server that also has the other keys.

## `ghcr_pull_token` — a read-only credential on the server

The server only pulls, so give it a token that can only pull: a classic PAT with just `read:packages`, stored as a secret.

```yaml
registry_username: <the PAT owner>
ghcr_pull_token: ${{ secrets.GHCR_PULL_TOKEN }}
```

When set, it is the only credential sent to the server; `registry_password` can then be dropped (keep the wider token for jobs that need it, such as registry cleanup). Either way the credential reaches `docker login` on stdin (`--password-stdin`), never on a command line. Docker keeps it in the server user's `~/.docker/config.json` afterwards, as before.

## `app_tag` — deploy a specific version

The compose file on the server references the tag through a variable:

```yaml
services:
  api:
    image: ghcr.io/owner/app-api:${APP_TAG:-latest}
```

and the workflow passes the tag of the build it just pushed, e.g. the `sha_tag` output of [docker-build-push-image](../docker-build-push-image/README.md):

```yaml
jobs:
  build:
    outputs:
      app_tag: ${{ steps.api.outputs.sha_tag }}
    steps:
      - id: api
        uses: lukaszmn/gh-actions/actions/docker-build-push-image@<sha>
        # …
  deploy:
    needs: build
    steps:
      - uses: lukaszmn/gh-actions/actions/deploy-docker-compose@<sha>
        with:
          # …
          app_tag: ${{ needs.build.outputs.app_tag }}
```

On the server the action pulls with the new tag first and only then writes `APP_TAG=<value>` into `deploy_path/.env` — replacing an existing `APP_TAG=` line (later duplicates are dropped), appending one otherwise, every other line kept, the file's mode kept — and runs `up -d`. A failed pull leaves `.env` naming the tag that is still running. The value must be a valid Docker tag (`[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}`).

**Rollback:** re-run the deploy job of the earlier workflow run whose version you want back (Actions → that run → *Re-run jobs* → the deploy job only). It passes that run's tag again, which is still in the registry as long as retention has not deleted it. By hand on the server: edit `APP_TAG` in `.env` and `docker compose up -d`.

## How values reach the server

All inputs travel as single-quoted shell assignments ahead of [`remote-deploy.sh`](remote-deploy.sh) (never `${{ }}` spliced into a script), and none of them is exported, so they cannot override variables of the same name in the server's `.env`.

## Tests

No server needed:

```sh
bash actions/deploy-docker-compose/tests/test-ssh-pinned.sh
bash actions/deploy-docker-compose/tests/test-remote-deploy.sh   # SHELL_UNDER_TEST=bash / "busybox sh" too
```
