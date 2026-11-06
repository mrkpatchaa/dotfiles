# fileview: Ctrl+click a file link in Herdr

> **Old Herdr only.** This plugin works in the old terminal Herdr (`herdr`, config in `~/.config/herdr/`). The Herdr desktop app (`herdr-app`) doesn't run these plugins and can't catch link clicks: there, Cmd+O lists the files in the terminal instead. See [`../../herdr-app/`](../../herdr-app/README.md).

A local Herdr plugin. Ctrl+click a `file://` link in a pane, and the file opens in a popup at its line (bat). `q` closes it.

## Set up on a new machine

1. Link the plugin: `herdr plugin link ~/devs/dotfiles/herdr/fileview`
2. Let Claude Code draw links inside Herdr. Add this to `~/.zshrc` (Herdr is not on Claude Code's list yet, herdr issue #4748):
   ```sh
   [ "$TERM_PROGRAM" = herdr ] && export FORCE_HYPERLINK=1
   ```
3. In iTerm, turn on Settings → Pointer → "Ctrl-click reported to apps". Without it, iTerm opens its own menu.
4. Ask Claude for file links. The global `~/.claude/CLAUDE.md` has the rule: a Markdown link to the absolute path, with the line as `#L<n>`.

Needs `bat`, `less` and `python3`.

## Files

- `herdr-plugin.toml`: the link handler (`^file://`), the action and the popup.
- `open.sh`: runs on the click and opens the popup.
- `parse.py`: reads the path and the line from `#L9` or `:9`.
- `view.sh`: the popup. It shows a file with bat, a folder with `ls`.
