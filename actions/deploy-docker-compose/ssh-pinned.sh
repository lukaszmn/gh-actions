# shellcheck shell=bash
# Helpers for the pinned-host-key path of action.yml. Sourced, not executed; kept in a
# file of their own so they can be tested without a server (see README).

# Single-quote a value for a POSIX shell: 'it'\''s'. Pure parameter expansion, so a
# secret passed through here never becomes another process's argument.
sh_quote() {
  local q=\'
  printf "'%s'" "${1//$q/$q\\$q$q}"
}

# The SHA256:… fingerprints in $1, one per line, '=' padding dropped. Accepts a bare
# fingerprint, the whole `ssh-keygen -lf` line, or several of either.
wanted_fingerprints() {
  printf '%s\n' "$1" | grep -oE 'SHA256:[A-Za-z0-9+/]+' | sort -u || true
}

# stdin: ssh-keyscan output. stdout: only the scanned keys whose SHA256 fingerprint is
# one of those in $1 — a known_hosts file for `StrictHostKeyChecking=yes`.
# Returns 1 (printing what was scanned to stderr) when no key matches, 2 when $1 holds
# no SHA256 fingerprint at all.
pin_known_hosts() {
  local wanted line fp ktype matched=1
  wanted=$(wanted_fingerprints "$1")
  if [[ -z "$wanted" ]]; then
    echo "host_fingerprint holds no SHA256:… fingerprint (ssh-keygen -lf <host key>.pub)." >&2
    return 2
  fi
  local scanned=()
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    fp=$(printf '%s\n' "$line" | ssh-keygen -E sha256 -lf - 2>/dev/null | awk '{print $2}') || fp=''
    [[ -z "$fp" ]] && continue
    read -r _ ktype _ <<<"$line"
    scanned+=("$fp $ktype")
    fp=${fp%%=*}
    if grep -qxF -- "$fp" <<<"$wanted"; then
      printf '%s\n' "$line"
      matched=0
    fi
  done
  if [[ $matched -ne 0 ]]; then
    {
      echo "Expected: $(tr '\n' ' ' <<<"$wanted")"
      if [[ ${#scanned[@]} -eq 0 ]]; then
        echo "Scanned:  nothing (host unreachable, or ssh-keyscan failed)"
      else
        printf 'Scanned:  %s\n' "${scanned[@]}"
      fi
    } >&2
  fi
  return $matched
}
