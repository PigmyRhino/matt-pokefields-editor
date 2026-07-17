class_name CollisionOverride
extends RefCounted
## Replaces the ROM collision at `tile`. `flags` is the full pkmn_core::tile_flags u32 to use instead
## (bit 0 COLLISION = blocked; 0 = walkable). Sparse — only edited tiles are stored. The server merges
## these into its authoritative collision grid; the client merges them into its movement prediction.
## Mirrors the future pkmn_core::world::CollisionOverride.

# Tile flag bits — mirror crates/pkmn-core/src/tile_flags.rs (and the client's tile_flags.gd).
const COLLISION := 1 << 0
const SWIM := 1 << 1
const OCEAN := 1 << 2
const GRASS := 1 << 3
const TALL_GRASS := 1 << 4
const ICE := 1 << 5
const MUD := 1 << 6
const DEEP_SNOW := 1 << 7
const ROCKY := 1 << 8
const JUMP := 1 << 9
const LEDGE_DOWN := 1 << 10
const LEDGE_LEFT := 1 << 11
const LEDGE_RIGHT := 1 << 12
const LEDGE_UP := 1 << 13
const STAIRS_L := 1 << 14
const STAIRS_R := 1 << 15
const CLIMB := 1 << 16
const LADDER := 1 << 19
const WATERFALL_UP := 1 << 21
const BRIDGE := 1 << 25
const BLOCKED := COLLISION | SWIM | OCEAN  ## any "you can't walk here" bit
const WATER := SWIM | OCEAN
const LEDGES := LEDGE_DOWN | LEDGE_LEFT | LEDGE_RIGHT | LEDGE_UP

var tile := Vector2i.ZERO
var flags := 0


func to_dict() -> Dictionary:
	return { "tile_x": tile.x, "tile_y": tile.y, "flags": flags }


static func from_dict(d: Dictionary) -> CollisionOverride:
	var c := CollisionOverride.new()
	c.tile = Vector2i(int(d.get("tile_x", 0)), int(d.get("tile_y", 0)))
	c.flags = int(d.get("flags", 0))
	return c
