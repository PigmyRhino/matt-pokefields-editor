extends Node
## Dropdown vocabulary bundled with the editor (res://data) so the tool is fully standalone — no game
## repo needed. Snapshots of game vocab (object types, scripts, encounter groups, music/ambience,
## badges, flags, warp/door types, sprites, map ids). Regenerate from the game repo with
## `python3 tools/game-editor/data/regenerate.py` (see that script).
##
## Every catalog is an Array of { "value": String, "label": String }. File lines are "value" (label
## == value) or "value|Label". Pickers display `label` and store `value`.

var scripts: Array = []
var items: Array = []
var item_slugs: Array = []
var bgm: Array = []
var bbgm: Array = []
var ambience: Array = []
var badges: Array = []
var warp_types: Array = []
var door_types: Array = []
var sprites: Array = []
var skills: Array = []
var species_slugs: Array = []
var ability_slugs: Array = []
var move_slugs: Array = []
var natures: Array = []

## Vocabulary for the `scripted` graph editor's nodes. Each entry is
## { kind, label, params: [{ name, type, label, optional?, min?, max?, default? }] }; `kind`/param
## `name`s mirror pkmn_core exactly. JSON (not .txt) — structured. `script_actions` → Action nodes
## (ScriptAction), `script_conditions` → Condition nodes (interaction_graph::Condition).
var script_actions: Array = []
var script_conditions: Array = []

## Baked map index (tools/map-baker → res://data/maps.json): every map's
## { map_id, group, num, name, kind, warps, warp_targets }. Drives the map picker, the
## warp target-map dropdown, and seed-once ROM-warp import. Replaces the old runtime ROM enumeration.
var maps: Array = []

var _map_name_by_id: Dictionary = {}  # map_id -> friendly name (lazy, built from `maps`)


func _ready() -> void:
	scripts = _load("res://data/scripts.txt")
	items = _load("res://data/items.txt")
	item_slugs = _load("res://data/item_slugs.txt")
	bgm = _load("res://data/bgm.txt")
	bbgm = _load("res://data/bbgm.txt")
	ambience = _load("res://data/ambience.txt")
	badges = _load("res://data/badges.txt")
	warp_types = _load("res://data/warp_types.txt")
	door_types = _load("res://data/door_types.txt")
	sprites = _load("res://data/sprites.txt")
	skills = _load("res://data/skills.txt")
	species_slugs = _load("res://data/species_slugs.txt")
	ability_slugs = _load("res://data/ability_slugs.txt")
	move_slugs = _load("res://data/move_slugs.txt")
	natures = _load("res://data/natures.txt")
	script_actions = _load_json_array("res://data/script_actions.json")
	script_conditions = _load_json_array("res://data/script_conditions.json")
	maps = _load_maps("res://data/maps.json")


## Friendly display name for a baked map id ("rom_5_3" → "Viridian City"), or the id itself if unknown
## (so legacy/foreign ids still render). Backs the human-readable warp/target labels on the map canvas.
func map_name(map_id: String) -> String:
	if _map_name_by_id.is_empty():
		for m in maps:
			_map_name_by_id[str(m["map_id"])] = str(m["name"])
	return str(_map_name_by_id.get(map_id, map_id))


## { target_warp_name: "Source A, Source B" } — for every warp across all maps that lands in
## `dest_map_id`, the friendly names of the maps it comes from, grouped by the warp-target it arrives
## at. Lets the editor label a map's warp-targets by where players arrive FROM (the reverse of a warp's
## "→ destination" label). A target with no inbound warp is simply absent.
func incoming_sources(dest_map_id: String) -> Dictionary:
	var by_target: Dictionary = {}  # target name -> { source friendly name: true }
	for m in maps:
		var src := str(m["name"])
		for w in m.get("warps", []):
			if str(w.get("target_map", "")) != dest_map_id:
				continue
			var tw := str(w.get("target_warp", ""))
			if tw == "":
				continue
			if not by_target.has(tw):
				by_target[tw] = {}
			by_target[tw][src] = true
	var out: Dictionary = {}
	for tw in by_target:
		out[tw] = ", ".join(by_target[tw].keys())
	return out


## Names of every warp-target on a baked map ("kanto" → ["t_5_58", "t_8_183", …]), or [] if unknown.
## Lets a warp on one map pick a Target Warp that lives on its (different) destination map.
func warp_target_names(map_id: String) -> Array:
	for m in maps:
		if str(m["map_id"]) == map_id:
			var out: Array = []
			for t in m.get("warp_targets", []):
				out.append(str(t.get("name", "")))
			return out
	return []


## The label for a value within a catalog (falls back to the value itself, so unknown/legacy values
## still render readably in a picker).
static func label_of(entries: Array, value: String) -> String:
	for e in entries:
		if e["value"] == value:
			return e["label"]
	return value


## The baked map index (an array of map dicts), or [] if absent.
func _load_maps(path: String) -> Array:
	return _load_json_array(path)


## A top-level JSON array from `path`, or [] if missing/invalid (used for structured vocab files).
func _load_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_warning("Catalog: missing %s" % path)
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		push_error("Catalog: invalid JSON array at %s" % path)
		return []
	return parsed


func _load(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_warning("Catalog: missing %s" % path)
		return []
	var out: Array = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var s := line.strip_edges()
		if s == "":
			continue
		var bar := s.find("|")
		if bar >= 0:
			out.append({ "value": s.substr(0, bar), "label": s.substr(bar + 1) })
		else:
			out.append({ "value": s, "label": s })
	return out
