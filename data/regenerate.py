#!/usr/bin/env python3
"""Regenerate the editor's bundled dropdown catalogs (res://data/*.txt) from the monorepo.

The editor is standalone and ships snapshots of game vocab so designers pick values instead of
typing them. Re-run this whenever the underlying game data changes. Requires the FULL monorepo
checkout (this script reads the parent repo's SQLite DB, client audio/sprite assets, and Lua
scripts) — it is NOT runnable from a standalone clone of the game-editor repo.

Usage:  python3 tools/game-editor/data/regenerate.py

Line format: "value" or "value|Label". The editor shows Label and stores value.
"""
import shutil
import sqlite3
from pathlib import Path

DATA = Path(__file__).resolve().parent          # tools/game-editor/data
REPO = Path(__file__).resolve().parents[3]      # monorepo root


def write(name: str, lines: list[str]) -> None:
    (DATA / name).write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"  {name}: {len(lines)} entries")


def basenames(globpat: str, suffix: str) -> list[str]:
    return sorted(p.name[: -len(suffix)] for p in REPO.glob(globpat))


def slugify(name: str) -> str:
    # Mirrors crates/pkmn-core/src/data/slug.rs::slugify (designer JSONs reference items by slug).
    # é/É fold to 'e' (Poké Ball -> poke_ball, Flabébé -> flabebe); ♀/♂ map to f/m so Nidoran♀
    # (nidoran_f) and Nidoran♂ (nidoran_m) stay distinct. Keep in lockstep with that canonical impl.
    out, prev_us = [], True
    for ch in name:
        if ch.isascii() and ch.isalnum():
            out.append(ch.lower()); prev_us = False
        elif ch in ("é", "É"):
            out.append("e"); prev_us = False
        elif ch in ("♀", "♂"):
            if not prev_us:
                out.append("_")
            out.append("f" if ch == "♀" else "m"); prev_us = False
        elif not prev_us:
            out.append("_"); prev_us = True
    s = "".join(out)
    return s[:-1] if s.endswith("_") else s


print(f"repo: {REPO}")
print(f"out:  {DATA}")

# 1. Reference data from the Pokemon DB. (Encounter groups + resource OBJECT_TYPEs are NOT snapshotted
# here — the editor reads them live from content/encounter_data.json and content/resource_nodes.json,
# so a snapshot would only drift; see ContentScan.)
con = sqlite3.connect(REPO / "pokemon_data.db")
item_rows = con.execute("SELECT item_id, name FROM items ORDER BY name").fetchall()
species_names = [r[0] for r in con.execute("SELECT name FROM pokemon_species ORDER BY name")]
ability_names = [r[0] for r in con.execute("SELECT name FROM abilities ORDER BY name")]
move_names = [r[0] for r in con.execute("SELECT name FROM moves ORDER BY name")]
con.close()


def slug_catalog(names: list[str]) -> list[str]:  # "slug|Display", deduped
    seen, out = set(), []
    for n in names:
        s = slugify(n)
        if s and s not in seen:
            seen.add(s); out.append(f"{s}|{n}")
    return out


# Slug catalogs for trainer/encounter references (species/ability/move are lower-snake in those JSONs).
write("species_slugs.txt", slug_catalog(species_names))
write("ability_slugs.txt", slug_catalog(ability_names))
write("move_slugs.txt", slug_catalog(move_names))
# Natures — fixed 25 (trainer `nature` field, lower-snake).
write("natures.txt", ["hardy", "lonely", "brave", "adamant", "naughty", "bold", "docile", "relaxed",
	"impish", "lax", "timid", "hasty", "serious", "jolly", "naive", "modest", "mild", "quiet",
	"bashful", "rash", "calm", "gentle", "sassy", "careful", "quirky"])
write("items.txt", [f"{i}|{n}" for (i, n) in item_rows])  # picker by id (value = item_id, label = name)
_seen, _slugs = set(), []
for (i, n) in item_rows:  # picker by slug, for JSONs that reference items by lower-snake name (shops, trainers)
    s = slugify(n)
    if s and s not in _seen:
        _seen.add(s); _slugs.append(f"{s}|{n}")
write("item_slugs.txt", _slugs)

# 2. Music (overworld BGM + battle BBGM) + 3. ambience — client audio asset basenames.
write("bgm.txt", basenames("client/assets/audio/BGM/*.ogg", ".ogg"))
write("bbgm.txt", basenames("client/assets/audio/BBGM/*.ogg", ".ogg"))
write("ambience.txt", basenames("client/assets/audio/ambience/*.ogg", ".ogg"))

# 4. Badges — fixed 0..7 (Kanto order). Value is the leading int.
write("badges.txt", [f"{i}|{n}" for i, n in enumerate(
    ["Boulder", "Cascade", "Thunder", "Rainbow", "Soul", "Marsh", "Volcano", "Earth"])])

# 5. warp_type / 6. door_type — forward-looking client render hints (no canonical source yet).
write("warp_types.txt", ["door", "stairs", "cave", "ladder", "hole", "gap", "teleport"])
write("door_types.txt", basenames("client/assets/sprites/animations/doors/doors*.png", ".png"))

# 8. Sprite ids — ROM overworld range (0..255 superset) + custom PNG sprites (client/.../npcs).
custom = sorted(int(p.stem) for p in (REPO / "client/assets/sprites/npcs").glob("*.png"))
sprites = [f"{i}|ROM {i}" for i in range(256)] + [f"{i}|Custom {i}" for i in custom]
write("sprites.txt", sprites)

# Skills — fixed gather-skill set (matches resource_defs `skill` field).
write("skills.txt", ["foraging", "mining"])

# 9. Map index — the baked map list (names + ROM coords + seed warps), produced by tools/map-baker.
# Copied verbatim so the editor lists/seeds maps without parsing the ROM (the client gets the same file).
maps_json = REPO / "services/game-server/map-data/maps.json"
if maps_json.exists():
    shutil.copyfile(maps_json, DATA / "maps.json")
    print("  maps.json: copied from map-data")
else:
    print("  maps.json: SKIPPED (run `cargo run -p map-baker` first)")

print("done.")
