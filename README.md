# EnemyHUD

A target HP bar for Final Fantasy XI ([Windower 4](https://www.windower.net/)) in a Vana'diel-style
frame: rounded navy panel with a gold rim, pill-shaped HP bar, the monster's level, who it is
attacking, what it is casting or readying, and its buffs and debuffs with timers.

## Features

- **HP bar** that turns yellow at 50% and red at 25%, with a white trail showing recent damage.
- **Name colored by claim**: yours or your party's, someone else's, or unclaimed.
- **Level**: read quietly from a `/check` the addon sends itself (hidden from the chat log), or
  from widescan. Shows `??` for monsters too strong to gauge.
- **Targeting row**: who the monster is after, colored by who they are (you, your pet, a party
  member), with their HP.
- **Cast / readying bar** for spells (with cast time) and TP moves.
- **Debuffs** (red tiles) from your spells, job abilities, blood pacts, weapon skills, TP moves and
  added effects. Spells get a countdown from their duration, using Debuffed's overwrite rules. Other
  effects have no duration in the game data, so they show until a wear-off message (5 minute cap).
  Sleep is cleared as soon as the monster takes damage or acts.
- **Monster buffs** (green tiles) in their own row: effects a monster gives itself or another
  monster. Dispel, Erase and steal effects remove them.

## Install

1. Copy the `EnemyHUD` folder into `Windower4\addons\`.
2. Extract the status icons from your own game files (they are not included in this repository):

   ```
   py -I tools\extract_status_icons.py "C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI\ROM\119\57.DAT" icons
   ```

   Run it from the `EnemyHUD` folder and use your own install path. If you use a status icon mod
   (e.g. XI-View), point it at that mod's `119\57.DAT` instead to get its icons.
3. Load it: `//lua load EnemyHUD`, or add `lua load EnemyHUD` to `Windower4\scripts\init.txt` to
   load it at every launch. If you used the official `enemybar` addon, unload it so the two don't overlap.

## Use

Drag the frame with the mouse to move it; the position is saved.

| Command | What it does |
|---|---|
| `//ehud check` | Turn the automatic level check on or off |
| `//ehud center` | Center the frame horizontally |
| `//ehud save` | Save the settings now |

## Settings

`data\settings.xml` is created the first time the addon loads.

| Setting | Default | Meaning |
|---|---|---|
| `width` | 400 | Frame width in pixels |
| `icon_size` | 14 | Buff and debuff icon size in pixels |
| `max_debuffs` | 10 | Icons per row |
| `hp_yellow` / `hp_red` | 50 / 25 | HP% at which the bar changes color |
| `auto_check` | true | Send a quiet `/check` to learn the level |
| `name_font`, `name_size`, `small_font`, `small_size` | Georgia 11 / 9 | Text style |
| `pos` | centered, y 60 | Frame position (`x = -1` centers it) |

Reload after editing: `//lua r EnemyHUD`.

## Rebuilding the textures

The rounded corners and bar caps (`corner_*.png`, `cap_*.png`) are generated, not drawn by hand:

```
py -I tools\enemyhud_textures.py .
```

`RADIUS` in the script must match `CORNER` in `EnemyHUD.lua`.

## Credits

- HP bar layout based on [enemybar](https://github.com/Windower/Lua/tree/dev/addons/enemybar) by Mike McKee (BSD 3-Clause).
- Debuff tracking and overwrite rules based on [Debuffed](https://github.com/Windower/Lua/tree/dev/addons/Debuffed) by Xathe (BSD 3-Clause).
- Written by Someonesmall with Claude (Anthropic).

## License

BSD 3-Clause. See [LICENSE](LICENSE), which keeps the original enemybar and Debuffed notices.
