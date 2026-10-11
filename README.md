# mba-dotfiles

Sway + themes for a **2012 MacBook Air** on **Fedora Sway**.

```
git clone <your-repo-url> ~/mba-dotfiles
cd ~/mba-dotfiles && ./install.sh
```

A whiptail menu lets you install or uninstall components (Mac fixes, Broadcom Wi-Fi,
Wayland tools, apps, Helium, Sway config, theme) or switch themes.

## How it works
- Configs are **symlinked** into `~/.config`: edit in place, then `git commit`.
  Don't move the repo after installing.
- Existing files are backed up as `*.bak` and restored on uninstall.
- Uninstall only removes packages/files the installer added
  (tracked in `~/.local/state/mba-dotfiles/installed.txt`).
- Super (Cmd) is the Sway modifier: Cmd+Enter foot, Cmd+D fuzzel, Cmd+V clipboard, Cmd+Ctrl+L lock.
- Reboot after the Mac fixes or Wi-Fi driver.

## Adding a theme
Each folder in `themes/` mirrors `~/.config` and is linked in as-is:

```
themes/mytheme/
├── theme.conf                    # DESC (shown in the menu), optional GTK_ZIP/GTK_DIR/GTK_NAME, YAZI_FLAVOR
├── sway/config.d/60-theme.conf   # wallpaper, window colors, bar colors
├── foot/foot.ini
├── fuzzel/fuzzel.ini
├── mako/config
├── swaylock/config
└── (anything else: gtk-3.0/, yazi/theme.toml, ...)
```
Easiest start: `cp -r themes/nord themes/mytheme`, change the colors and `DESC`,
then run `./install.sh` and choose "Switch theme". Include only the files you want to theme.

## Layout
`install.sh`, `config/` (non-theme Sway config), `themes/`, `system/` (files for `/etc`).
