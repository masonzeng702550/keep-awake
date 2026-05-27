# keep-awake

A Claude Code skill that keeps your laptop awake so long-running agent tasks
survive a closed lid or an idle screen — on **macOS** and **Windows**.

讓筆電在闔蓋或閒置時不睡眠的 Claude Code skill，使長時間執行的 agent 任務不會中斷——支援 **macOS** 與 **Windows**。

---

## English

### What problem this solves

You start a long agent task — a big refactor, a test suite, an overnight run —
then close the lid and walk away. The OS sleeps a couple of minutes later and the
task freezes at step three. This skill holds a temporary "don't sleep" request
for **exactly the duration of the task**, then lets the laptop go back to normal
power-saving. No app to install, no permanent setting changed.

- **macOS**: wraps the built-in `caffeinate` command.
- **Windows**: uses the `SetThreadExecutionState` Win32 API via PowerShell.

### Install (Claude Code)

```bash
# Clone, then copy into your Claude Code skills directory
git clone https://github.com/masonzeng702550/keep-awake.git
cp -r keep-awake ~/.claude/skills/keep-awake

# macOS only: make the shell helper executable
chmod +x ~/.claude/skills/keep-awake/scripts/keep_awake.sh
```

On Windows the PowerShell script needs no chmod. Once the folder is in your
skills directory, Claude Code picks it up automatically.

### How it triggers

You don't call it manually. When you ask Claude Code to run something long and
mention closing the lid, leaving the laptop, running overnight, or "don't let it
sleep," the skill activates, starts keep-awake before the work, and releases it
when the task finishes.

### Manual usage

macOS:

```bash
# Wrap a single command (cleanest — auto-releases on exit)
caffeinate -i -s npm test

# Or start/stop around a multi-step task (cap at 2 hours)
bash scripts/keep_awake.sh start 7200
# ... work ...
bash scripts/keep_awake.sh stop
bash scripts/keep_awake.sh status   # check
```

Windows (PowerShell):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\keep_awake.ps1 start 7200
# ... work ...
powershell -ExecutionPolicy Bypass -File scripts\keep_awake.ps1 stop
powershell -ExecutionPolicy Bypass -File scripts\keep_awake.ps1 status
```

The timeout is a **safety cap**, not a target — always `stop` when the task is
done so the laptop can sleep again. The cap only prevents a crashed session from
keeping the machine awake forever.

### Important caveats

- **macOS, closed lid, on battery**: won't work. A MacBook sleeps on lid close on
  battery by hardware design. **Plug in** for closed-lid runs.
- **Windows, closed lid**: keeping the system awake isn't always enough. If
  "When I close the lid" is set to *Sleep*, the lid still sleeps the machine. Set
  it to **Do nothing** in Control Panel → Power Options → "Choose what closing
  the lid does" (Plugged in), at least while running.
- **Managed / corporate machines**: MDM power policies can force sleep and cannot
  be overridden by this skill.
- **By design, no permanent change**: keep-awake is released after the task. If
  you want lid-close-never-sleeps permanently, change Power Options / `pmset`
  yourself, or use an app like Amphetamine (macOS).

### Files

```
keep-awake/
├── SKILL.md                 # the skill itself (instructions for Claude)
├── README.md                # this file
└── scripts/
    ├── keep_awake.sh        # macOS helper (caffeinate)
    └── keep_awake.ps1       # Windows helper (SetThreadExecutionState)
```

### License

MIT — see [LICENSE](LICENSE).

---

## 繁體中文

### 解決什麼問題

你開了一個長時間的 agent 任務——大型重構、跑測試、過夜批次——然後闔上筆電離開。
系統幾分鐘後睡眠，任務就卡在第三步。這個 skill 會在**任務執行期間**暫時持有一個
「別睡」的請求，任務一結束就讓筆電恢復正常省電。不用裝任何 app，也不改任何永久設定。

- **macOS**：包裝內建的 `caffeinate` 指令。
- **Windows**：透過 PowerShell 呼叫 `SetThreadExecutionState` Win32 API。

### 安裝（Claude Code）

```bash
# 複製專案後，放進 Claude Code 的 skills 目錄
git clone https://github.com/masonzeng702550/keep-awake.git
cp -r keep-awake ~/.claude/skills/keep-awake

# 僅 macOS：給 shell 腳本執行權限
chmod +x ~/.claude/skills/keep-awake/scripts/keep_awake.sh
```

Windows 的 PowerShell 腳本不需要 chmod。資料夾放進 skills 目錄後，Claude Code 會自動載入。

### 如何觸發

你不需要手動呼叫。當你請 Claude Code 跑長任務，並提到「要闔蓋」「人會離開」
「過夜跑」「別讓它睡」這類話時，skill 就會啟動：開工前先防睡，任務結束後自動釋放。

### 手動使用

macOS：

```bash
# 直接包住單一指令（最乾淨，跑完自動解除）
caffeinate -i -s npm test

# 或在多步驟任務前後 start/stop（上限設 2 小時）
bash scripts/keep_awake.sh start 7200
# ... 做事 ...
bash scripts/keep_awake.sh stop
bash scripts/keep_awake.sh status   # 查看狀態
```

Windows（PowerShell）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\keep_awake.ps1 start 7200
# ... 做事 ...
powershell -ExecutionPolicy Bypass -File scripts\keep_awake.ps1 stop
powershell -ExecutionPolicy Bypass -File scripts\keep_awake.ps1 status
```

那個 timeout 是**安全上限**，不是目標——任務做完一定要 `stop`，讓筆電能再次睡眠。
上限的用途只是避免 session 掛掉後機器永遠不睡。

### 重要限制

- **macOS、闔蓋、用電池**：沒用。MacBook 在電池模式下闔蓋是硬體層級強制睡眠。
  闔蓋跑任務請**插電**。
- **Windows、闔蓋**：只讓系統不睡有時不夠。若「闔上螢幕時」設定是*睡眠*，
  闔蓋仍會讓機器睡著。請到 控制台 → 電源選項 → 「選擇關閉上蓋的作用」，
  把（插電狀態的）「闔上螢幕時」改成 **不採取任何動作**，至少在跑任務期間。
- **公司／受管控的機器**：MDM 電源政策可能強制睡眠，這個 skill 蓋不過去。
- **刻意不做永久變更**：keep-awake 在任務後就釋放。若你想要「闔蓋永遠不睡」，
  請自己改電源選項／`pmset`，或用 Amphetamine 這類 app（macOS）。

### 檔案結構

```
keep-awake/
├── SKILL.md                 # skill 本體（給 Claude 看的說明）
├── README.md                # 本檔
└── scripts/
    ├── keep_awake.sh        # macOS 輔助腳本（caffeinate）
    └── keep_awake.ps1       # Windows 輔助腳本（SetThreadExecutionState）
```

### 授權

MIT — 見 [LICENSE](LICENSE)。
