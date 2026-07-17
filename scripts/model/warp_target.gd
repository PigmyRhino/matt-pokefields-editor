class_name WarpTarget
extends RefCounted
## A warp arrival point (where an incoming warp lands). Mirrors pkmn_core::world::WarpTarget.

var name := ""
var tile := Vector2i.ZERO
var target_warp := ""
var direction := 0


func to_dict() -> Dictionary:
	return { "name": name, "tile_x": tile.x, "tile_y": tile.y, "target_warp": target_warp, "direction": direction }


static func from_dict(d: Dictionary) -> WarpTarget:
	var t := WarpTarget.new()
	t.name = str(d.get("name", ""))
	t.tile = Vector2i(int(d.get("tile_x", 0)), int(d.get("tile_y", 0)))
	t.target_warp = str(d.get("target_warp", ""))
	t.direction = int(d.get("direction", 0))
	return t
