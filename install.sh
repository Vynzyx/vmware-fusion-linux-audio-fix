#!/usr/bin/env bash
# Guest-side audio fix for Linux on VMware Fusion (Apple Silicon).
set -euo pipefail

WITH_MIC=0
for arg in "$@"; do
  case $arg in
    --with-mic) WITH_MIC=1 ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [ "$(id -u)" -eq 0 ]; then
  echo "run as your normal user, not root" >&2
  exit 1
fi

if ! command -v wpctl >/dev/null 2>&1; then
  echo "wireplumber is not installed" >&2
  exit 1
fi

if ! lspci -nn 2>/dev/null | grep -qi '15ad:1977'; then
  echo "warning: VMware HD Audio controller (15ad:1977) not found, continuing anyway" >&2
fi

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STAMP=$(date +%Y%m%d%H%M%S)

backup() {
  if [ -e "$1" ]; then
    cp -a "$1" "$1.bak.$STAMP"
  fi
}

install -d "$HOME/.config/wireplumber/wireplumber.conf.d"
install -d "$HOME/.config/pipewire/pipewire.conf.d"
install -d "$HOME/.config/systemd/user/pipewire.service.d"
install -d "$HOME/.config/systemd/user/wireplumber.service.d"
install -d "$HOME/.config/systemd/user/pipewire-pulse.service.d"

TARGET_WP="$HOME/.config/wireplumber/wireplumber.conf.d/51-vmware-hda.conf"
TARGET_CLOCK="$HOME/.config/pipewire/pipewire.conf.d/20-clock.conf"
TARGET_NOMIC="$HOME/.config/wireplumber/wireplumber.conf.d/60-no-mic.conf"
TARGET_LIMITS="$HOME/.config/systemd/user"

backup "$TARGET_WP"
backup "$TARGET_CLOCK"
backup "$TARGET_NOMIC"

install -m 0644 "$DIR/files/51-vmware-hda.conf" "$TARGET_WP"
install -m 0644 "$DIR/files/20-clock.conf" "$TARGET_CLOCK"
install -m 0644 "$DIR/files/rt.conf" "$HOME/.config/systemd/user/pipewire.service.d/rt.conf"
install -m 0644 "$DIR/files/rt.conf" "$HOME/.config/systemd/user/wireplumber.service.d/rt.conf"
install -m 0644 "$DIR/files/rt.conf" "$HOME/.config/systemd/user/pipewire-pulse.service.d/rt.conf"

if [ "$WITH_MIC" -eq 1 ]; then
  rm -f "$TARGET_NOMIC"
  echo "microphone enabled"
else
  install -m 0644 "$DIR/files/60-no-mic.conf" "$TARGET_NOMIC"
  echo "microphone disabled"
fi

# Realtime scheduling needs privilege. Anything here failing is not fatal for
# playback stability, the ALSA settings do most of the work.
if sudo -v 2>/dev/null; then
  sudo usermod -aG audio "$USER"
  sudo install -m 0644 "$DIR/files/95-pipewire-limits.conf" \
    /etc/security/limits.d/95-pipewire-limits.conf
  sudo systemctl restart rtkit-daemon 2>/dev/null || true
else
  echo "sudo unavailable, add this by hand for full effect:" >&2
  echo "  sudo usermod -aG audio \$USER" >&2
  echo "  sudo cp $DIR/files/95-pipewire-limits.conf /etc/security/limits.d/" >&2
fi

systemctl --user daemon-reload
systemctl --user restart wireplumber pipewire pipewire-pulse

echo
echo "installed. log out and back in once, then run ./verify.sh"
