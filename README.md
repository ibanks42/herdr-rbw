# herdr-rbw

![License](https://img.shields.io/github/license/ibanks42/herdr-rbw)

Fuzzy-search your Bitwarden vault and paste/copy credentials — directly inside [herdr](https://herdr.dev), your agent-aware terminal multiplexer.

This is a **herdr port of [tmux-bitwarden](https://github.com/Alkindi42/tmux-bitwarden) by [Alkindi](https://github.com/Alkindi42)**, adapted from the tmux plugin system to herdr's native plugin v1 format. The design, the fzf selector UX, the session/auth handling, and the metadata cache all come from Alkindi's original — this port just moves them from tmux keybindings to herdr panes and actions. Huge thanks to Alkindi for the original; it's a lovely piece of work. 🫡

> **Fork note:** `herdr-rbw` is a fork of [WillowMist/herdr-bitwarden](https://github.com/WillowMist/herdr-bitwarden) (the `bw`-based herdr port by Penfold/Willow Cline). The herdr porting work — manifest, popup plumbing, fzf selector, cache design — is theirs; this fork converts the backend from the official `bw` CLI to [`rbw`](https://github.com/doy/rbw).

## Features

- 🔍 Fuzzy search Bitwarden items with `fzf`
- 👀 Preview username and URIs before selecting
- 🔐 Secure vault access through `rbw` (agent-held keys, no session tokens)
- 🔁 Automatic re-authentication on session expiration
- ⚡ Fast search with optional metadata caching
- ⌨️ Keyboard-driven workflow
- 📋 Paste or copy credentials (username, password, TOTP)
- 🔄 Refresh cache without leaving the selector
- 🖥 Popup interface via herdr's native popup placement

## Requirements

- [herdr](https://herdr.dev) >= 0.8.0 (plugin v1)
- [rbw](https://github.com/doy/rbw) (unofficial Bitwarden CLI)
- [pinentry](https://www.gnupg.org/related_software/pinentry/index.en.html) (for the unlock prompt; `rbw` requires it)
- [jq](https://jqlang.github.io/jq/)
- [fzf](https://github.com/junegunn/fzf)
- Bash >= 4

## Installation

Install it from GitHub:

```bash
herdr plugin install ibanks42/herdr-rbw
```

Then add a keybinding in `~/.config/herdr/config.toml` (the original tmux plugin used `prefix+b`, but that's herdr's native `toggle_sidebar` — this chord keeps the same letter):

```toml
[[keys.command]]
key = "prefix+ctrl+b"
type = "plugin_action"
command = "bitwarden.open-picker"
description = "Open Bitwarden picker"
```

Reload config (`herdr server reload-config`) and you're set.

## Usage

Press `prefix + ctrl + b` (or whatever key you bound) to open the Bitwarden selector popup.

| Key | Action |
|-----|-----------------------------------------|
| `Enter` | Paste password into the active pane |
| `Ctrl-y` | Copy password to clipboard |
| `Ctrl-u` | Paste username into the active pane |
| `Alt-u` | Copy username to clipboard |
| `Ctrl-r` | Refresh cached items |
| `Alt-t` | Copy TOTP to clipboard |
| `Ctrl-t` | Paste TOTP into the active pane |

## Authentication

Before using the plugin, configure `rbw` once:

```bash
rbw config set email you@example.com
rbw login
# only needed for the official bitwarden.com server:
rbw register
```

_No manual session handling is required._ The plugin automatically:

- checks the agent state with `rbw unlocked`
- prompts for unlock only when necessary via `rbw unlock` (the popup is a real terminal, so the master-password prompt works right inside it)
- retries operations transparently if the vault re-locks

Unlike the old `bw`-based flow, there is no `BW_SESSION` token and no
session file: the `rbw-agent` background process holds the keys in memory
(like `ssh-agent`). Any `session` file left over from the `bw` era is
deleted on startup.

## Configuration

All options are optional and read from environment variables, or from
`config.env` in the plugin config dir
(`herdr plugin config-dir bitwarden`).

| Variable | Default | Description |
|------|------|------|
| `RBW_CACHE` | `true` | Enable/disable the metadata cache |
| `RBW_CACHE_TTL` | `86400` | Cache duration in seconds (`-1` = never expire) |
| `RBW_CACHE_FILE` | `<state>/items.json` | Cache file location |

Legacy `BW_CACHE*` names from the `bw` era are still honored as a fallback.
`RBW_PROFILE` (rbw's native vault-switching env var) is passed through
untouched.

Example `config.env`:

```bash
RBW_CACHE=true
RBW_CACHE_TTL=43200
```

## Security

- Passwords are **never stored in the cache** — only metadata (name, username, URIs)
- Passwords are retrieved **only when required** (on paste/copy, via `rbw get --raw` / `rbw code`)
- Vault keys live in the `rbw-agent` process memory (like `ssh-agent`) — no session token on disk or in env
- The metadata cache holds no secrets and `rbw list --raw` exposes none (TOTP presence is therefore not shown for fresh entries)

## How it works

- `herdr-plugin.toml` — manifest declaring the `picker` popup pane and the `open-picker` action
- `picker.sh` — entrypoint (runs inside the popup): dependency check → session check → fzf selector → dispatch
- `lib/selector.sh` — fzf selector (ported from tmux-bitwarden; preview moved to `lib/preview.sh`)
- `lib/session.sh` — auth via the rbw agent (`rbw unlocked` / `rbw unlock`), auto-re-auth on lock
- `lib/vault.sh` — rbw wrappers (`rbw list --raw`, `rbw get --raw`, `rbw code`)
- `lib/cache.sh` — metadata cache with TTL
- `lib/actions.sh` — paste via `herdr pane send-text <pane> <value>`, copy via clipboard
- `lib/common.sh` — helpers; resolves the target pane from `HERDR_PLUGIN_CONTEXT_JSON.focused_pane_id`

## Differences from tmux-bitwarden

| tmux-bitwarden | herdr-rbw |
|---|---|
| `tmux display-popup` | herdr manifest `placement = "popup"` pane |
| `tmux send-keys -l -t "$pane" -- "$value"` | `herdr pane send-text "$pane" "$value"` |
| `@bw-*` tmux options | `RBW_*` env vars / `config.env` (`BW_*` still honored as fallback) |
| `tmux display-message` | stderr in the popup |
| session stored in tmux option | keys held by `rbw-agent` in memory (no session file) |

## License

MIT — see [LICENSE](LICENSE). Original tmux-bitwarden (c) 2026 Alkindi, herdr port (c) 2026 Penfold/Willow Cline.
