To use it simply, we just need to run the script:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/nicknew605-cpu/AluzSpy/refs/heads/main/loader.lua"))()
```

It works well on Delta X, otherwise I don't know 😏

If you updated from an older build, clear old config once:

```lua
pcall(delfile, "AluzSpy/config.json")
pcall(delfile, "AluzSpy/.boot")
```

---

# AluzSpy 1.2.2 Max

## Top features

1. **Single File Dump** — Everything in one `FullScripts_*.lua` plus a clean `Save_*.json` / `.txt` session (schema 4: manifest, deobf, reverse, VIP status).
2. **Deep Dump Mode** — Detects Luarmor, Luraph, MoonSec, IronBrew, Prometheus and more, then runs a deeper ~120s scan.
3. **Stage Tracking** — Full loading chain (loader → HttpGet → loadstring…) and what is still missing.
4. **Missing Payload Alerts** — Warns when only UI was dumped or feature code is missing, with next-step advice.
5. **Auto Hook Health** — Checks hooks about every 20s and reinstalls if broken. `__namecall` is installed **once**; extra capture (hx) chains in safely so s2c + hx + nc do not crash.
6. **Deobfuscate Engine** — Static cleanup + runtime string capture; auto-deobf can run on new dumps.
7. **Reverse Map** — Links remotes to scripts/closures (constants, upvalues, observed calls) with confidence scores.
8. **VIP Profiles** — `lite`, `standard`, `max`, `safe`. `AluzSpy.vip("scan")` runs dump → decode → deobf → reverse; `AluzSpy.vip("report")` exports summary.
9. **Auto Redaction** — Session reports can mask cookies, webhooks, tokens, API keys, emails, IPs, paths. `AluzSpy.vip("redact")` for existing files.
10. **Safe Loader** — Module manifest, version guard, optional commit pin (`AluzSpyRef`), disable list (`AluzSpyDisable`). Optional module failure does not block boot.

---

## Quick commands

| Command | What it does |
| --- | --- |
| `AluzSpy.help()` | List all commands |
| `AluzSpy.save()` | Write session + **FullScripts_*.lua** |
| `AluzSpy.fullDump()` | One file, all captured script sources only |
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
| `AluzSpy/FullScripts_<place>_<time>.lua` | **Main dump** — all captured sources in one file |
| `AluzSpy/Save_<place>_<time>.json` | Session metadata + dump index + log tail |
| `AluzSpy/Save_<place>_<time>.txt` | Human-readable report |
| `AluzSpy/Dump/*` | Per-script files (recovery / spill) |

---

## Known limits

- Deobfuscation is static cleanup plus runtime string capture — not a full VM devirtualizer.
- Reverse links are evidence, not proof.
- Many features need executor APIs (`getconstants`, `getupvalues`, `getscriptclosure`, `decompile`, hooks).
- Under heavy load the event queue can drop events; the drop counter is in the report.

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
