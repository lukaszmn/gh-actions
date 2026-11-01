#!/bin/sh
# Runs ON THE SERVER, fed by action.yml (over appleboy/ssh-action or OpenSSH).
#
# Inputs arrive as plain shell assignments prepended to this script — deliberately NOT
# exported, so none of them reaches `docker compose`'s environment, where it would
# override a same-named variable in the server's .env:
#   DEPLOY_PATH              directory holding the compose file and .env
#   DEPLOY_COMPOSE_FILE      compose file, relative to DEPLOY_PATH
#   DEPLOY_REGISTRY          registry hostname for `docker login`
#   DEPLOY_REGISTRY_USERNAME registry username
#   DEPLOY_REGISTRY_PASSWORD the one credential chosen by action.yml (ghcr_pull_token,
#                            else registry_password) — read from stdin by docker login
#   DEPLOY_APP_TAG           optional image tag written to .env as APP_TAG
#
# POSIX sh on purpose: appleboy/ssh-action runs it in the remote user's login shell.
set -e

# Docker's tag grammar: [A-Za-z0-9_][A-Za-z0-9_.-]{0,127}. Checked on the runner too;
# repeated here because this is the side that writes the file.
valid_tag() {
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$' &&
    [ "$(printf '%s' "$1" | wc -l)" -eq 0 ]
}

# Replace the first APP_TAG= line of an env file in place (dropping any later
# duplicates), or append one; every other line is kept byte for byte. Written to a temp
# file in the same directory and renamed over the original, so a failure mid-write
# never leaves a truncated .env; the original's mode is kept.
write_app_tag() {
  file=$1
  tag=$2
  dir=$(dirname "$file")
  tmp=$(mktemp "$dir/.env.app-tag.XXXXXX")
  if ! awk -v tag="$tag" '
      /^[[:space:]]*(export[[:space:]]+)?APP_TAG[[:space:]]*=/ {
        if (!done) { print "APP_TAG=" tag; done = 1 }
        next
      }
      { print }
      END { if (!done) print "APP_TAG=" tag }
    ' "$file" >"$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  chmod "$(stat -c '%a' "$file")" "$tmp" 2>/dev/null || chmod 600 "$tmp"
  mv -f "$tmp" "$file"
}

main() {
  cd "$DEPLOY_PATH"
  test -f .env || { echo "ERROR: .env missing — create from .env.example" >&2; exit 1; }
  test -f "$DEPLOY_COMPOSE_FILE" || {
    echo "ERROR: $DEPLOY_COMPOSE_FILE missing at DEPLOY_PATH" >&2
    exit 1
  }

  if [ -n "${DEPLOY_APP_TAG:-}" ] && ! valid_tag "$DEPLOY_APP_TAG"; then
    echo "ERROR: app_tag is not a valid image tag" >&2
    exit 1
  fi

  if [ -z "${DEPLOY_REGISTRY_PASSWORD:-}" ]; then
    echo "ERROR: no registry credential (pass ghcr_pull_token or registry_password)" >&2
    exit 1
  fi
  # printf is a shell builtin: the credential never appears in a process's arguments.
  printf '%s\n' "$DEPLOY_REGISTRY_PASSWORD" |
    docker login "$DEPLOY_REGISTRY" -u "$DEPLOY_REGISTRY_USERNAME" --password-stdin
  unset DEPLOY_REGISTRY_PASSWORD

  if [ -n "${DEPLOY_APP_TAG:-}" ]; then
    # Pull the new tag first, handing it to compose through the environment (which
    # outranks .env for interpolation), and persist it only once the pull succeeded:
    # a failed pull leaves .env naming the tag that is actually running.
    APP_TAG=$DEPLOY_APP_TAG docker compose -f "$DEPLOY_COMPOSE_FILE" pull
    write_app_tag .env "$DEPLOY_APP_TAG"
    echo "APP_TAG=$DEPLOY_APP_TAG written to $DEPLOY_PATH/.env"
  else
    docker compose -f "$DEPLOY_COMPOSE_FILE" pull
  fi
  docker compose -f "$DEPLOY_COMPOSE_FILE" up -d
  docker image prune -f
}

# Everything above is only definitions, and stdin is cut off here: over `ssh … sh -s`
# this script IS stdin, and a command that read from it would swallow the rest.
main </dev/null
