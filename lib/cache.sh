#!/usr/bin/env bash
#
# Metadata cache for herdr-rbw.
# Ported from tmux-bitwarden's cache.sh — cache file lives in the
# plugin state dir. Cache stores metadata ONLY (name/username/URIs),
# never passwords.

bw_file_mtime() {
  local file="$1"

  [[ -f "$file" ]] || return 1

  if stat -c %Y "$file" >/dev/null 2>&1; then
    stat -c %Y "$file"
  else
    stat -f %m "$file"
  fi
}

bw_cache_is_expired() {
  local file="$1"
  local ttl_seconds="$2"
  local now
  local mtime

  [[ -f "$file" ]] || return 0

  if [[ "$ttl_seconds" -eq -1 ]]; then
    return 1
  fi

  now="$(date +%s)"
  mtime="$(bw_file_mtime "$file")" || return 0

  ((now - mtime >= ttl_seconds))
}

# Execute rbw list with auth retry.
bw_list_items_raw() {
  bw_run_with_auth "rbw_cli_list_items"
}

bw_list_items_with_cache() {
  local raw_items
  local cache
  local cache_ttl
  local cache_file
  local cache_filter
  local enabled_cache

  # Normalized cache shape (kept identical to the `bw` era so old cache
  # files stay valid): {id, name, login: {username, uris: [{uri}], has_totp}}.
  # rbw differences handled here:
  #   - entry type is the string "Login" (bw used the number 1)
  #   - username lives in .user (bw: .login.username)
  #   - uris is an array of STRINGS (bw: array of {uri} objects) —
  #     re-wrapped into {uri} objects for downstream code
  #   - `rbw list --raw` exposes no TOTP secret, so has_totp is always
  #     false for fresh entries (old cache files keep their stored value)
  cache_filter='
    map(
      select(.type == "Login" or .type == 1)
      | {
          id,
          name,
          login: {
            username: (.user // .login.username // ""),
            uris: ((.uris // .login.uris // []) | map(if type == "string" then {uri: .} else {uri: (.uri // "")} end)),
            has_totp: (.login.has_totp // false)
          }
        }
    )
  '

  enabled_cache="$(bw_get_config_or_default "$BW_CONFIG_KEY_CACHE" "$BW_CONFIG_DEFAULT_CACHE")"

  if [[ "$enabled_cache" == "true" ]]; then
    cache_file="$(bw_get_config_or_default "$BW_CONFIG_KEY_CACHE_FILE" "$BW_CONFIG_DEFAULT_CACHE_FILE")"
    cache_ttl="$(bw_get_config_or_default "$BW_CONFIG_KEY_CACHE_TTL" "$BW_CONFIG_DEFAULT_CACHE_TTL")"

    if bw_cache_is_expired "$cache_file" "$cache_ttl"; then
      mkdir -p "$(dirname "$cache_file")" || return 1
      raw_items="$(bw_list_items_raw)" || return 1
      cache="$(printf '%s\n' "$raw_items" | jq -c "$cache_filter")" || return 1

      printf '%s\n' "$cache" >"$cache_file" || return 1
    else
      cache="$(<"$cache_file")" || return 1
    fi
  else
    raw_items="$(bw_list_items_raw)" || return 1
    cache="$(printf '%s\n' "$raw_items" | jq -c "$cache_filter")" || return 1
  fi

  printf '%s\n' "$cache"
}

bw_cache_invalidate() {
  local cache_file

  cache_file="$(bw_get_config_or_default "$BW_CONFIG_KEY_CACHE_FILE" "$BW_CONFIG_DEFAULT_CACHE_FILE")" || return 1
  rm -f "$cache_file"
}
