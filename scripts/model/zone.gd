class_name Zone
extends RefCounted
## A polygonal zone. One class covers the four meta.json zone arrays via `category`. The polygon is a
## list of tile-corner vertices, serialized as [[x,y],...] floats (matching pkmn_core::world::Polygon).

const CATEGORIES := ["Area", "Encounter", "Gate", "ResourceArea"]
const CLIMATES := ["none", "temperate"]
const ENCOUNTER_TERRAINS := ["grass_patch", "cave_floor", "water"]

var category := "Area"
var name := ""
var polygon: Array[Vector2i] = []
## Editor-only painted tile set (key Vector2i -> true). The serialized `polygon` is derived from this
## via rebuild_polygon_from_cells(); on load `cells` is reconstructed via rasterize_from_polygon().
var cells: Dictionary = {}
## Non-empty after a rebuild that couldn't be expressed as one simple ring (holes / disjoint tiles).
var rebuild_warning := ""

# Area
var display_name := ""
var day_track := ""
var night_track := ""
var day_ambience := ""
var night_ambience := ""
var climate := "none"
# Encounter
var terrain := "grass_patch"
var encounter_group := ""
var fish_encounter_group := ""
var fish_rod_tier := 0
# Gate
var requires_flag: Array[String] = []
var forbids_flag: Array[String] = []
var requires_badge: Array[int] = []
var requires_item: Array = []        ## [{ "item_id": int, "min_qty": int }]
var requires_party_min := -1         ## -1 = none
## Blocked-message text per failed-predicate key (e.g. "flag:starter_chosen"). Lives on the gate so
## the copy travels with it; mirrors pkmn_core::gate::Gate::messages.
var gate_messages: Dictionary = {}
# Resource
var object_types: Array[String] = []
var max_active := 1


## The meta.json array this category serializes into.
func array_key() -> String:
	match category:
		"Encounter": return "encounter_zones"
		"Gate": return "gate_zones"
		"ResourceArea": return "resource_areas"
		_: return "area_zones"


## `placement_ids` (Resource only) is computed by the caller from the interactables inside the polygon.
func to_dict(placement_ids: Array = []) -> Dictionary:
	var d: Dictionary = { "name": name, "polygon": _poly_dict() }
	match category:
		"Area":
			d["display_name"] = display_name
			d["day_track"] = day_track
			d["night_track"] = night_track
			d["day_ambience"] = day_ambience
			d["night_ambience"] = night_ambience
			d["climate"] = climate
		"Encounter":
			d["terrain"] = terrain
			d["encounter_group"] = encounter_group
			d["fish_encounter_group"] = fish_encounter_group
			d["fish_rod_tier"] = fish_rod_tier
		"Gate":
			d["gate"] = _gate_dict()
		"ResourceArea":
			d["object_types"] = object_types.duplicate()
			d["max_active"] = max_active
			d["placement_ids"] = placement_ids
	return d


static func from_dict(cat: String, d: Dictionary) -> Zone:
	var z := Zone.new()
	z.category = cat
	z.name = str(d.get("name", ""))
	for p in d.get("polygon", []):
		z.polygon.append(Vector2i(int(p[0]), int(p[1])))
	match cat:
		"Area":
			z.display_name = str(d.get("display_name", ""))
			z.day_track = str(d.get("day_track", ""))
			z.night_track = str(d.get("night_track", ""))
			z.day_ambience = str(d.get("day_ambience", ""))
			z.night_ambience = str(d.get("night_ambience", ""))
			z.climate = str(d.get("climate", "none"))
		"Encounter":
			z.terrain = str(d.get("terrain", "grass_patch"))
			z.encounter_group = str(d.get("encounter_group", ""))
			z.fish_encounter_group = str(d.get("fish_encounter_group", ""))
			z.fish_rod_tier = int(d.get("fish_rod_tier", 0))
		"Gate":
			var g: Dictionary = d.get("gate", {})
			for f in g.get("requires_flag", []):
				z.requires_flag.append(str(f))
			for f in g.get("forbids_flag", []):
				z.forbids_flag.append(str(f))
			for b in g.get("requires_badge", []):
				z.requires_badge.append(int(b))
			for it in g.get("requires_item", []):
				z.requires_item.append({ "item_id": int(it.get("item_id", 0)), "min_qty": int(it.get("min_qty", 1)) })
			z.requires_party_min = int(g.get("requires_party_min", -1))
			z.gate_messages = (g.get("messages", {}) as Dictionary).duplicate()
		"ResourceArea":
			for ot in d.get("object_types", []):
				z.object_types.append(str(ot))
			z.max_active = int(d.get("max_active", 1))
	z.rasterize_from_polygon()
	return z


# -- tile painting (editor authoring; polygon is derived from `cells`) --

func paint(tile: Vector2i) -> void:
	cells[tile] = true
	rebuild_polygon_from_cells()


func erase(tile: Vector2i) -> void:
	cells.erase(tile)
	rebuild_polygon_from_cells()


func tile_count() -> int:
	return cells.size()


## Reconstruct the painted tile set from `polygon` (every cell whose center falls inside it), so a
## loaded zone can be re-painted. Inverse of rebuild_polygon_from_cells().
func rasterize_from_polygon() -> void:
	cells = {}
	if polygon.size() < 3:
		return
	var minx := polygon[0].x
	var maxx := polygon[0].x
	var miny := polygon[0].y
	var maxy := polygon[0].y
	for v in polygon:
		minx = mini(minx, v.x)
		maxx = maxi(maxx, v.x)
		miny = mini(miny, v.y)
		maxy = maxi(maxy, v.y)
	for ty in range(miny, maxy):
		for tx in range(minx, maxx):
			if contains_tile(Vector2i(tx, ty)):
				cells[Vector2i(tx, ty)] = true


## Trace the rectilinear outer boundary of `cells` into corner vertices. Each cell edge not shared
## with a neighbour is a directed boundary half-edge oriented so the filled interior is on its right;
## following them from the top-left-most vertex yields the outer ring. Collinear runs are collapsed.
func rebuild_polygon_from_cells() -> void:
	rebuild_warning = ""
	if cells.is_empty():
		polygon = []
		return
	var edges: Dictionary = {}  # Vector2i start -> Array[Vector2i] ends
	for c: Vector2i in cells:
		var x := c.x
		var y := c.y
		if not cells.has(Vector2i(x, y - 1)):
			_add_edge(edges, Vector2i(x, y), Vector2i(x + 1, y))
		if not cells.has(Vector2i(x + 1, y)):
			_add_edge(edges, Vector2i(x + 1, y), Vector2i(x + 1, y + 1))
		if not cells.has(Vector2i(x, y + 1)):
			_add_edge(edges, Vector2i(x + 1, y + 1), Vector2i(x, y + 1))
		if not cells.has(Vector2i(x - 1, y)):
			_add_edge(edges, Vector2i(x, y + 1), Vector2i(x, y))
	var ring := _trace_ring(edges, _min_vertex(edges))
	for k: Vector2i in edges:
		if not (edges[k] as Array).is_empty():
			rebuild_warning = "holes/disjoint tiles — outline traces the outer edge only"
			break
	polygon = _collapse_collinear(ring)


func _add_edge(edges: Dictionary, a: Vector2i, b: Vector2i) -> void:
	if not edges.has(a):
		edges[a] = ([] as Array[Vector2i])
	(edges[a] as Array).append(b)


func _min_vertex(edges: Dictionary) -> Vector2i:
	var best := Vector2i(0x7fffffff, 0x7fffffff)
	for k: Vector2i in edges:
		if k.y < best.y or (k.y == best.y and k.x < best.x):
			best = k
	return best


func _trace_ring(edges: Dictionary, start: Vector2i) -> Array[Vector2i]:
	var ring: Array[Vector2i] = []
	var cur := start
	while true:
		ring.append(cur)
		var outs: Array = edges.get(cur, [])
		if outs.is_empty():
			break
		cur = outs.pop_back()
		if cur == start:
			break
	return ring


func _collapse_collinear(ring: Array[Vector2i]) -> Array[Vector2i]:
	var n := ring.size()
	if n < 3:
		return ring
	var out: Array[Vector2i] = []
	for i in n:
		var prev: Vector2i = ring[(i - 1 + n) % n]
		var cur: Vector2i = ring[i]
		var nxt: Vector2i = ring[(i + 1) % n]
		var d1 := cur - prev
		var d2 := nxt - cur
		if d1.x * d2.y - d1.y * d2.x != 0:  # keep only direction-change corners
			out.append(cur)
	return out


## Ray-cast point-in-polygon at the tile's center (matches Rust Polygon::contains_tile).
func contains_tile(tile: Vector2i) -> bool:
	var n := polygon.size()
	if n < 3:
		return false
	var px := float(tile.x) + 0.5
	var py := float(tile.y) + 0.5
	var inside := false
	var j := n - 1
	for i in n:
		var xi := float(polygon[i].x)
		var yi := float(polygon[i].y)
		var xj := float(polygon[j].x)
		var yj := float(polygon[j].y)
		if ((yi > py) != (yj > py)) and (px < (xj - xi) * (py - yi) / (yj - yi) + xi):
			inside = not inside
		j = i
	return inside


func _poly_dict() -> Array:
	var out: Array = []
	for v in polygon:
		out.append([float(v.x), float(v.y)])
	return out


func _gate_dict() -> Dictionary:
	var g: Dictionary = {}
	if not requires_flag.is_empty():
		g["requires_flag"] = requires_flag.duplicate()
	if not forbids_flag.is_empty():
		g["forbids_flag"] = forbids_flag.duplicate()
	if not requires_badge.is_empty():
		g["requires_badge"] = requires_badge.duplicate()
	if not requires_item.is_empty():
		g["requires_item"] = requires_item.duplicate(true)
	if requires_party_min >= 0:
		g["requires_party_min"] = requires_party_min
	if not gate_messages.is_empty():
		g["messages"] = gate_messages.duplicate()
	return g
