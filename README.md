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

# AluzSpy 1.2.3 Stable

## Top features

1. **Hooks and Dump are split** — `AluzSpy/Hooks/` stores hook, remote, schema, alert, and debug data; `AluzSpy/Dump/` stores script dumps, decoded output, bytecode analysis, and the dump index. Dump sources never leak into the hook report.
2. **Max profile on start** — every launch applies the `max` profile automatically: capture, decode, net, deobf, reverse, VM dump, runtime string capture, and the watch layer are enabled. Anything you explicitly turn off is remembered and stays off.
3. **Hook Engine v2** — every hook lives in a registry with its own state, install strategy, retry counter and backoff. A hook that fails to install is retried instead of being lost forever.
4. **One capture path per remote call** — `FireServer`/`InvokeServer` are captured either through `__namecall` or through the direct function hook, never both. No more duplicated rows in the report on slow frames.
5. **Hook restore** — `AluzSpy.restore()` puts `__namecall`, `FireServer`, `InvokeServer`, `HttpGet`, `request` and the rest back to their original state, so you can leave a game completely clean.
6. **Wider hook coverage** — `HttpPost`/`HttpPostAsync` are hooked as well, the `request` global is re-resolved if a script replaces it, and runtime string capture watches `string.char`, `string.sub` and `table.concat`.
7. **Dump Engine v2** — a real disk budget: 96 MB total, per-kind quotas (script / layer / deob / bytecode / index), and LRU eviction of the least important files first.
8. **Reclaimable script quota** — the script budget is released again when scripts are garbage collected, so a long session keeps dumping instead of hitting a wall.
9. **Deep VM Dump** — Lua 5.1 bytecode is disassembled into an instruction listing with resolved constants, prototype tree, VM score and extracted URLs. Script names are written next to the dumps as `.bytecode.txt` / `.bytecode.json`.
10. **Fingerprint that learns** — the obfuscator fingerprint cache is keyed by source *and* URL, and prior observations are remembered across sessions so confidence improves over time.
11. **Watch layer** — cookie, webhook, token, and API-key redaction, remote schema shapes, exfiltration alerts, property writes, and chat capture. It reuses the existing `__newindex` hook instead of installing a conflicting second one.
12. **Stage Tracking** — full loading chain (loader → HttpGet → loadstring…) and what is still missing. `AluzSpy.stageReport()` prints each stage and error.
13. **Missing Payload Alerts** — Warns when only UI was dumped or feature code is missing, with next-step advice.
14. **Auto Hook Health** — Checks hooks about every 20s and reinstalls if broken. The probe verifies the hook is actually installed instead of guessing from traffic.
15. **Deobfuscate Engine** — Static cleanup + runtime string capture; auto-deobf runs on new dumps and writes `.deob.lua` / `.deob.json` into `Dump/`.
16. **Reverse Map** — Links remotes to scripts/closures (constants, upvalues, observed calls) with confidence scores.
17. **VIP Profiles** — `lite`, `standard`, `max`, `safe`. `AluzSpy.vip("scan")` runs dump → decode → deobf → reverse → VM analysis; `AluzSpy.vip("report")` exports a summary.
18. **Self-tuning** — the capture budget follows the measured frame time, and stale state is collected automatically. The tool keeps adjusting instead of staying stuck at a fixed setting.
19. **Safe Loader** — Module manifest, dependency check (a module is skipped loudly when its dependency is missing), version guard, optional commit pin (`AluzSpyRef`), disable list (`AluzSpyDisable`). Optional module failure does not block boot.

---

## Quick commands

| Command | What it does |
| --- | --- |
| `AluzSpy.help()` | List all commands |
| `AluzSpy.save()` | Write `Hooks/` report + `Dump/` index and full dump |
| `AluzSpy.status()` | Version, profile, stats, stage states, hook states, health, VM and dump summary |
| `AluzSpy.restore()` | Undo every installed hook and restore the originals |
| `AluzSpy.fullDump()` | One file, all captured script sources only |
| `AluzSpy.dumpIndex()` | Rebuild `Dump/Index_*.json` and `.txt` |
| `AluzSpy.paths()` | Show the active Hooks/Dump/session paths |
| `AluzSpy.watch()` | Show alerts, schema count, redaction and watch state |
| `AluzSpy.debugAll()` | Snapshot stages, debug watch, stats, and errors into `Hooks/` |
| `AluzSpy.stageReport()` | Print each loading stage and its error |
| `AluzSpy.vip()` | Show profile and module status |
| `AluzSpy.vip("profile", "max")` | Full modules (decode, net, deobf, reverse, VM, …) |
| `AluzSpy.vip("scan")` | One-click: dump, decode, deobfuscate, reverse |
| `AluzSpy.vip("report")` | Save session report and VIP summary |
| `AluzSpy.vip("redact")` | Redacted copies of exported files |
| `AluzSpy.vip("safe")` | Safer profile (fewer risky hooks) |
| `AluzSpy.deobf(file)` | Deobfuscate one dumped file |
| `AluzSpy.deobfAll()` | Queue every dumped file |
| `AluzSpy.deobfReport()` | Deobfuscation summary |
| `AluzSpy.vm("status")` | Bytecode analysis summary (runs, ok, strings, captures) |
| `AluzSpy.vm("captured")` | All strings captured at runtime |
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

The loader writes `AluzSpy/manifest.json` with the resolved version, module list and bundle hash, so you can tell two sessions apart.

---

## Output files

| Path | Content |
| --- | --- |
| `AluzSpy/Hooks/Hooks_<place>_<time>.json` | Full hook/remote/schema/alert/error snapshot since startup |
| `AluzSpy/Hooks/Hooks_<place>_<time>.txt` | Human-readable hook report, redacted when enabled |
| `AluzSpy/Hooks/debug_all.json` | Debug snapshot from `AluzSpy.debugAll()` |
| `AluzSpy/Dump/FullScripts_<place>_<time>.lua` | Optional one-file view of every captured source |
| `AluzSpy/Dump/Index_<place>_<time>.json` / `.txt` | Dump index with file names, sizes, tags, kind, and hashes |
| `AluzSpy/Dump/<tag>_<n>_*.lua` | Per-script dumps, including script recovery and spill |
| `AluzSpy/Dump/*.dec.lua` / `*.sandbox.txt` | Decoded and sandbox analysis output |
| `AluzSpy/Dump/*.deob.lua` / `*.deob.json` | Deobfuscation output and report |
| `AluzSpy/Dump/*.bytecode.txt` / `*.bytecode.json` | Lua 5.1 bytecode disassembly, constants, VM score, URLs |
| `AluzSpy/Dump/*.layer<n>.lua` | Decoded layers recovered from a dump |
| `AluzSpy/Dump/Diff_*.txt` | Structural diffs for changed scripts |

On every save the hook data is rebuilt from the live log (up to the 3000-record cap), while dump files are only referenced and indexed from `Dump/`. Redaction is applied to both the `.txt` and `.json` hook reports; it is never applied to the dumped script sources themselves.

---

## Known limits

- Deobfuscation is static cleanup plus runtime string capture — not a full VM devirtualizer.
- The VM dump recovers structure, constants and URLs from Lua 5.1 bytecode; it does not rebuild the original source of a virtualised script.
- Reverse links are evidence, not proof.
- Many features need executor APIs (`getconstants`, `getupvalues`, `getscriptclosure`, `decompile`, `getscriptbytecode`, hooks).
- Under heavy load the event queue can drop events; the drop counter is in the report.
- Watch property capture only covers movement, health, gravity, CFrame, position, anchor, and platform state; it does not mirror every instance write.
- Redaction is best-effort masking, not a guarantee that a dumped script or a custom secret format is safe to share.
- Max profile is applied on launch; use `AluzSpy.set("decode", false)` or `AluzSpy.mod("net", false)` if you need a lighter session.

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
