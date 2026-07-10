# Trainers

One file per battler NPC. The filename stem **must** equal the NPC's
`unique_name` from Tiled — that's the only identifier; there is no separate
slug. Each TMX entry is its own self-contained battler (a dawn-shift NPC and a
night-shift NPC of the "same character" are independent records, with their
own defeat flags).

Trainer corpora are loaded directly by the game-server at boot from this
directory tree — there is **no SQLite or Python generator step**. Edit a JSON,
restart the server, done. Validation is fail-loud: any unresolvable slug,
out-of-range IV/EV, illegal level spec, malformed initial_field, or duplicate
unique_name is collected across every file and reported together before the
server starts accepting connections.

## Wiring an NPC up

1. In the NPC's `.tmx`, change `INTERACT_TYPE` from `"simple_dialogue"` (the
   default for all NPCs) to `"trainer"`. That's the same designer-facing
   property used everywhere else (`pc`, `poke_center`, `crafting`, …) —
   `"trainer"` just routes to `trainer.lua`. The server uses the NPC's
   existing `unique_name` to find the matching trainer file.
2. Drop a JSON file at `<region>/<area>/<unique_name>.json` (the directory
   structure is yours; the filename is what matters).
3. Restart the game-server.

The map-processor build will fail loud if you typo the `INTERACT_TYPE` value
(e.g. `"trianer"` would error out at build time with the file path and the
unresolved value).

## Schema

Every field is written out in every file with its default visible. The
validator also accepts the trimmed form (omit a field, get its default), but
the long form means you don't have to remember what's editable.

```jsonc
{
  "unique_name": "vc_battler_graham",     // matches filename + the NPC's TMX unique_name
  "display_name": "Night Officer Graham",
  "sprite": null,                         // string or null
  "rank": "Ace",                          // Novice | Amateur | Ace | Pro | Master | Champion | Elite
  "music_key": null,                      // string or null — null falls back to map default
  "payout_base": 800,                     // pokeyen on victory
  "payout_per_level": 30,                 // added × the trainer's highest mon level
  "badge_award": null,                    // 0..7, or null for non-leaders

  "items": [                              // bag the AI can use mid-battle
    { "item": "super_potion", "qty": 2 }  // qty >= 1; one row per item id
  ],

  "initial_field": {                      // optional pre-set battlefield. null is fine.
    "weather": "SunnyDay",                // Clear | Rain | SunnyDay | Sandstorm | Hail | Snow
    "terrain": null,                      // Electric | Grassy | Misty | Psychic
                                          // | SoaringWinds | WrithingMire | HauntedArena
    "field_effects": {                    // per-side hazards / screens. keys: "trainer", "player"
      "trainer": [
        { "type_": "StealthRock" },
        { "type_": "Spikes", "stack_count": 2 }
        // others: Reflect, LightScreen, ToxicSpikes, StickyWeb, Tailwind,
        //         Safeguard, LuckyChant, AuroraVeil, Mist
      ]
    },
    "global_effects": {
      "TrickRoom": { "duration": 5 }      // currently the only global effect
    }
  },

  "team": [                               // 1..6 mons, lead first
    {
      "species":    "noctowl",            // lower_snake of canonical name
      "ability":    "insomnia",
      "nature":     "modest",             // 25 valid; full list in crates/pkmn-core/src/enums/nature.rs
      "gender":     "female",             // "male" | "female" | "genderless" | null (rolls)
      "is_shiny":   true,
      "held_item":  "sitrus_berry",       // null = no item
      "fixed_level": 25,                  // OR replace with "level_offset": <int>; never both
      "iv_hp": 31, "iv_atk": 31, "iv_def": 31,
      "iv_spa": 31, "iv_spd": 31, "iv_spe": 31,    // each 0..31
      "ev_hp": 252, "ev_atk": 0, "ev_def": 0,
      "ev_spa": 252, "ev_spd": 0, "ev_spe": 6,     // each 0..252, sum <= 510
      "moves": ["air_slash", "psychic", "roost", "extrasensory"]
      // 0..4 moves. Empty / short slots auto-fill from the species's level-up
      // learnset at the resolved level.
    }
  ]
}
```

`level_offset` resolves at battle time against the player's highest-level mon
(clamped to 1..100). Use `fixed_level` for signature mons, `level_offset` for
mooks that should track player progression.

## Slugs

`species`, `ability`, `move`, `item` slugs are the lower_snake form of the
canonical name (`Vital Spirit` → `vital_spirit`, `Mr. Mime` → `mr_mime`). The
server resolves them against the loaded `PokemonDataCache` at boot. To find
one without launching:

```bash
python -c "import sqlite3; c=sqlite3.connect('pokemon_data.db'); \
  [print(r[0]) for r in c.execute(\"SELECT name FROM items WHERE name LIKE '%berry%'\")]"
```

## Dialogue

Trainer dialogue is keyed by `<unique_name>.{start,loss,win,post_defeat}` in
`services/game-server/scripts/lib/trainer_dialogue.lua`:

```lua
TRAINER_DIALOGUE = {
    ["vc_battler_graham.start"] = "Halt! It's well past curfew.",
    ["vc_battler_graham.loss"]  = "...Hmph. Carry on, then.",
    ...
}
```

Use `\n` for newlines. Hot-reloaded — no server restart needed.

Set a key to `null` and that beat is silent.

## Rematches

Authored as separate NPC entries in Tiled with their own `unique_name`s
(`vc_battler_graham_rematch`, etc.) and their own trainer JSONs. The defeat
flag is per-NPC (`trainer_defeated:<unique_name>`), so the rematch NPC's
interact script can gate visibility on whether the original Graham has been
beaten.
