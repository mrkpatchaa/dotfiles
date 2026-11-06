# herdr-app: my Herdr desktop setup

My settings, keys, theme and one mod for the Herdr desktop app (`herdr-app`). They replace the old Herdr setup in `../herdr/` (moved over on 6 Nov 2026).

## Set up on a new machine

Copy the files into the app's home. The app reloads them while it runs:

```sh
cp -R ~/devs/dotfiles/herdr-app/{keys.json,settings.json,themes,mods} ~/.config/herdr-app/
herdr-app check ~/.config/herdr-app/mods/fileview
herdr-app status   # "errors": [] means every file loaded
```

Copy, don't symlink: whether the app follows symlinks is untested. The fileview viewer needs `bat` and `less`.

## What's here

- `settings.json`: Tokyo Night as the theme. The rest is the app's defaults.
- `themes/tokyo-night.json`: the theme (herdr-app doesn't ship one).
- `keys.json`: the app's default keys plus two of mine:
  - **Cmd+R** shows or hides the right panel (Files / Changes). It replaces the old `ctrl+b f` reviewr toggle: herdr-app has no prefix keys and no plugins.
  - **Cmd+O** opens fileview.
- `mods/fileview/`: **Cmd+O** lists the files named in the focused terminal (file:// links, full paths, `~/` paths, paths relative to its folder), newest first. Type to filter, Enter opens one at its line with `bat` in a pane on the right, `q` closes it. It replaces the old Ctrl+click plugin (`../herdr/fileview/`): herdr-app gives mods no way to catch a click on a link.

## Keep in mind

- Once `keys.json` is edited, the app stops adding new default keys to it on updates. Compare it with a fresh install's file after a big update.
- Claude Code links show only their short text on screen, so Cmd+O finds them only when the path starts from the terminal's folder.
- Settings in the app's own screen rewrite `~/.config/herdr-app/settings.json`. Copy it back here after changing something you want to keep.
