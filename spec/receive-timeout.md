# Receive timeout

GoTP implements OTP-29.0.4 `wait_timeout/2`, `timeout/0`, and timeout cancellation by `remove_message/0` through explicit capabilities.

## Contract

- Timeout values are non-negative integer milliseconds or the atom `infinity`.
- Zero continues immediately at the instruction following `wait_timeout`.
- A finite timeout starts once, resumes the receive-loop label on message wakeup, and resumes the following `timeout` instruction on expiry.
- `timeout` resets the selective-receive cursor and clears the timer.
- `remove_message` cancels and clears the timer so a selected message wins the receive race.
- Clock access is injected with `goplus/std/clock.Clock`; VM code cannot read wall time directly.
- Timer callbacks enqueue scheduler wakeups and never mutate process execution state.

## Executable evidence

- `gotp.vm.receive-timeout-laws`
- `gotp.erts.receive-timeout-laws`
- `gotp.kernel.timer-wakeup-laws`

## Upstream trace

- OTP-29.0.4 `lib/compiler/src/genop.tab`: instruction contracts for `remove_message`, `timeout`, and `wait_timeout`.
- OTP-29.0.4 `erts/emulator/beam/emu/msg_instrs.tab`: saved receive pointer, one-shot timer, wakeup, and cancellation behavior.
