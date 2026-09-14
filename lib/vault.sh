#!/usr/bin/env bash
#
# rbw CLI wrappers for herdr-rbw.
# NOTE: raw CLI functions use rbw_cli_* prefix so they don't collide with
# the auth-wrapped wrappers in actions.sh (bw_get_totp etc.).
# Unlike `bw`, rbw needs no session token: the rbw-agent holds the keys,
# so these wrappers take no session argument.

rbw_cli_list_items() {
  # Best-effort sync so a cache refresh picks up server-side changes.
  # Ignored when offline — `rbw list` still serves the local database.
  rbw sync >/dev/null 2>&1 || true
  rbw list --raw
}

rbw_cli_get_item_by_id() {
  local id="$1"

  rbw get --raw "$id"
}

rbw_cli_get_totp() {
  local id="$1"

  rbw code "$id"
}
