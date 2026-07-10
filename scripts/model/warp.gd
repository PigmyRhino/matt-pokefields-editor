class_name Warp
extends RefCounted
## A warp source tile (steps the player to a target). Mirrors pkmn_core::world::Warp.

var name := ""
var tile := Vector2i.ZERO
var target_map := ""
var target_warp := ""
var warp_type := ""  ## optional; reserved for future door/transition animations
var door_type := ""  ## optional; reserved for future door/transition animations


func to_dict() -> Dictionary:
	return {
		"name": name, "tile_x": tile.x, "tile_y": tile.y,
		"target_map": target_map, "target_warp": target_warp,
		"warp_type": warp_type, "door_type": door_type,
	}


static func from_dict(d: Dictionary) -> Warp:
	var w := Warp.new()
	w.name = str(d.get("name", ""))
	w.tile = Vector2i(int(d.get("tile_x", 0)), int(d.get("tile_y", 0)))
	w.target_map = str(d.get("target_map", ""))
	w.target_warp = str(d.get("target_warp", ""))
	w.warp_type = str(d.get("warp_type", ""))
	w.door_type = str(d.get("door_type", ""))
	return w
