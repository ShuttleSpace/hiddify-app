#!/usr/bin/env bash
# Samples the macOS proxy switches while you reproduce, so the exact moment the
# switch is (or is not) cleared is on record. Run this first, then disconnect or
# switch service mode, then come back and paste the tail.
set -u
OUT="${TMPDIR:-/tmp}/hiddify-proxy-watch.log"
SERVICES=("Wi-Fi" "AX88179A" "200806006809080000")

printf '%-8s %-24s %-10s %-14s %s\n' TIME SERVICE KIND ENABLED ADDR > "$OUT"
while true; do
  for s in "${SERVICES[@]}"; do
    for kind in web secure socks; do
      case $kind in
        web)    flag=-getwebproxy ;;
        secure) flag=-getsecurewebproxy ;;
        socks)  flag=-getsocksfirewallproxy ;;
      esac
      out=$(networksetup "$flag" "$s" 2>/dev/null)
      [ -z "$out" ] && continue
      en=$(printf '%s' "$out" | sed -n 's/^Enabled: //p')
      srv=$(printf '%s' "$out" | sed -n 's/^Server: //p')
      prt=$(printf '%s' "$out" | sed -n 's/^Port: //p')
      printf '%-8s %-24s %-10s %-10s %s:%s\n' \
        "$(date +%H:%M:%S)" "$s" "$kind" "$en" "$srv" "$prt" >> "$OUT"
    done
  done
  sleep 1
done