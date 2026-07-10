class_name ObjectLayer
extends Node2D
## Draws zones (filled polygons), every point placeable (interactables / warps / warp targets) as a
## colored marker, patrol waypoint lines, the in-progress polygon, and the selection highlight; and
## hit-tests a tile to the placeable or zone on it.

const KIND_COLORS := {
	"Npc": Color(0.3, 0.7, 1.0),
	"Sign": Color(0.95, 0.8, 0.3),
	"Facility": Color(0.75, 0.55, 1.0),
	"ResourceNode": Color(0.4, 0.9, 0.45),
	"Trigger": Color(1.0, 0.5, 0.5),
}
const WARP_COLOR := Color(1.0, 0.6, 0.2)
const TARGET_COLOR := Color(0.3, 0.9, 0.9)
## Interactable direction byte (Down/Left/Right/Up = 0..3) → NPC sheet row (sorted HGSS order).
const NPC_ROW_FOR_DIR := [1, 2, 3, 0]
const ZONE_COLORS := {
	"Area": Color(0.5, 0.6, 1.0),
	"Encounter": Color(0.5, 1.0, 0.6),
	"Gate": Color(1.0, 0.45, 0.45),
	"ResourceArea": Color(0.95, 0.75, 0.35),
}

@onready var _tile: int = EditorConfig.TILE_SIZE

const PROBLEM_ERR := Color(1.0, 0.3, 0.3)
const PROBLEM_WARN := Color(1.0, 0.82, 0.4)

var _doc: MapDoc = null
var _selected: Variant = null
var _font: Font
## Context for human-readable warp/target labels (see set_warp_context).
var _self_map := ""
var _incoming: Dictionary = {}
## The in-progress Ctrl-drag box-fill region (empty = none).
var _paint_box: Rect2i = Rect2i()
## model object (Interactable/Warp/WarpTarget/Zone) -> true if it has an ERROR (else a warning).
var _problem_objs: Dictionary = {}


func _ready() -> void:
	_font = ThemeDB.fallback_font


func set_doc(doc: MapDoc) -> void:
	_doc = doc
	queue_redraw()


## Mark objects flagged by validation so they get a colored ring (error = red, warning = amber).
func set_problem_objects(objs: Dictionary) -> void:
	_problem_objs = objs
	queue_redraw()


func set_selected(obj: Variant) -> void:
	_selected = obj
	queue_redraw()


## The current Ctrl-drag box-fill preview (a tile-space Rect2i; empty to clear).
func set_paint_box(box: Rect2i) -> void:
	_paint_box = box
	queue_redraw()


## Context for human-readable warp/target labels: the map being edited and a { target_name: source-map
## names } index (Catalog.incoming_sources). Set once per map load — warps then read "→ destination"
## and targets read "← source" instead of their raw `warp_x_y` / `t_x_y` ids.
func set_warp_context(self_map: String, incoming: Dictionary) -> void:
	_self_map = self_map
	_incoming = incoming
	queue_redraw()


func refresh() -> void:
	queue_redraw()


## All point placeables on `tile`, in click-cycle order: interactables (last-placed first), then warps,
## then warp-targets; [] for an empty tile. Several can share a tile (a warp sits on the target it lands
## on), so the MapEditor cycles through these on repeated clicks — the only way to reach the one beneath.
func placeables_at(tile: Vector2i) -> Array:
	var out: Array = []
	if _doc == null:
		return out
	for i in range(_doc.interactables.size() - 1, -1, -1):
		if _doc.interactables[i].tile == tile:
			out.append(_doc.interactables[i])
	for w in _doc.warps:
		if w.tile == tile:
			out.append(w)
	for t in _doc.warp_targets:
		if t.tile == tile:
			out.append(t)
	return out


## Every zone containing `tile`, topmost-first (last-drawn wins); [] if none. The MapEditor cycles
## these on repeated clicks, the only way to reach a zone hidden under another (e.g. an Encounter zone
## beneath an Area polygon) — mirroring how placeables_at lets a stacked warp-target be reached.
func zones_at(tile: Vector2i) -> Array:
	var out: Array = []
	if _doc == null:
		return out
	for i in range(_doc.zones.size() - 1, -1, -1):
		if _doc.zones[i].contains_tile(tile):
			out.append(_doc.zones[i])
	return out


func _draw() -> void:
	if _doc != null:
		for z in _doc.zones:
			_draw_zone(z)
		for it in _doc.interactables:
			var col: Color = KIND_COLORS.get(it.kind, Color.WHITE)
			# NPCs draw their actual overworld sprite (idle frame, facing direction); others use a marker.
			if it.kind == "Npc" and _draw_npc_sprite(it):
				_label(it.tile, it.id, col)
			else:
				_marker(it.tile, col, it.id)
			if it.waypoints.size() >= 2:
				var pts: PackedVector2Array = []
				for w in it.waypoints:
					pts.append(_center(w))
				draw_polyline(pts, Color(KIND_COLORS.get(it.kind, Color.WHITE), 0.85), 1.0)
			if _problem_objs.has(it):
				_ring(it.tile, _problem_objs[it])
		for w in _doc.warps:
			_marker(w.tile, WARP_COLOR, _warp_label(w))
			if _problem_objs.has(w):
				_ring(w.tile, _problem_objs[w])
		for t in _doc.warp_targets:
			_marker(t.tile, TARGET_COLOR, _target_label(t))
			if _problem_objs.has(t):
				_ring(t.tile, _problem_objs[t])

	if _selected is Zone:
		var z := _selected as Zone
		for c: Vector2i in z.cells:  # painted tiles of the active zone
			draw_rect(Rect2(Vector2(c.x * _tile, c.y * _tile), Vector2(_tile, _tile)), Color(1, 1, 1, 0.2))
		_draw_poly_outline(z.polygon, Color.WHITE, 2.0)
	elif _selected != null:
		var sp := Vector2(_selected.tile.x * _tile, _selected.tile.y * _tile)
		draw_rect(Rect2(sp, Vector2(_tile, _tile)), Color.WHITE, false, 2.0)

	if _paint_box.size.x > 0 and _paint_box.size.y > 0:  # Ctrl-drag box-fill preview
		var bp := Vector2(_paint_box.position) * _tile
		var bs := Vector2(_paint_box.size) * _tile
		draw_rect(Rect2(bp, bs), Color(0.3, 0.9, 1.0, 0.18))
		draw_rect(Rect2(bp, bs), Color(0.3, 0.9, 1.0, 0.9), false, 1.0)


func _draw_zone(z: Zone) -> void:
	if z.polygon.size() < 3:
		return
	var col: Color = ZONE_COLORS.get(z.category, Color.WHITE)
	var pts: PackedVector2Array = []
	for v in z.polygon:
		pts.append(Vector2(v.x * _tile, v.y * _tile))
	draw_colored_polygon(pts, Color(col, 0.18))
	_draw_poly_outline(z.polygon, col, 1.0)
	if _problem_objs.has(z):
		_draw_poly_outline(z.polygon, PROBLEM_ERR if _problem_objs[z] else PROBLEM_WARN, 2.0)
	if _font != null and z.name != "":
		draw_string(_font, pts[0] + Vector2(2, 10), z.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)


func _draw_poly_outline(verts: Array[Vector2i], col: Color, width: float) -> void:
	if verts.size() < 2:
		return
	var pts: PackedVector2Array = []
	for v in verts:
		pts.append(Vector2(v.x * _tile, v.y * _tile))
	pts.append(pts[0])
	draw_polyline(pts, col, width)


func _center(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * _tile, tile.y * _tile) + Vector2(_tile, _tile) * 0.5


func _marker(tile: Vector2i, col: Color, label: String) -> void:
	var origin := Vector2(tile.x * _tile, tile.y * _tile)
	var rect := Rect2(origin + Vector2.ONE, Vector2(_tile - 2, _tile - 2))
	draw_rect(rect, Color(col, 0.45))
	draw_rect(rect, col, false, 1.0)
	_label(tile, label, col)


## A colored validation ring just outside a point object's tile (error = red, warning = amber).
func _ring(tile: Vector2i, is_error: bool) -> void:
	var origin := Vector2(tile.x * _tile, tile.y * _tile)
	draw_rect(Rect2(origin - Vector2(2, 2), Vector2(_tile + 4, _tile + 4)),
		PROBLEM_ERR if is_error else PROBLEM_WARN, false, 2.0)


## "→ Viridian City" — where a warp leads (friendly destination-map name). Same-map jumps show the
## landing target ("↪ t_5_58"); a warp with no destination yet falls back to its raw name.
func _warp_label(w: Warp) -> String:
	if w.target_map == "":
		return w.name
	if w.target_map == _self_map:
		return ("↪ " + w.target_warp) if w.target_warp != "" else w.name
	return "→ " + Catalog.map_name(w.target_map)


## "← Viridian City" — where players arrive here FROM (friendly source-map names). A target no warp
## lands on falls back to its raw name.
func _target_label(t: WarpTarget) -> String:
	var src: String = _incoming.get(t.name, "")
	return ("← " + src) if src != "" else t.name


func _label(tile: Vector2i, label: String, col: Color) -> void:
	if _font != null and label != "":
		var origin := Vector2(tile.x * _tile, tile.y * _tile)
		draw_string(_font, origin + Vector2(1, -2), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col)


## Draws an NPC's overworld sprite: the idle frame for its facing direction, bottom-aligned and
## centered on its tile (sprites are often taller than one tile). Returns false if the sprite can't
## be resolved (no id / texture), so the caller falls back to a marker.
func _draw_npc_sprite(it: Interactable) -> bool:
	if it.sprite < 0:
		return false
	var tex := GameData.get_npc_sprite(it.sprite)
	if tex == null:
		return false
	var fw := tex.get_width() / 4.0
	var fh := tex.get_height() / 4.0
	var row: int = NPC_ROW_FOR_DIR[clampi(it.direction, 0, 3)]
	var src := Rect2(0.0, row * fh, fw, fh)
	var origin := Vector2(it.tile.x * _tile, it.tile.y * _tile)
	var dest := Rect2(Vector2(origin.x + (_tile - fw) * 0.5, origin.y + _tile - fh), Vector2(fw, fh))
	draw_texture_rect_region(tex, dest, src)
	return true
