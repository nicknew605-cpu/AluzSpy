To use it simply, we just need to run the script:

```
loadstring(game:HttpGet("https://raw.githubusercontent.com/nicknew605-cpu/AluzSpy/refs/heads/main/loader.lua"))()
```

It works well on Delta X, otherwise I don't know 😏

# Script features:

[#script-features](#script-features)

**Top 10 VIP Features – AluzSpy 1.2.1 Max**

1. **Single File Dump**  
Everything is saved into one clean `Session_*.json` file instead of 30-40 separate files. Reports are schema 6 and include the module manifest, deobfuscation report, reverse map and VIP status.

2. **Deep Dump Mode**  
Automatically detects Luarmor, Luraph, MoonSec, IronBrew and more, then runs a deeper 60-second scan.

3. **Stage Tracking**  
Shows the full loading chain (loader → HttpGet → loadstring…) and clearly marks what was captured and what’s missing.

4. **Missing Payload Alerts**  
Warns you when only the UI was dumped or when the real feature code is still missing, and gives simple next-step advice.

5. **Auto Hook Health**  
Continuously checks hooks every 20 seconds and automatically reinstalls them if they break or get detected. The `__namecall` and `loadstring` hooks have separate reinstall limits with backoff, and a replaced `__namecall` is reported as a conflict.

6. **Deobfuscate Engine**  
Cleans dumped Lua without targeting any specific protector: folds constant strings and numbers, restores table-indexed strings, removes dead branches and renames junk variables with real scope tracking. Every pass is validated and rolled back if it would break the code. The report says what remains (VM or dispatch structure is flagged, not restored).

7. **Reverse Map**  
Links each remote to the scripts and closures that reference it, using constants, upvalues and observed calls. Every link has a confidence score and its evidence, and the scan is limited in time and object count.

8. **VIP Profiles**  
`lite`, `standard`, `max` and `safe` profiles. `AluzSpy.vip("scan")` runs dump, decode, deobfuscate and reverse in one go, and `AluzSpy.vip("report")` exports everything.

9. **Auto Redaction**  
Session reports mask cookies, Discord webhooks, Telegram bot tokens, bearer tokens, JWTs, API keys, emails, IPs and user folders. `AluzSpy.vip("redact")` writes sanitized copies of files you already exported.

10. **Safe Loader**  
Module manifest, version guard, optional commit pinning and a disable list. An optional module that fails never blocks boot, and a required one falls back to the cached bundle.

## Quick commands

| Command | What it does |
| --- | --- |
| `AluzSpy.help()` | List all commands |
| `AluzSpy.save()` | Write the session report |
| `AluzSpy.vip()` | Show profile and module status |
| `AluzSpy.vip("profile", "max")` | Switch profile (`lite`, `standard`, `max`, `safe`) |
| `AluzSpy.vip("scan")` | One-click scan: dump, decode, deobfuscate, reverse |
| `AluzSpy.vip("report")` | Save session report and VIP summary |
| `AluzSpy.vip("redact")` | Write redacted copies of exported files |
| `AluzSpy.vip("safe")` | Disable risky hooks |
| `AluzSpy.deobf(file)` | Deobfuscate one dumped file to `*.deobf.lua` |
| `AluzSpy.deobfAll()` | Queue every dumped file |
| `AluzSpy.deobfReport()` | Summary of deobfuscation runs |
| `AluzSpy.reverse()` | Build the closure, constant and remote map |
| `AluzSpy.reverse({deep = true})` | Also scan the GC (slower) |
| `AluzSpy.reverseFind(text)` | Search constants collected by the last scan |
| `AluzSpy.protect(name)` | Never quiet this remote |
| `AluzSpy.threshold(name, mult)` | Raise the spam thresholds for one remote |
| `AluzSpy.modules()` | Loaded, failed and disabled modules |
| `AluzSpy.set("autoDeobf", true)` | Deobfuscate automatically when a script is decoded |

## Loader options

Set these before running the loader:

```
getgenv().AluzSpyRef = "main"
getgenv().AluzSpyDisable = { vip = true }
```

`AluzSpyRef` can be a branch, a tag or a commit, so every module comes from the same version. `AluzSpyDisable` skips optional modules.

## Known limits

- Deobfuscation is static cleanup plus runtime string capture. It is not a general VM devirtualizer.
- Reverse links are evidence, not proof: a matching constant does not guarantee that a closure sends the remote.
- Many features depend on what your executor provides (`getconstants`, `getupvalues`, `getscriptclosure`, `decompile`, hooks).
- Under heavy load the event queue can drop events instead of freezing the game; the drop counter is shown in the report.

    This script is for EDUCATIONAL, LEARNING, AND ENTERTAINMENT purposes only

  # Donate
[#donate](#donate)
    You can support me by transferring money. Um, I'm Vietnamese, so if you're Vietnamese and want to support me, you can send me a private message via Telegram (@doncareok).
Thank you for your support and patronage.❤️

  # Discord server
[#discord-server](#discord-server)
    Go in to get VIP scripts, interesting scripts, etc.

    <https://discord.gg/5U4xD7qB6>

    and receive the latest notifications and updates about the script.
