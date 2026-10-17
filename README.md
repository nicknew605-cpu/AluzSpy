# AluzSpy 1.2.2 Max

```lua
pcall(delfile, "AluzSpy/config.json")
pcall(delfile, "AluzSpy/.boot")
loadstring(game:HttpGet("https://raw.githubusercontent.com/nicknew605-cpu/AluzSpy/refs/heads/main/loader.lua"))()
```

```lua
AluzSpy.vip("profile", "max")
AluzSpy.save()
AluzSpy.fullDump()
```

Primary output: `AluzSpy/FullScripts_<placeId>_<time>.lua`

Also: session `.json` / `.txt`, per-script files under `AluzSpy/Dump/`.

| Command | Action |
|---------|--------|
| AluzSpy.save() | Session + FullScripts |
| AluzSpy.fullDump() | Sources only, one file |
| AluzSpy.vip("scan") | dump decode deobf reverse |
| AluzSpy.vip("profile","max") | full modules |
| AluzSpy.modules() | status |
| AluzSpy.health() | hook health |
| AluzSpy.help() | all commands |

Single namecall design. Educational use only.
