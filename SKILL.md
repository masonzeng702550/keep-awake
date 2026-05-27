---
name: keep-awake
description: Keep a laptop awake so long-running agent tasks survive a closed lid or an idle screen, on macOS or Windows. Use this skill BEFORE starting any task that will take more than a few minutes and might run while the user steps away or closes the laptop — for example multi-file refactors, test suites, builds, batch downloads, data processing, overnight runs, or any plan with many sequential steps. Trigger it whenever the user mentions closing the lid, leaving the laptop, running overnight, "keep it running", "don't let it sleep", or worries that a task will be interrupted by sleep. On macOS the skill wraps the built-in `caffeinate` tool; on Windows it uses the SetThreadExecutionState power API via PowerShell. In both cases the system stays awake only for as long as the task runs, then normal power behavior is restored automatically.
---

# Keep Awake (macOS + Windows)

## What this does and why

Closing the lid or leaving a laptop idle triggers sleep. When the system sleeps,
a running agent task is suspended — a forty-step plan that was fine at step three
is frozen until someone wakes the machine. The fix is to hold a temporary
"don't sleep" request for exactly the duration of the task: no installation, no
permanent setting change.

- **macOS** uses the built-in `caffeinate` command.
- **Windows** uses the `SetThreadExecutionState` Win32 API, invoked from
  PowerShell.

This skill is the discipline around those mechanisms: start the keep-awake
before a long task, scope it to exactly that task, and let it end cleanly so the
laptop returns to normal power-saving afterward. The goal is a laptop that stays
awake *only while work is happening* — not a machine that never sleeps and cooks
its battery overnight.

## Step 1: Detect the platform

Before doing anything, determine which OS you're on, because the mechanism
differs. A quick way from a shell:

- If `uname` returns `Darwin` → **macOS**, use the `caffeinate` approach below.
- If you're in PowerShell / `cmd`, or `uname` is unavailable → **Windows**, use
  the PowerShell approach below.

If unsure, just ask the user, or check the environment. Then follow the matching
section.

---

## macOS

### The core mechanism

`caffeinate` holds a power assertion as long as it is running. The cleanest
pattern is to attach it directly to the long-running command, so the assertion
is released the instant the work finishes:

```bash
caffeinate -i -s <your-long-command>
```

Flags that matter:

- `-i` prevents **idle** sleep.
- `-s` prevents sleep **while on AC power** — the one that matters for a closed
  lid, because closed-lid sleep is only reliably blocked when plugged in.
- `-d` prevents the **display** from sleeping (usually unnecessary for a closed
  lid; useful for the "screen on, I walked away" case).
- `-m` prevents the disk from idle-sleeping.

For the closed-lid case use `-i -s`, and the laptop should be **plugged in** — a
MacBook on battery still sleeps on lid close by hardware design.

### Case A — the task is a single command you can wrap

Best case. Wrap it so keep-awake lives and dies with the task:

```bash
caffeinate -i -s npm test
```

When the command exits, `caffeinate` exits, and the Mac returns to normal sleep
behavior on its own. Nothing to clean up.

### Case B — many steps over time (the usual agent case)

When you'll run a sequence of commands yourself over several minutes, start a
time-boxed background assertion, do the work, then stop it:

```bash
bash scripts/keep_awake.sh start 7200   # cap at 2 hours
# ... do the long task ...
bash scripts/keep_awake.sh stop         # release as soon as it's done
```

The timeout is a safety cap, not a target. If the task finishes early, **always
call `stop`**. The cap exists only so a crashed or abandoned session can't leave
the machine awake forever.

### Inspect / debug (macOS)

```bash
bash scripts/keep_awake.sh status   # is this skill holding the Mac awake?
pmset -g assertions                 # all power assertions system-wide
```

---

## Windows

### The core mechanism

Windows has no single built-in command like `caffeinate`. The robust, no-install
equivalent is the `SetThreadExecutionState` API: a process declares "keep the
system awake" and the request is held only while that process is alive. The
helper script wraps this in a detached, time-boxed background process.

### Case A — the task is a single command you can wrap

Run the keep-awake for slightly longer than the command, kick off the command,
and stop when done. (Windows can't "wrap" a command the way `caffeinate` does,
so use the start/stop pattern even for single commands.)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\keep_awake.ps1 start 3600
npm test
powershell -ExecutionPolicy Bypass -File scripts\keep_awake.ps1 stop
```

### Case B — many steps over time (the usual agent case)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\keep_awake.ps1 start 7200
# ... do the long task ...
powershell -ExecutionPolicy Bypass -File scripts\keep_awake.ps1 stop
```

Same rule as macOS: the timeout is a safety cap; **always `stop`** when done.

### The lid-close caveat on Windows

Keeping the system awake is necessary but not always sufficient. If **"When I
close the lid"** is set to *Sleep*, closing the lid can still sleep the machine
regardless of the keep-awake request. For a reliable closed-lid run, the user
should set the lid-close action to **"Do nothing"**:

> Control Panel → Power Options → "Choose what closing the lid does" → set
> "When I close the lid" (Plugged in) to **Do nothing**.

This skill does **not** change that global setting by design — it only prevents
idle/system sleep for the duration of the task. Mention this to the user when
they specifically want to close the lid.

### Inspect / debug (Windows)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\keep_awake.ps1 status
powercfg /requests   # all power requests (run as admin for full detail)
```

---

## Always clean up (both platforms)

The single most important habit: **the keep-awake must not outlive the task.** A
laptop that silently never sleeps drains battery, runs hot, and erodes the
user's trust. After finishing — or if the task fails, or the user cancels —
release it:

- macOS: `bash scripts/keep_awake.sh stop` (automatic if you used Case A wrapping)
- Windows: `powershell -ExecutionPolicy Bypass -File scripts\keep_awake.ps1 stop`

## Communicating with the user

Be brief and concrete. When you start a long task with keep-awake, say so in one
line, including the cap and the relevant caveat:

> macOS — "Starting the build with keep-awake on (capped at 2h). You can close
> the lid — just keep it plugged in, since a MacBook on battery still sleeps on
> lid close. I'll release it when the build finishes."

> Windows — "Keep-awake on (capped at 2h). To close the lid, set the lid action
> to 'Do nothing' in Power Options and stay plugged in. I'll release it when the
> build finishes."

When you finish, confirm you released it. Don't over-explain the flags or the API
unless asked — the user cares that the task survives and that their battery is
safe afterward.

## What this skill does NOT do

- It cannot keep a **MacBook on battery** awake with the lid closed — hardware
  behavior. Tell the user to plug in.
- On Windows it cannot override a lid-close-equals-sleep power setting; that's a
  user setting to change (see above).
- It cannot override **MDM / corporate power policies** on managed machines.
- It does not change any permanent system setting — by design. If the user wants
  lid-close-never-sleeps *permanently*, that's a different request (a `pmset` /
  Power Options change, or an app like Amphetamine) — confirm they really want it
  always-on before changing global power settings.
