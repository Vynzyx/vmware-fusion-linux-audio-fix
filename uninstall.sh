#!/usr/bin/env bash
# Removes everything install.sh writes. Leave the group and limits.d entry
# alone unless you pass --all.
set -euo pipefail

ALL=0
if [ "${1:-}" = "--all" ]; then
  ALL=1
fi

rm -f "$HOME/.config/wireplumber/wireplumber.conf.d/51-vmware-hda.conf"
rm -f "$HOME/.config/wireplumber/wireplumber.conf.d/60-no-mic.conf"
rm -f "$HOME/.config/pipewire/pipewire.conf.d/20-clock.conf"
rm -f "$HOME/.config/systemd/user/pipewire.service.d/rt.conf"
rm -f "$HOME/.config/systemd/user/wireplumber.service.d/rt.conf"
rm -f "$HOME/.config/systemd/user/pipewire-pulse.service.d/rt.conf"

if [ "$ALL" -eq 1 ] && sudo -v 2>/dev/null; then
  sudo rm -f /etc/security/limits.d/95-pipewire-limits.conf
  sudo gpasswd -d "$USER" audio >/dev/null 2>&1 || true
fi

systemctl --user daemon-reload
systemctl --user restart wireplumber pipewire pipewire-pulse 2>/dev/null || true
echo "removed"
