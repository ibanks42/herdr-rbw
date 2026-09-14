#!/usr/bin/env bash
# shellcheck disable=SC2034
#
# rbw session/auth management for herdr-rbw.
#
# rbw is agent-based (like ssh-agent): the rbw-agent background process
# holds the vault keys, so there is NO session token to pass around and
# NO session file to maintain. This replaces the old `bw` flow
# (`bw unlock --raw` + BW_SESSION file with 0600 perms).
#
# Any leftover session file from the `bw` era is deleted on startup —
# it is a live vault key and must not linger on disk unused.

readonly BW_STATUS_LOCKED="locked"
readonly BW_STATUS_UNLOCKED="unlocked"
# Kept for compatibility; rbw folds login+unlock into `rbw unlock`,
# so this state is never returned by bw_get_status anymore.
readonly BW_STATUS_UNAUTHENTICATED="unauthenticated"

# Run a vault function, retrying once via `rbw unlock` if the agent
# reports a locked / logged-out vault.
bw_run_with_auth() {
  local fn="$1"
  local result
  local ret
  local lowered

  shift

  result="$("$fn" "$@" 2>&1)"
  ret=$?

  if ((ret != 0)); then
    lowered="$(printf '%s' "$result" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lowered" == *"lock"* ]] ||
      [[ "$lowered" == *"unlock"* ]] ||
      [[ "$lowered" == *"not logged in"* ]] ||
      [[ "$lowered" == *"not authenticated"* ]] ||
      [[ "$lowered" == *"no agent"* ]] ||
      [[ "$lowered" == *"agent"* && "$lowered" == *"run"* ]]; then
      printf "Unlocking vault...\n" >&2
      bw_authenticate || return 1

      printf "Fetching vault...\n" >&2
      result="$("$fn" "$@")"
      ret=$?
    fi
  fi

  printf '%s\n' "$result"
  return "$ret"
}

bw_authenticate() {
  bw_cleanup_legacy_session

  if [[ "$(bw_get_status)" == "$BW_STATUS_UNLOCKED" ]]; then
    return 0
  fi

  # `rbw unlock` handles login AND unlock as needed (it prompts on the
  # terminal — the popup is a real terminal, so this works inline).
  # First-time setup still requires `rbw config set email <email>`,
  # `rbw login`, and (on bitwarden.com) `rbw register`.
  if ! bw_unlock; then
    bw_display_message "Failed to unlock vault. If this is a fresh setup, run 'rbw config set email <email>' then 'rbw login' (and 'rbw register' for bitwarden.com)."
    return 1
  fi
}

bw_has_session() {
  rbw unlocked >/dev/null 2>&1
}

# rbw has no `status` command; unlocked-ness is the exit code of
# `rbw unlocked` (0 = unlocked). Login state needs no separate check:
# `rbw unlock` performs login automatically when required.
bw_get_status() {
  if rbw unlocked >/dev/null 2>&1; then
    printf '%s\n' "$BW_STATUS_UNLOCKED"
  else
    printf '%s\n' "$BW_STATUS_LOCKED"
  fi
}

# Unlock vault via rbw (interactive prompt for master password)
bw_unlock() {
  rbw unlock
}

# Legacy `bw` sessions do not exist under rbw. This only reports the
# rbw agent state (kept under the old name for callers).
bw_get_session() {
  if rbw unlocked >/dev/null 2>&1; then
    printf 'unlocked\n'
  fi
}

bw_get_status_for_session() {
  bw_get_status
}

# No-op under rbw: the agent keeps the keys, nothing to store.
# Removes any legacy `bw` session file so a stale vault key is not
# left sitting on disk.
bw_unlock_and_store_session() {
  bw_cleanup_legacy_session
}

# Delete the session file left over from the `bw`-based version.
bw_cleanup_legacy_session() {
  if [[ -n "${BW_SESSION_FILE:-}" && -f "$BW_SESSION_FILE" ]]; then
    rm -f "$BW_SESSION_FILE"
  fi
  if [[ -n "${BW_SESSION:-}" ]]; then
    bw_display_message "Note: BW_SESSION is ignored — rbw authenticates via its agent, not env tokens."
  fi
}
