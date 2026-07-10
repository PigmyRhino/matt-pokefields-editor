class_name MapDoc
extends RefCounted
## In-memory model of one map's meta.json overlay. Mirrors the top-level schema the server reads.
## Sections the editor doesn't manage yet (the zone arrays, until Phase C2) are preserved verbatim
## through a load → save cycle so authoring never drops hand-authored data.

var is_dark := false
var interactables: Array[Interactable] = []
var warps: Array[Warp] = []
var warp_targets: Array[WarpTarget] = []
var zones: Array[Zone] = []
var tile_overrides: Array[TileOverride] = []
var collision_overrides: Array[CollisionOverride] = []
var _extra: Dictionary = {}


func to_dict() -> Dictionary:
	var d := _extra.duplicate(true)
	d["properties"] = { "is_dark": is_dark }
	d["interactables"] = _dump(interactables)
	d["warps"] = _dump(warps)
	d["warp_targets"] = _dump(warp_targets)
	d["tile_overrides"] = _dump(tile_overrides)
	d["collision_overrides"] = _dump(collision_overrides)
	# Zones fan out into the four typed arrays; resource areas bind the resource-node ids inside them.
	var by_key := { "area_zones": [], "encounter_zones": [], "gate_zones": [], "resource_areas": [] }
	for z in zones:
		if z.category == "ResourceArea":
			by_key[z.array_key()].append(z.to_dict(_placement_ids_in(z)))
		else:
			by_key[z.array_key()].append(z.to_dict())
	for key in by_key:
		d[key] = by_key[key]
	return d


static func from_dict(d: Dictionary) -> MapDoc:
	var doc := MapDoc.new()
	var props: Dictionary = d.get("properties", {})
	doc.is_dark = bool(props.get("is_dark", false))
	for raw in d.get("interactables", []):
		doc.interactables.append(Interactable.from_dict(raw))
	for raw in d.get("warps", []):
		doc.warps.append(Warp.from_dict(raw))
	for raw in d.get("warp_targets", []):
		doc.warp_targets.append(WarpTarget.from_dict(raw))
	for raw in d.get("tile_overrides", []):
		doc.tile_overrides.append(TileOverride.from_dict(raw))
	for raw in d.get("collision_overrides", []):
		doc.collision_overrides.append(CollisionOverride.from_dict(raw))
	for raw in d.get("area_zones", []):
		doc.zones.append(Zone.from_dict("Area", raw))
	for raw in d.get("encounter_zones", []):
		doc.zones.append(Zone.from_dict("Encounter", raw))
	for raw in d.get("gate_zones", []):
		doc.zones.append(Zone.from_dict("Gate", raw))
	for raw in d.get("resource_areas", []):
		doc.zones.append(Zone.from_dict("ResourceArea", raw))
	doc._extra = d.duplicate(true)
	for key in ["properties", "interactables", "warps", "warp_targets", "tile_overrides",
			"collision_overrides", "area_zones", "encounter_zones", "gate_zones", "resource_areas"]:
		doc._extra.erase(key)
	return doc


# -- grid override edits (tile painting + collision) -------------------------------------------------

## Paint `src` onto (tile, layer), updating an existing override there or appending a new one.
func set_tile_override(tile: Vector2i, layer: int, src: Vector2i) -> void:
	var ov := tile_override_at(tile, layer)
	if ov != null:
		ov.src = src
		return
	var t := TileOverride.new()
	t.tile = tile
	t.layer = layer
	t.src = src
	tile_overrides.append(t)


func erase_tile_override(tile: Vector2i, layer: int) -> void:
	var ov := tile_override_at(tile, layer)
	if ov != null:
		tile_overrides.erase(ov)


func tile_override_at(tile: Vector2i, layer: int) -> TileOverride:
	for ov in tile_overrides:
		if ov.tile == tile and ov.layer == layer:
			return ov
	return null


## Set the collision at `tile` to `flags`, or remove the override (revert to ROM) when `flags` matches
## the ROM's, keeping the set sparse.
func set_collision_override(tile: Vector2i, flags: int, rom_flags: int) -> void:
	var ov := collision_override_at(tile)
	if flags == rom_flags:
		if ov != null:
			collision_overrides.erase(ov)
		return
	if ov != null:
		ov.flags = flags
		return
	var c := CollisionOverride.new()
	c.tile = tile
	c.flags = flags
	collision_overrides.append(c)


func collision_override_at(tile: Vector2i) -> CollisionOverride:
	for ov in collision_overrides:
		if ov.tile == tile:
			return ov
	return null


## { Vector2i tile: flags } of the collision overrides, for the collision overlay's effective-flags draw.
func collision_override_map() -> Dictionary:
	var out: Dictionary = {}
	for ov in collision_overrides:
		out[ov.tile] = ov.flags
	return out


## Resource-node interactable ids governed by a resource area: those whose tile falls inside its
## polygon AND whose OBJECT_TYPE is one of the area's `object_types`. Mirrors the map-processor binding
## (main.rs::bind_and_validate_resource_areas) — `object_types` is the filter, so other node types
## sharing the polygon (e.g. a forage_tree inside a forage_node area) are NOT bound to it. The server
## treats `placement_ids` as the authoritative pool, so this filter is where the scoping happens.
func _placement_ids_in(z: Zone) -> Array:
	var ids: Array = []
	for it in interactables:
		if it.kind != "ResourceNode" or not z.contains_tile(it.tile):
			continue
		if str(it.properties.get("OBJECT_TYPE", "")) in z.object_types:
			ids.append(it.id)
	return ids


func save_to(path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("MapDoc: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify(to_dict(), "  "))
	return true


static func load_from(path: String) -> MapDoc:
	if not FileAccess.file_exists(path):
		return MapDoc.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("MapDoc: invalid JSON at %s" % path)
		return MapDoc.new()
	return from_dict(parsed)


func _dump(items: Array) -> Array:
	var out: Array = []
	for it in items:
		out.append(it.to_dict())
	return out
