# Diagnosis notes

Recorded while chasing the dropouts, kept so the dead ends do not get
retried.

## Measurement

Audio problems in a VM are easy to argue about and hard to see, so the test
was: play a generated 440 Hz WAV for a fixed time, poll
`/proc/asound/cardN/pcm0p/sub0/status` five times a second, and count the
states.

- `RUNNING` means the PCM is streaming.
- `SETUP` means it was torn down and re-prepared.
- `XRUN` means the emulation actually starved.

Tearing down is cheap, so `SETUP` is the metric that matters. Baseline on the
untouched setup was 13 to 14 `SETUP` samples per 20 seconds, i.e. roughly one
per 1.4 seconds, which matches what the speakers do.

## Ruling out the host

`aplay -D hw:0 file.wav` on the guest, with PipeWire stopped, ran 60 out of 60
samples `RUNNING`. Same host device, same emulated codec, no PipeWire, no
dropouts. That puts the problem in the guest audio stack rather than the host
backend.

`vmware.log` did show about 15,800 `HDAudio: Unhandled REG write ... Stream
Synchronization` warnings. The guest driver programs stream sync groups that
Fusion never implements. Real, but not fatal on its own: `aplay` hits the same
unhandled writes and stays clean. It is a symptom of how often the guest
re-synchronises, not the cause of the gaps.

Host `coreaudiod` logged nothing at all across the bad period. No overloads,
no device errors.

## The actual cause

PipeWire's ALSA plugin defaults to timer-based scheduling. Against a real
codec that is fine. Against this emulated one, the reported DMA position is
too coarse for the timer, so the stream looks starved long before the ring is
empty.

`api.alsa.disable-tsched = true` switches to period wakeups, `disable-batch`
spreads the writes, and long periods plus headroom give the emulation room to
lag. With those, 120 of 120 samples stayed `RUNNING` while six CPU burners
saturated every vCPU.

The second half was scheduling. `LimitRTPRIO` was 0 on the user services, so
PipeWire could not take realtime priority, and any load pushed it off the CPU.
With `LimitRTPRIO=95` the data loop runs `SCHED_RR` and the xruns under load
disappear.

## Dead ends

Host `.vmx` tuning, all tried, all reverted:

- `sound.backendType = "audiounit"` — the stream reports `RUNNING` and nothing
  comes out of the speakers. No error, no fallback message.
- `sound.fileName` with only the output half (`BuiltInSpeakerDevice`) —
  also silent. The input half has to stay.
- `sound.maxLength`, `sound.numBuffers`, `sound.bufferTime` — silent, and the
  log fills with `SoundAQDisposeQueue: Audio queue not stopped completely`.
- `sound.autodetect = "FALSE"` with the device names pinned — works, but does
  not add anything once the guest buffers are in place, and it costs the
  ability to follow a headphone switch.

The default host sound block is the one that works.

## Things that were not the problem

- Host default output device churn. Real, but the guest buffers absorb it.
- Sample rate. Everything is 48 kHz end to end, host device included.
- The `hdaudio.codec.personality` knob.
- Emulated capture. Input is unrelated to playback and stays broken with
  non-VPIO backends (`kAudioUnitErr_FormatNotSupported` on the input unit),
  which is why the fix disables the capture node by default.

## Ordering

Period size is clamped by the PipeWire clock, so `20-clock.conf` has to load
with a quantum at least as large as `api.alsa.period-size`, otherwise the
period silently collapses back to the quantum and most of the benefit goes
away. Without the clock file, a 4096 period was accepted but the buffer capped
at 8192 frames; with it, the whole ring is usable.
