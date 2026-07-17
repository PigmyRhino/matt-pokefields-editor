extends GameDataCache
## Reference-data cache (species / items / moves / abilities / clothing) for property dropdowns.
## All data is embedded in the pkmn_client GDExtension, so no external database is needed.
##
## Also resolves sprites for the data editors. Pokémon box icons and low-id item icons come from the
## optional B/W ROM via RomManager.pokemon_reader (see RomManager); custom items (id >= 1000) use the
## bundled PNGs in res://assets/sprites/items. Everything is cached and degrades to null without art.

## value -> Texture2D. Keys: int species_id (box icons) and "i<id>" strings (item icons).
var _tex_cache: Dictionary = {}
## slugify(display name) -> species_id, built once on first lookup.
var _slug_species: Dictionary = {}
## species_id -> follower NARC index and its inverse, built once from the HGSS ROM. An NPC whose
## sprite is a Pokémon stores that NARC index in render.sprite — the same overworld-sheet id space
## as any ROM character sprite (get_npc_sprite / the client both render it via get_npc_sheet), so no
## new sprite band is introduced. Only Gen 1–4 species have an HGSS following sprite; the rest are
## absent from the map. Empty until the ROM loads.
var _species_narc: Dictionary = {}
var _narc_species: Dictionary = {}
## [{value: species_id, label: name}] for the Pokémon sprite picker — every follower-capable species
## in dex order, built alongside the maps.
var _overworld_species: Array = []


func _ready() -> void:
	if not load_database():
		push_error("GameData: failed to load embedded database")


## species_id for an encounter/trainer species slug (e.g. "lotad"), or 0 if unknown.
func species_id_for_slug(slug: String) -> int:
	if slug == "":
		return 0
	if _slug_species.is_empty():
		# National-dex ids are dense from 1; scan a generous ceiling once (gaps return null cheaply).
		for id in range(1, 1026):
			var sp := get_species(id)
			if sp != null:
				_slug_species[slugify(sp.name)] = id
	return int(_slug_species.get(slug, 0))


## Lazily build the species<->follower-NARC maps by asking the HGSS ROM for each species' overworld
## sheet index (0 = none). No-op that leaves the maps empty until HGSS is loaded.
func _ensure_follower_map() -> void:
	if not _species_narc.is_empty() or not RomManager.is_hgss_loaded():
		return
	for id in range(1, 494):  # HGSS following-Pokémon sheets cover Gen 1–4 (dex 1..493)
		var narc: int = RomManager.pokemon_reader.get_follower_narc_index(id)
		if narc <= 0:
			continue
		var sp := get_species(id)
		if sp == null:
			continue
		_species_narc[id] = narc
		_narc_species[narc] = id
		_overworld_species.append({ "value": str(id), "label": str(sp.name) })


## Picker vocabulary for NPCs whose sprite is a Pokémon: every species with an HGSS overworld sprite,
## as [{value: species_id, label: name}]. Empty until the HGSS ROM is loaded.
func overworld_species_entries() -> Array:
	_ensure_follower_map()
	return _overworld_species


## The render.sprite value that draws `species_id` as an overworld Pokémon NPC: its HGSS following-
## sprite NARC index (rendered through the same get_npc_sheet path as any overworld sprite). 0 if the
## species has no overworld sprite or the ROM isn't loaded.
func npc_sprite_for_species(species_id: int) -> int:
	_ensure_follower_map()
	return int(_species_narc.get(species_id, 0))


## The species a render.sprite value denotes, or 0 if it isn't a Pokémon overworld sprite (an ordinary
## character sheet or custom PNG). Lets the inspector show a saved sprite back as "Pokémon: <species>".
func species_for_npc_sprite(sprite_id: int) -> int:
	_ensure_follower_map()
	return int(_narc_species.get(sprite_id, 0))


## Pokémon box icon (small square sprite) for a species id, or null without the B/W ROM.
func get_pokemon_icon(species_id: int) -> Texture2D:
	if species_id <= 0:
		return null
	if _tex_cache.has(species_id):
		return _tex_cache[species_id] as Texture2D
	if not RomManager.is_bw_loaded():
		return null
	var img: Image = RomManager.pokemon_reader.get_box_icon(species_id, 0)
	var tex: Texture2D = ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null
	_tex_cache[species_id] = tex
	return tex


## Item icon: items with a Gen 5 rom id (rom_item_id) come from the B/W ROM; everything else (custom
## items, clothing, poké-items without a ROM icon) uses the bundled PNGs. Mirrors the client's
## get_item_icon — the ROM icon table is indexed by rom_item_id, NOT item_id (they diverge for
## berries, held items, and machines; passing item_id would show e.g. a plate for a TM). Returns null
## when art is unavailable (e.g. a ROM-icon item before the B/W ROM has loaded — not cached, so it
## resolves once B/W loads).
func get_item_icon(item_id: int) -> Texture2D:
	if item_id <= 0:
		return null
	var key := "i%d" % item_id
	if _tex_cache.has(key):
		return _tex_cache[key] as Texture2D
	var tex: Texture2D = null
	var entry := get_item(item_id)
	if entry != null and entry.rom_item_id >= 0:
		if not RomManager.is_bw_loaded():
			return null  # ROM icon, but no ROM yet — don't cache, it may resolve once B/W loads
		var img: Image = RomManager.pokemon_reader.get_item_icon(entry.rom_item_id)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	else:
		var p := "res://assets/sprites/items/%d.png" % item_id
		if ResourceLoader.exists(p):
			tex = load(p) as Texture2D
	_tex_cache[key] = tex
	return tex


## NPC overworld sprite SHEET (4 cols × 4 rows; rows Up/Down/Left/Right, col 0 = idle). ROM-extracted
## from HGSS for id < 1000, or the bundled PNG for custom ids (>= 1000). Cached; null if unresolved.
func get_npc_sprite(sprite_id: int) -> Texture2D:
	if sprite_id < 0:
		return null
	var key := "n%d" % sprite_id
	if _tex_cache.has(key):
		return _tex_cache[key] as Texture2D
	var tex: Texture2D = null
	if sprite_id >= 1000:
		var p := "res://assets/sprites/npcs/%d.png" % sprite_id
		if ResourceLoader.exists(p):
			tex = load(p) as Texture2D
	elif RomManager.is_hgss_loaded():
		var img: Image = RomManager.pokemon_reader.get_npc_sheet(sprite_id)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	else:
		return null
	_tex_cache[key] = tex
	return tex


## A single small NPC frame (down-facing idle) for use as a dropdown/button icon, as an AtlasTexture
## over the cached sheet. Cached; null if the sheet can't be resolved.
func get_npc_icon(sprite_id: int) -> Texture2D:
	if sprite_id < 0:
		return null
	var key := "ni%d" % sprite_id
	if _tex_cache.has(key):
		return _tex_cache[key] as Texture2D
	var sheet := get_npc_sprite(sprite_id)
	if sheet == null:
		return null  # no HGSS / unresolved — don't cache, may resolve later
	var fw := sheet.get_width() / 4.0
	var fh := sheet.get_height() / 4.0
	var at := AtlasTexture.new()
	at.atlas = sheet
	at.region = Rect2(0.0, fh, fw, fh)  # row 1 = Down (ROW_FOR_DIR[0]), col 0 = idle
	_tex_cache[key] = at
	return at


## Mirrors crates/pkmn-core/src/data/slug.rs::slugify (display name -> lower-snake slug): ASCII
## alphanumerics fold to lowercase, é/É to 'e' (Poké Ball -> poke_ball), ♀/♂ to f/m (so Nidoran♀ /
## Nidoran♂ stay distinct), and every other run collapses to a single underscore. Keep in lockstep
## with that canonical impl (and data/regenerate.py's copy).
func slugify(name: String) -> String:
	var out := ""
	var prev_us := true
	for ch in name:
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			out += ch.to_lower()
			prev_us = false
		elif ch == "é" or ch == "É":
			out += "e"
			prev_us = false
		elif ch == "♀" or ch == "♂":
			if not prev_us:
				out += "_"
			out += "f" if ch == "♀" else "m"
			prev_us = false
		elif not prev_us:
			out += "_"
			prev_us = true
	return out.trim_suffix("_")
