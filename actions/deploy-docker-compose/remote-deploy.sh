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
#   DEPLOY_REGISTRY_TOKEN    the read-only ghcr_pull_token — read from stdin by docker login
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

# Replace the first APP_TAG= line of an env file (dropping any later duplicates), or
# append one; every other line is kept byte for byte. The new content is built in a temp
# file and then written INTO the existing file rather than renamed over it, so its inode,
# owner, mode and any symlink survive (a rename would replace a symlinked .env with a
# copy owned by the deploy user, and overwrite a deliberately read-only one).
# `[ \t]`, not `[[:space:]]`: old mawk has no character classes.
write_app_tag() {
  file=$1
  tag=$2
  tmp=$(mktemp "${TMPDIR:-/tmp}/env.app-tag.XXXXXX")
  if awk -v tag="$tag" '
      /^[ \t]*(export[ \t]+)?APP_TAG[ \t]*=/ {
        if (!done) { print "APP_TAG=" tag; done = 1 }
        next
      }
      { print }
      END { if (!done) print "APP_TAG=" tag }
    ' "$file" >"$tmp" && cat "$tmp" >"$file"; then
    rm -f "$tmp"
  else
    rm -f "$tmp"
    return 1
  fi
}

main() {
  # `cd ""` succeeds (into $HOME in some shells): an unset path must not deploy there.
  [ -n "${DEPLOY_PATH:-}" ] || { echo "ERROR: deploy_path is empty" >&2; exit 1; }
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

  if [ -z "${DEPLOY_REGISTRY_TOKEN:-}" ]; then
    echo "ERROR: no registry credential (pass ghcr_pull_token)" >&2
    exit 1
  fi
  # printf is a shell builtin: the credential never appears in a process's arguments.
  printf '%s\n' "$DEPLOY_REGISTRY_TOKEN" |
    docker login "$DEPLOY_REGISTRY" -u "$DEPLOY_REGISTRY_USERNAME" --password-stdin
  unset DEPLOY_REGISTRY_TOKEN

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

# Over `ssh … sh -s` this script IS stdin, and a command reading stdin would swallow
# whatever follows it. Everything above is only definitions, so nothing is left to
# swallow by the time main runs; the redirect is a second guard, for edits that add
# top-level commands below this line.
main </dev/null
