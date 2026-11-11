To use it simply, we just need to run the script:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/nicknew605-cpu/AluzSpy/refs/heads/main/loader.lua"))()
```

It works well on Delta X, otherwise I don't know 😏

Config from older builds migrates automatically. If an old boot flag causes trouble after updating, clear it once:

```lua
pcall(delfile, "AluzSpy/.boot")
```

Older `AluzSpy/Save_*.json` files remain readable; new saves are written to `AluzSpy/Hooks/` and `AluzSpy/Dump/`.

---

# AluzSpy 1.2.3 Beta

## Top features

1. **Hooks and Dump are split** — `AluzSpy/Hooks/` stores hook, remote, schema, alert, and debug data; `AluzSpy/Dump/` stores script dumps, decoded output, and the dump index. Dump sources never leak into the hook report.
2. **Max profile on start** — every launch applies the `max` profile automatically, so capture, decode, net, deobf, reverse, and the watch layer are enabled unless you disable a module afterwards.
3. **Watch layer is back** — cookie, webhook, token, and API-key redaction, remote schema shapes, exfiltration alerts, property writes, and chat capture. It is guarded at every entry point and reuses the existing `__newindex` hook instead of installing a conflicting second one.
4. **Deep Dump Mode** — Detects Luarmor, Luraph, MoonSec, IronBrew, Prometheus and more, then runs a deeper ~120s scan.
5. **Stage Tracking** — Full loading chain (loader → HttpGet → loadstring…) and what is still missing. `AluzSpy.stageReport()` prints each stage and error.
6. **Missing Payload Alerts** — Warns when only UI was dumped or feature code is missing, with next-step advice.
7. **Auto Hook Health** — Checks hooks about every 20s and reinstalls if broken. `__namecall` is installed **once**; extra capture (hx) chains in safely so s2c + hx + nc do not crash.
8. **Deobfuscate Engine** — Static cleanup + runtime string capture; auto-deobf runs on new dumps and writes `.deob.lua` / `.deob.json` into `Dump/`.
9. **Reverse Map** — Links remotes to scripts/closures (constants, upvalues, observed calls) with confidence scores.
10. **VIP Profiles** — `lite`, `standard`, `max`, `safe`. `AluzSpy.vip("scan")` runs dump → decode → deobf → reverse; `AluzSpy.vip("report")` exports a summary.
11. **Safe Loader** — Module manifest, version guard, optional commit pin (`AluzSpyRef`), disable list (`AluzSpyDisable`). Optional module failure does not block boot.

---

## Quick commands

| Command | What it does |
| --- | --- |
| `AluzSpy.help()` | List all commands |
| `AluzSpy.save()` | Write `Hooks/` report + `Dump/` index and full dump |
| `AluzSpy.fullDump()` | One file, all captured script sources only |
| `AluzSpy.dumpIndex()` | Rebuild `Dump/Index_*.json` and `.txt` |
| `AluzSpy.paths()` | Show the active Hooks/Dump/session paths |
| `AluzSpy.watch()` | Show alerts, schema count, redaction and watch state |
| `AluzSpy.debugAll()` | Snapshot stages, debug watch, stats, and errors into `Hooks/` |
| `AluzSpy.stageReport()` | Print each loading stage and its error |
| `AluzSpy.vip()` | Show profile and module status |
| `AluzSpy.vip("profile", "max")` | Full modules (decode, net, deobf, reverse, …) |
| `AluzSpy.vip("scan")` | One-click: dump, decode, deobfuscate, reverse |
| `AluzSpy.vip("report")` | Save session report and VIP summary |
| `AluzSpy.vip("redact")` | Redacted copies of exported files |
| `AluzSpy.vip("safe")` | Safer profile (fewer risky hooks) |
| `AluzSpy.deobf(file)` | Deobfuscate one dumped file |
| `AluzSpy.deobfAll()` | Queue every dumped file |
| `AluzSpy.deobfReport()` | Deobfuscation summary |
| `AluzSpy.reverse()` | Closure / constant / remote map |
| `AluzSpy.reverse({deep = true})` | Also scan GC (slower) |
| `AluzSpy.reverseFind(text)` | Search constants from last scan |
| `AluzSpy.protect(name)` | Never quiet this remote |
| `AluzSpy.threshold(name, mult)` | Raise spam thresholds for one remote |
| `AluzSpy.modules()` | Loaded / failed / disabled modules |
| `AluzSpy.health()` | Hook health status |
| `AluzSpy.set("autoDeobf", true)` | Auto-deobf when a script is decoded |

---

## Loader options

Set these **before** running the loader:

```lua
getgenv().AluzSpyRef = "main"
getgenv().AluzSpyDisable = { vip = true }
getgenv().AluzSpyTrace = true
```

- `AluzSpyRef` — branch, tag, or commit (all modules from the same version)
- `AluzSpyDisable` — skip optional modules
- `AluzSpyTrace` — write `AluzSpy/trace.log`

---

## Output files

| Path | Content |
| --- | --- |
| `AluzSpy/Hooks/Hooks_<place>_<time>.json` | Full hook/remote/schema/alert/error snapshot since startup |
| `AluzSpy/Hooks/Hooks_<place>_<time>.txt` | Human-readable hook report, redacted when enabled |
| `AluzSpy/Hooks/debug_all.json` | Debug snapshot from `AluzSpy.debugAll()` |
| `AluzSpy/Dump/FullScripts_<place>_<time>.lua` | Optional one-file view of every captured source |
| `AluzSpy/Dump/Index_<place>_<time>.json` / `.txt` | Dump index with file names, sizes, tags, and hashes |
| `AluzSpy/Dump/<tag>_<n>_*.lua` | Per-script dumps, including script recovery and spill |
| `AluzSpy/Dump/*.dec.lua` / `*.sandbox.txt` | Decoded and sandbox analysis output |
| `AluzSpy/Dump/*.deob.lua` / `*.deob.json` | Deobfuscation output and report |
| `AluzSpy/Dump/Diff_*.txt` | Structural diffs for changed scripts |

On every save the hook data is rebuilt from the live log (up to the 2500-record cap), while dump files are only referenced and indexed from `Dump/`. Redaction is applied to both the `.txt` and `.json` hook reports; it is never applied to the dumped script sources themselves.

---

## Known limits

- Deobfuscation is static cleanup plus runtime string capture — not a full VM devirtualizer.
- Reverse links are evidence, not proof.
- Many features need executor APIs (`getconstants`, `getupvalues`, `getscriptclosure`, `decompile`, hooks).
- Under heavy load the event queue can drop events; the drop counter is in the report.
- Watch property capture only covers movement, health, gravity, CFrame, position, anchor, and platform state; it does not mirror every instance write.
- Redaction is best-effort masking, not a guarantee that a dumped script or a custom secret format is safe to share.
- Max profile is applied on launch; use `AluzSpy.set("decode", false)` or `AluzSpy.mod("net", false)` if you need a lighter session.

This script is for **EDUCATIONAL, LEARNING, AND ENTERTAINMENT** purposes only.

---

## Donate

You can support me by transferring money. Um, I'm Vietnamese, so if you're Vietnamese and want to support me, you can send me a private message via Telegram (**@doncareok**).  
Thank you for your support and patronage. ❤️

---

## Discord server

Go in to get VIP scripts, interesting scripts, etc.

**https://discord.gg/5U4xD7qB6**

and receive the latest notifications and updates about the script.

---

## Contact / bugs

- Email: **nicknew605@gmail.com**
- Discord: **https://discord.gg/5U4xD7qB6**
- Telegram: **@doncareok**
