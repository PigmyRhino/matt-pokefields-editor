class_name TileOverride
extends RefCounted
## A painted tile that replaces the ROM's render at `tile` on one layer. `src` is the ROM atlas cell to
## draw; src == (-1, -1) erases the cell to empty. Sparse — only edited tiles are stored. Streamed to
## the client over the wire (it repaints these over its ROM render). Mirrors the future
## pkmn_core::world::TileOverride.

var tile := Vector2i.ZERO
var layer := 0                ## 0 = ground (below player), 1 = above-player overlay
var src := Vector2i(-1, -1)   ## ROM atlas cell; (-1, -1) = erase


func to_dict() -> Dictionary:
	return { "tile_x": tile.x, "tile_y": tile.y, "layer": layer, "src_x": src.x, "src_y": src.y }


static func from_dict(d: Dictionary) -> TileOverride:
	var t := TileOverride.new()
	t.tile = Vector2i(int(d.get("tile_x", 0)), int(d.get("tile_y", 0)))
	t.layer = int(d.get("layer", 0))
	t.src = Vector2i(int(d.get("src_x", -1)), int(d.get("src_y", -1)))
	return t
