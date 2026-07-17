class_name Interactable
extends RefCounted
## One authored map object, mirroring pkmn_core::interactable::InteractableDef. `to_dict()` emits the
## canonical meta.json shape verified by the Rust contract test `editor_overlay_format_round_trips`.

const KINDS := ["Npc", "Sign", "Facility", "ResourceNode", "Trigger"]
const DIRECTIONS := ["Down", "Left", "Right", "Up"]  # index = direction byte 0..3
const PHASES := ["Morning", "Day", "Dusk", "Night"]

var id := ""
var tile := Vector2i.ZERO
var kind := "Npc"
var script_name := ""                  ## "" = none ("script" is a reserved Object member)
var properties: Dictionary = {}        ## String -> String

# NPC render (emitted only for kind == "Npc")
var sprite := -1
var direction := 0
var display_name := ""
var time_of_day: Array[String] = []    ## [] = all phases

# NPC trainer / behavior
var vision_range := -1                 ## -1 = none
var behavior: Dictionary = {}          ## {} = none, else {"kind": ..., params}
var waypoints: Array[Vector2i] = []

# Generic `scripted` interpreter graph (used when script_name == "scripted"). {} = none, else
# { "entry": String, "nodes": Array[Dictionary] }, mirroring pkmn_core::interaction_graph::InteractionGraph.
var graph: Dictionary = {}


## Activation categories, mirroring the map-processor defaults. ResourceNode is a placeholder the
## server re-derives from OBJECT_TYPE at load (assign_resource_script).
func activation() -> Array:
	match kind:
		"Npc":
			return ["FacePress", "Vision"] if vision_range >= 0 else ["FacePress"]
		"Trigger":
			return ["StepOn"]
		_:
			return ["FacePress"]


func to_dict() -> Dictionary:
	var d := { "id": id, "tile_x": tile.x, "tile_y": tile.y, "kind": kind, "activation": activation() }
	if script_name != "":
		d["script"] = script_name
	elif kind == "ResourceNode":
		d["script"] = "default"  # resource nodes run default.lua (the chop/gather loop); picker is hidden
	if not properties.is_empty():
		d["properties"] = properties.duplicate()
	# Generic interpreter graph — emitted for any kind whose script is "scripted".
	if not graph.is_empty():
		d["graph"] = _ints_deep(graph)
	if kind == "Npc":
		d["render"] = {
			"sprite": sprite, "direction": direction,
			"time_of_day": time_of_day.duplicate(), "display_name": display_name,
		}
		if vision_range >= 0:
			d["vision_range"] = vision_range
		if not behavior.is_empty():
			d["behavior"] = _behavior_out()
		if not waypoints.is_empty():
			var wp: Array = []
			for w in waypoints:
				wp.append({ "x": w.x, "y": w.y })
			d["waypoints"] = wp
	return d


## Graph numbers (item_id, qty, badge_id, ms, …) must serialize as ints, not 17.0 — Godot widens JSON
## ints to floats on load and JSON.stringify writes them back as floats, which the server's serde
## (u8/u16/u32 fields) rejects. A graph carries no fractional values, so coercing every whole float to
## an int throughout (nodes → nested action/cond params) is safe. Mirrors `_behavior_out`'s intent.
static func _ints_deep(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			for k in v:
				out[k] = _ints_deep(v[k])
			return out
		TYPE_ARRAY:
			var arr: Array = []
			for e in v:
				arr.append(_ints_deep(e))
			return arr
		TYPE_FLOAT:
			return int(v) if v == floor(v) else v
		_:
			return v


## Behaviour numbers (pause_ms / radius / directions) must serialize as ints — Godot's JSON parser
## widens integers to floats on load, and the server's u8/u32 behaviour fields reject floats.
func _behavior_out() -> Dictionary:
	var out: Dictionary = {}
	for k in behavior:
		var v: Variant = behavior[k]
		if v is float:
			out[k] = int(v)
		elif v is Array:
			var arr: Array = []
			for e in v:
				arr.append(int(e) if e is float else e)
			out[k] = arr
		else:
			out[k] = v
	return out


static func from_dict(d: Dictionary) -> Interactable:
	var it := Interactable.new()
	it.id = str(d.get("id", ""))
	it.tile = Vector2i(int(d.get("tile_x", 0)), int(d.get("tile_y", 0)))
	it.kind = str(d.get("kind", "Npc"))
	it.script_name = str(d.get("script", ""))
	it.properties = (d.get("properties", {}) as Dictionary).duplicate()
	var render: Dictionary = d.get("render", {})
	it.sprite = int(render.get("sprite", -1))
	it.direction = int(render.get("direction", 0))
	it.display_name = str(render.get("display_name", ""))
	for p in render.get("time_of_day", []):
		it.time_of_day.append(str(p))
	it.vision_range = int(d.get("vision_range", -1))
	it.graph = (d.get("graph", {}) as Dictionary).duplicate(true)
	it.behavior = (d.get("behavior", {}) as Dictionary).duplicate()
	for w in d.get("waypoints", []):
		it.waypoints.append(Vector2i(int(w.get("x", 0)), int(w.get("y", 0))))
	return it
