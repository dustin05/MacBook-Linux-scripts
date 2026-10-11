#!/usr/bin/env bash
# swaybar status line: fan, temp, wifi, volume, battery, clock
while true; do
  p=()
  f=$(cat /sys/devices/platform/applesmc.768/fan1_input 2>/dev/null) && p+=("fan ${f}rpm")
  for t in /sys/devices/platform/coretemp.0/hwmon/hwmon*/temp1_input; do
    [ -r "$t" ] && { p+=("$(( $(cat "$t") / 1000 ))C"); break; }
  done
  w=$(nmcli -t -f TYPE,NAME connection show --active 2>/dev/null | awk -F: '$1 ~ /wireless/ {print $2; exit}')
  p+=("wifi ${w:-off}")
  v=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '/MUTED/ {print "muted"; next} {printf "%d%%", $2*100}')
  [ -n "$v" ] && p+=("vol $v")
  for b in /sys/class/power_supply/BAT*; do
    [ -r "$b/capacity" ] || continue
    s=$(cat "$b/status"); c=$(cat "$b/capacity")
    case "$s" in Charging) i="+";; Full) i="=";; *) i="";; esac
    p+=("bat ${c}%${i}"); break
  done
  p+=("$(date '+%a %d %b  %H:%M')")
  out=""; for x in "${p[@]}"; do out+="${out:+  |  }$x"; done
  echo "$out"
  sleep 5
done
