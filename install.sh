#!/usr/bin/env bash
# mba-dotfiles: pick components to install or uninstall (whiptail TUI).
# Target: 2012 MacBook Air, Fedora Sway. Run as your normal user, from the repo.
# Uninstall only removes packages/files this installer added (tracked in $STATE).

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
C="$HOME/.config"
STATE="$HOME/.local/state/mba-dotfiles/installed.txt"
THEME_STATE="$HOME/.local/state/mba-dotfiles/theme"
NEED_REBOOT=0
WANT=()

[ "$(id -u)" -eq 0 ] && { echo "Run as your normal user, not root."; exit 1; }
command -v whiptail >/dev/null || sudo dnf install -y newt
sudo -v || exit 1
mkdir -p "$(dirname "$STATE")"; touch "$STATE"

ORDER=(mac wifi tools apps helium sway theme)
declare -A DESC=(
  [mac]="Mac fixes: Fn keys, fan (mbpfan), TLP, thermald, sensors"
  [wifi]="Broadcom Wi-Fi driver (RPM Fusion akmod-wl)"
  [tools]="Wayland tools: mako, swaylock, grim, cliphist, wlsunset..."
  [apps]="Apps: foot, fuzzel, yazi + fonts"
  [helium]="Helium browser (official COPR)"
  [sway]="Sway config: trackpad, Mac keys, swaybar + status line"
  [theme]="Theme (pick from themes/): sway, foot, fuzzel, mako, swaylock, GTK"
)

# ---------- helpers ----------
say()       { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }
state_add() { grep -qxF "$1 $2 $3" "$STATE" || echo "$1 $2 $3" >> "$STATE"; }
state_del() { grep -vxF "$1 $2 $3" "$STATE" > "$STATE.tmp"; mv "$STATE.tmp" "$STATE"; }
state_get() { awk -v c="$1" -v k="$2" '$1==c && $2==k {print $3}' "$STATE"; }

install_pkgs() {   # install_pkgs <component> <pkgs...>  (records only what we newly installed)
  local comp=$1; shift; local new=() p
  WANT+=("$@")
  for p in "$@"; do rpm -q "$p" >/dev/null 2>&1 || new+=("$p"); done
  [ ${#new[@]} -eq 0 ] && return 0
  sudo dnf install -y --skip-unavailable "${new[@]}"
  for p in "${new[@]}"; do rpm -q "$p" >/dev/null 2>&1 && state_add "$comp" pkg "$p"; done
  return 0
}

finish_uninstall() {   # finish_uninstall <component>: remove tracked pkgs, coprs, files
  local c=$1 p f
  local pk=(); mapfile -t pk < <(state_get "$c" pkg)
  if [ ${#pk[@]} -gt 0 ]; then
    sudo dnf remove "${pk[@]}"          # no -y: you confirm the list
    for p in "${pk[@]}"; do rpm -q "$p" >/dev/null 2>&1 || state_del "$c" pkg "$p"; done
  fi
  for p in $(state_get "$c" copr); do sudo dnf copr remove -y "$p" && state_del "$c" copr "$p"; done
  for f in $(state_get "$c" file); do sudo rm -f "$f"; state_del "$c" file "$f"; done
}

link_cfg() {   # link_cfg <src_root> <rel>: link <src_root>/<rel> -> ~/.config/<rel>, backing up real files
  local src="$1/$2" dest="$C/$2"
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then mv "$dest" "$dest.bak"; fi
  ln -sfn "$src" "$dest"
}
unlink_cfg() {   # unlink_cfg <rel>
  local dest="$C/$1"
  if [ -L "$dest" ] && [[ "$(readlink "$dest")" == "$REPO"/* ]]; then
    rm "$dest"; [ -e "$dest.bak" ] && mv "$dest.bak" "$dest"
  fi
  return 0
}
reload_sway() { swaymsg reload >/dev/null 2>&1 || true; }

# ---------- install ----------
install_mac() {
  say "Mac fixes"
  local fn
  fn=$(whiptail --title "Fn keys" --menu "Top row default behaviour:" 12 66 2 \
       1 "Media keys (hold Fn for F1-F12)" 2 "F1-F12 (hold Fn for media keys)" 3>&1 1>&2 2>&3) || fn=1
  sed "s/fnmode=[0-9]/fnmode=$fn/" "$REPO/system/hid_apple.conf" | sudo tee /etc/modprobe.d/hid_apple.conf >/dev/null
  echo "$fn" | sudo tee /sys/module/hid_apple/parameters/fnmode >/dev/null 2>&1 || true
  sudo install -m644 "$REPO/system/mba-modules.conf" /etc/modules-load.d/mba.conf
  sudo modprobe applesmc 2>/dev/null; sudo modprobe coretemp 2>/dev/null

  # TLP conflicts with these; remember them so uninstall can put them back
  local p
  for p in tuned-ppd power-profiles-daemon; do
    rpm -q "$p" >/dev/null 2>&1 && { state_add mac restore "$p"; sudo dnf remove -y "$p"; }
  done
  sudo systemctl mask systemd-rfkill.service systemd-rfkill.socket 2>/dev/null || true

  install_pkgs mac tlp thermald mbpfan lm_sensors
  if ! rpm -q mbpfan >/dev/null 2>&1; then
    say "mbpfan not in repos: building from source"
    sudo dnf install -y gcc make git
    local t; t=$(mktemp -d)
    if git clone --depth 1 https://github.com/linux-on-mac/mbpfan "$t/m" && make -C "$t/m" && sudo make -C "$t/m" install \
       && sudo install -Dm644 "$t/m/mbpfan.service" /etc/systemd/system/mbpfan.service; then
      state_add mac file /usr/sbin/mbpfan; state_add mac file /etc/mbpfan.conf
      state_add mac file /etc/systemd/system/mbpfan.service
    fi
    rm -rf "$t"
  fi
  sudo systemctl daemon-reload
  sudo systemctl enable --now tlp thermald mbpfan 2>/dev/null || true
  sudo dracut -f >/dev/null 2>&1 || true
}

install_wifi() {
  say "Broadcom Wi-Fi"
  local fv; fv=$(rpm -E %fedora)
  sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$fv.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$fv.noarch.rpm" || return 0
  install_pkgs wifi kernel-devel akmod-wl broadcom-wl
  sudo akmods --force || true
  NEED_REBOOT=1
}

install_tools() {
  say "Wayland tools"
  install_pkgs tools mako swaylock swayidle swaybg grim slurp swappy wl-clipboard cliphist \
    brightnessctl pavucontrol wlsunset polkit-gnome pipewire wireplumber pipewire-pulseaudio \
    xdg-desktop-portal-wlr xdg-desktop-portal-gtk jq unzip curl git
  if ! command -v cliphist >/dev/null; then
    sudo dnf install -y golang && sudo env GOBIN=/usr/local/bin go install go.senan.xyz/cliphist@latest \
      && state_add tools file /usr/local/bin/cliphist
  fi
}

install_apps() {
  say "Apps"
  install_pkgs apps foot fuzzel yazi fd-find ripgrep fzf zoxide poppler-utils ImageMagick \
    jetbrains-mono-fonts google-noto-emoji-fonts
  if ! rpm -q yazi >/dev/null 2>&1; then
    sudo dnf copr enable -y lihaohong/yazi && state_add apps copr lihaohong/yazi
    install_pkgs apps yazi
  fi
}

install_helium() {
  say "Helium browser"
  sudo dnf copr enable -y imput/helium && state_add helium copr imput/helium
  install_pkgs helium helium-bin
}

install_sway() {
  say "Sway config"
  mkdir -p "$C/sway/config.d"
  [ -f "$C/sway/config" ] || cp /etc/sway/config "$C/sway/config"
  [ -f "$C/sway/config.bak" ] || cp "$C/sway/config" "$C/sway/config.bak"
  grep -qxF '# mba-dotfiles' "$C/sway/config" || \
    printf '\n# mba-dotfiles\ninclude ~/.config/sway/config.d/*.conf\n' >> "$C/sway/config"
  link_cfg "$REPO/config" sway/config.d/50-mba.conf
  link_cfg "$REPO/config" sway/status.sh
  if grep -rqs swayidle /etc/sway "$C/sway/config"; then
    echo "swayidle already started by existing config: skipping 55-idle.conf"
  else
    link_cfg "$REPO/config" sway/config.d/55-idle.conf
  fi
  reload_sway
}

# ---- themes: each folder in themes/ mirrors ~/.config plus a theme.conf ----
theme_var()   { ( . "$1" >/dev/null 2>&1; printf '%s' "${!2:-}" ); }   # theme_var <theme.conf> <VAR>
theme_files() { ( cd "$1" && find . -type f ! -name theme.conf | sed 's|^\./||' ); }

pick_theme() {
  local items=() d name cur first=1 st
  cur=$(cat "$THEME_STATE" 2>/dev/null)
  for d in "$REPO"/themes/*/; do
    name=$(basename "$d")
    if [ "$name" = "$cur" ] || { [ -z "$cur" ] && [ $first -eq 1 ]; }; then st=ON; else st=OFF; fi
    first=0
    items+=("$name" "$(theme_var "$d/theme.conf" DESC)" "$st")
  done
  [ ${#items[@]} -gt 0 ] || { echo "No themes found in $REPO/themes" >&2; return 1; }
  whiptail --title "Theme" --radiolist "Pick a theme (add your own in themes/)" 16 72 8 "${items[@]}" 3>&1 1>&2 2>&3
}

theme_unlink() {   # remove everything a theme put in place
  local t=$1 d="$REPO/themes/$1" f g y
  [ -d "$d" ] || return 0
  while read -r f; do unlink_cfg "$f"; done < <(theme_files "$d")
  for f in gtk.css gtk-dark.css assets; do
    [ -L "$C/gtk-4.0/$f" ] && [[ "$(readlink "$C/gtk-4.0/$f")" == "$HOME/.themes/"* ]] && rm "$C/gtk-4.0/$f"
  done
  g=$(theme_var "$d/theme.conf" GTK_NAME);     [ -n "$g" ] && rm -rf "$HOME/.themes/$g"
  y=$(theme_var "$d/theme.conf" YAZI_FLAVOR);  [ -n "$y" ] && rm -rf "$C/yazi/flavors/${y##*:}.yazi"
  return 0
}

install_theme() {
  say "Theme"
  local t cur d f zip dir name fl
  t=$(pick_theme) || return 0
  cur=$(cat "$THEME_STATE" 2>/dev/null)
  [ -n "$cur" ] && theme_unlink "$cur"
  d="$REPO/themes/$t"
  while read -r f; do link_cfg "$d" "$f"; done < <(theme_files "$d")

  zip=$(theme_var "$d/theme.conf" GTK_ZIP); dir=$(theme_var "$d/theme.conf" GTK_DIR)
  name=$(theme_var "$d/theme.conf" GTK_NAME)
  if [ -n "$zip" ] && [ -n "$name" ]; then
    local tmp; tmp=$(mktemp -d)
    if curl -fsSL "$zip" -o "$tmp/gtk.zip" && unzip -q "$tmp/gtk.zip" -d "$tmp"; then
      mkdir -p "$HOME/.themes"; rm -rf "$HOME/.themes/$name"; mv "$tmp/$dir" "$HOME/.themes/$name"
      mkdir -p "$C/gtk-4.0"
      for f in gtk.css gtk-dark.css assets; do
        [ -e "$C/gtk-4.0/$f" ] && [ ! -L "$C/gtk-4.0/$f" ] && continue   # never clobber real files
        ln -sfn "$HOME/.themes/$name/gtk-4.0/$f" "$C/gtk-4.0/$f"
      done
    else echo "GTK theme download failed"; fi
    rm -rf "$tmp"
  fi
  if [ -n "$name" ]; then gsettings set org.gnome.desktop.interface gtk-theme "$name" 2>/dev/null || true
  else gsettings reset org.gnome.desktop.interface gtk-theme 2>/dev/null || true; fi

  fl=$(theme_var "$d/theme.conf" YAZI_FLAVOR)
  if [ -n "$fl" ] && command -v ya >/dev/null; then
    { ya pkg add "$fl" || ya pack -a "$fl"; } >/dev/null 2>&1
  fi
  echo "$t" > "$THEME_STATE"
  reload_sway
}

# ---------- uninstall ----------
uninstall_mac() {
  say "Removing Mac fixes"
  sudo systemctl disable --now tlp thermald mbpfan 2>/dev/null || true
  sudo systemctl unmask systemd-rfkill.service systemd-rfkill.socket 2>/dev/null || true
  sudo rm -f /etc/modprobe.d/hid_apple.conf /etc/modules-load.d/mba.conf
  finish_uninstall mac
  local p
  for p in $(state_get mac restore); do sudo dnf install -y "$p" && state_del mac restore "$p"; done
  sudo dracut -f >/dev/null 2>&1 || true
  NEED_REBOOT=1
}
uninstall_wifi()   { say "Removing Wi-Fi driver"; finish_uninstall wifi; NEED_REBOOT=1; }
uninstall_tools()  { say "Removing tools";   finish_uninstall tools; }
uninstall_apps()   { say "Removing apps";    finish_uninstall apps; }
uninstall_helium() { say "Removing Helium";  finish_uninstall helium; }

uninstall_sway() {
  say "Removing Sway config"
  unlink_cfg sway/config.d/50-mba.conf; unlink_cfg sway/config.d/55-idle.conf; unlink_cfg sway/status.sh
  [ -f "$C/sway/config" ] && sed -i '/^# mba-dotfiles$/,+1d' "$C/sway/config"
  reload_sway
}

uninstall_theme() {
  say "Removing theme"
  local cur; cur=$(cat "$THEME_STATE" 2>/dev/null)
  [ -n "$cur" ] && theme_unlink "$cur"
  rm -f "$THEME_STATE"
  gsettings reset org.gnome.desktop.interface gtk-theme 2>/dev/null || true
  gsettings reset org.gnome.desktop.interface color-scheme 2>/dev/null || true
  reload_sway
}

# ---------- UI ----------
pick() {   # pick <title> <default ON|OFF>
  local items=() k d
  for k in "${ORDER[@]}"; do
    d=$2
    if [ "$k" = wifi ] && [ "$2" = ON ]; then
      lspci -nn 2>/dev/null | grep -qiE 'network.*broadcom' && d=ON || d=OFF
    fi
    items+=("$k" "${DESC[$k]}" "$d")
  done
  whiptail --title "$1" --separate-output --checklist "Space = toggle, Enter = confirm" 18 80 7 \
    "${items[@]}" 3>&1 1>&2 2>&3
}

action=$(whiptail --title "MBA Sway setup" --menu "What do you want to do?" 14 60 4 \
  install   "Install / update components" \
  theme     "Switch theme" \
  uninstall "Remove components" \
  quit      "Exit" 3>&1 1>&2 2>&3) || exit 0
[ "$action" = quit ] && exit 0
if [ "$action" = theme ]; then
  install_theme
  whiptail --title "Theme" --msgbox "Active theme: $(cat "$THEME_STATE" 2>/dev/null || echo none)\n\nFoot/mako/fuzzel pick it up on next launch; sway reloaded." 10 64
  exit 0
fi

def=ON; [ "$action" = uninstall ] && def=OFF
SEL=(); mapfile -t SEL < <(pick "${action^}: choose components" "$def")
[ ${#SEL[@]} -eq 0 ] && { echo "Nothing selected."; exit 0; }

msg="About to $action:\n\n"
for k in "${SEL[@]}"; do msg+=" - ${DESC[$k]}\n"; done
[ "$action" = uninstall ] && msg+="\nOnly packages/files this installer added will be removed."
whiptail --title "Confirm" --yesno "$msg" 18 78 || exit 0

for k in "${ORDER[@]}"; do
  [[ " ${SEL[*]} " == *" $k "* ]] && "${action}_$k"
done

# ---------- summary ----------
missing=()
if [ "$action" = install ]; then
  for p in "${WANT[@]}"; do
    rpm -q "$p" >/dev/null 2>&1 || command -v "$p" >/dev/null 2>&1 || missing+=("$p")
  done
fi
out="Done."
[ ${#missing[@]} -gt 0 ] && out+="\n\nNot installed (check repo/name): ${missing[*]}"
[ "$NEED_REBOOT" -eq 1 ] && out+="\n\nReboot recommended."
[ "$action" = install ] && out+="\n\nVerify later: sensors | grep -i fan ; systemctl status mbpfan tlp"
whiptail --title "Finished" --msgbox "$out" 16 70
