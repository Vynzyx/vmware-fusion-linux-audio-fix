# VMware Fusion Linux guest audio dropouts

Audio in a Linux guest on VMware Fusion (Apple Silicon) stutters and cuts out
roughly once a second. It affects every app in the guest, not just one.

Two things combine to cause it:

- PipeWire drives the emulated VMware HD Audio codec with timer-based
  scheduling. The emulated DMA position counter is too coarse for it, so
  PipeWire sees underruns that never happened and re-prepares the PCM stream
  about every 1.4 seconds.
- The PipeWire audio thread runs without realtime priority, so it loses the
  CPU whenever the guest is even slightly busy.

The host audio device itself is fine. A direct `aplay -D hw:0` runs clean
while PipeWire tears the stream down repeatedly on the same device.

Fix is guest-side only. The host `.vmx` stays at its defaults.

## Symptoms

- Sound drops out, then returns, in a regular cycle.
- Stutter gets worse with CPU load, but happens at idle too.
- `vmware.log` on the host is flooded with
  `HDAudio: Unhandled REG write ... Stream Synchronization`.
- `aplay -D hw:0 file.wav` sounds clean while `pw-play file.wav` does not.

## Install

Run inside the guest as your normal user, not as root:

```bash
git clone https://github.com/Vynzyx/vmware-fusion-linux-audio-fix
cd vmware-fusion-linux-audio-fix
./install.sh
```

Log out and back in once so the `audio` group applies.

`./install.sh --with-mic` keeps the guest microphone usable. By default the
capture node is hidden from applications.

## Verify

```bash
./verify.sh
```

It plays 20 seconds of test tone and polls the PCM state. All samples should
read `RUNNING`. Any `SETUP` or `XRUN` sample is a tear-down. Run it with a
`stress-ng --cpu 0` or similar in the background for a load test.

Before the fix the same measurement gives 13 to 14 tear-downs per 20 seconds.

## What it changes

- `~/.config/wireplumber/wireplumber.conf.d/51-vmware-hda.conf`
  `api.alsa.disable-tsched`, `disable-batch`, 4096 frame periods, 16384 frame
  headroom on the emulated card.
- `~/.config/pipewire/pipewire.conf.d/20-clock.conf`
  clock quantum 4096, max quantum 8192.
- `~/.config/systemd/user/*.service.d/rt.conf` with `LimitRTPRIO=95`,
  `LimitNICE=-11`, `LimitMEMLOCK=infinity`.
- `/etc/security/limits.d/95-pipewire.conf` and membership of the `audio`
  group.

## Caveats

- Adds latency. Around 85 to 170 ms, fine for video and music, noticeable if
  you monitor live input.
- Disables the guest microphone unless `--with-mic` is passed.
- Written against PipeWire 1.6 and WirePlumber 0.5. Distros with PulseAudio
  installed instead need the `tsched=0` equivalent on `module-udev-detect`.
- Tested on Fusion 26.0.0, macOS 26, Ubuntu 26.04 arm64 guest. No reason for it
  to be Ubuntu specific, but that is all it was tested on.
- Host-side `.vmx` tweaks people recommend for this (`sound.backendType`,
  `sound.maxLength`, `sound.numBuffers`, `sound.bufferTime`, output-only
  `sound.fileName`) either silence the output or add nothing. Stock host sound
  settings are the ones that work.

## Uninstall

```bash
./uninstall.sh
```

## License

MIT
