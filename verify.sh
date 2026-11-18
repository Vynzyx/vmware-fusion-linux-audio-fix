#!/usr/bin/env bash
# Measures whether the emulated audio stream survives, by polling the PCM
# state while a test tone plays. Every SETUP or XRUN sample is a tear-down.
set -euo pipefail

SECONDS_TO_RUN=${1:-20}
RATE=48000

if command -v speaker-test >/dev/null 2>&1; then
  :
elif ! command -v pw-cat >/dev/null 2>&1; then
  echo "need alsa-utils (speaker-test) or pipewire-utils (pw-cat)" >&2
  exit 1
fi

card=""
for codec in /proc/asound/card*/codec#*; do
  [ -e "$codec" ] || continue
  if grep -qi '15ad' "$codec" 2>/dev/null; then
    card=$(basename "$(dirname "$codec")")
    break
  fi
done

if [ -z "$card" ]; then
  echo "no VMware audio codec found under /proc/asound" >&2
  exit 1
fi

pcm="/proc/asound/$card/pcm0p/sub0"
if [ ! -d "$pcm" ]; then
  echo "no playback PCM at $pcm" >&2
  exit 1
fi

if command -v speaker-test >/dev/null 2>&1; then
  timeout "$((SECONDS_TO_RUN + 4))" speaker-test -D default -c 2 -t sine -l 999 >/dev/null 2>&1 &
else
  tmp=$(mktemp --suffix=.wav)
  python3 - "$tmp" <<'PY'
import math, struct, sys, wave
w = wave.open(sys.argv[1], "wb")
w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000)
w.writeframes(b"".join(
    struct.pack("<hh", int(9000 * math.sin(2 * math.pi * 440 * i / 48000)),
                int(9000 * math.sin(2 * math.pi * 440 * i / 48000)))
    for i in range(48000 * 30)))
w.close()
PY
  timeout "$((SECONDS_TO_RUN + 4))" pw-cat --playback "$tmp" >/dev/null 2>&1 &
fi
player=$!

sleep 1.5
running=0
setup=0
xrun=0
for _ in $(seq 1 "$((SECONDS_TO_RUN * 5))"); do
  state=$(head -1 "$pcm/status" 2>/dev/null | awk '{print $2}')
  case $state in
    RUNNING) running=$((running + 1)) ;;
    SETUP) setup=$((setup + 1)) ;;
    XRUN) xrun=$((xrun + 1)) ;;
  esac
  sleep 0.2
done
kill "$player" 2>/dev/null || true

echo "running=$running setup=$setup xrun=$xrun"
if [ "$setup" -eq 0 ] && [ "$xrun" -eq 0 ]; then
  echo "clean"
else
  echo "tear-downs still present"
fi
