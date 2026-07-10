# Game Editor

A standalone Godot project for designers to author map content (NPCs, signs, facilities, resource
nodes, zones, warps) on top of the ROM-derived overworld, saving the canonical `meta.json` the
game-server reads. It is the replacement for the old Tiled → map-processor workflow.

It reuses the client's compiled `pkmn_client` GDExtension (in `addons/pkmn_client/`) for ROM map
rendering and reference data — **no client/server source is needed to run it.**

## Requirements
- Godot **4.6**.
- Three Pokémon ROMs, supplied once at first run (never shipped; copied into `user://roms/`), exactly
  as the game client uses them:
  - **FireRed (US v1.0, `BPRE`)** `.gba` — overworld map rendering (`firered.gba`).
  - **HeartGold/SoulSilver** `.nds` — overworld NPC sprites on the map (`hgss.nds`).
  - **Black/White** `.nds` — Pokémon box icons (encounters, trainer teams) + item icons (shops) in
    the data editors (`bw.nds`).

## Run
1. Open `tools/game-editor/project.godot` in Godot and press **F5** (or run the exported app).
2. On first launch, pick your three ROMs (FireRed, HGSS, B/W). After that it renders Kanto and shows
   NPC/Pokémon/item sprites.
3. **Pan:** middle-mouse drag · **Zoom:** mouse wheel · the tile under the cursor is shown top-left ·
   toggle **Show collision** to tint blocked tiles.

## Output → game (designer workflow)
The editor is **fully standalone** — it never touches the game repo. **Save** writes
`user://output/<region>.meta.json`; **Open Folder** reveals that folder. Designers hand those
output files back; the game maintainer drops each into `services/game-server/map-data/<region>/`.

## Keeping the GDExtension in sync (maintainer)
The editor uses the *same* compiled `pkmn_client` DLL as the client. After rebuilding it
(`cd client/rust && cargo build --release`), manually copy `pkmn_client.dll` /
`libpkmn_client.so` into `tools/game-editor/addons/pkmn_client/bin/` (and the client's addon).
Designers receive the editor with the DLL already in place — they don't rebuild anything.

## Editing
- **Tool** dropdown: *Select* or *Place*. **Kind** dropdown: the interactable to place.
- The **Kind** dropdown also includes **Warp** and **WarpTarget** (tile-based; a warp's *Target Warp*
  is a cross-reference dropdown of the map's warp-target names) and the four **zone** types
  (Area / Encounter / Gate / ResourceArea).
- *Place* mode → left-click an empty tile to drop a point object (auto-named `kind_x_y`). With a
  **zone** kind selected, each click adds a polygon vertex; **Finish Poly** (or Enter) closes it,
  Esc cancels. Resource areas auto-bind the resource nodes inside them on save.
- *Select* mode → left-click a point object, or inside a zone polygon, to edit it. **Delete** key or
  the inspector's delete button removes the selection.
- The right-hand **inspector** edits the selected object with dedicated fields per kind: id, kind,
  script (NPC/Sign/Facility), object type + encounter group (ResourceNode), and the full NPC set
  (sprite, direction, name, visibility, vision, behavior, waypoints). Every authored property has a
  first-class field — there is no free-form key=value box. (Any unknown keys in a loaded file are
  preserved untouched through save.)
- **Save** writes `user://output/<region>.meta.json` (sections the editor doesn't manage yet are
  preserved). **Reload** re-reads it. **Open Folder** reveals the output for hand-off.

## Status
- **Phase A (done):** render + navigate the Kanto overworld from the ROM.
- **Phase B (done):** place/select/edit/delete interactables (all 5 kinds) → save/load `meta.json`,
  validated against the server's parser by the Rust test `editor_overlay_format_round_trips`.
- **Phase B2 (done):** full NPC authoring — time-of-day visibility, trainer vision range, behavior
  (stationary / look-around / wander / patrol) with params, and patrol **waypoints** placed on the
  map (toggle *Edit waypoints*, click tiles, *Clear*).
- **Phase C1 (done):** warps + warp targets — tile placement, cross-referenced target picker.
- **Phase C2 (done):** zones (area / encounter / gate / resource) — polygon-drawing tool, per-type
  inspectors, resource-area placement binding. Format locked by `zone_warp_format_round_trips`.
- **Complete:** the editor now authors every `meta.json` section. Future polish (sprite preview,
  region switching for interiors, undo/redo) can layer on top.
