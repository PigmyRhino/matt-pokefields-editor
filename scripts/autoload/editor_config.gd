extends Node
## Editor-wide constants and the designer output location. The editor reads its ROM from user://roms
## and its dropdown vocab from res://data, and writes authored overlays into the project itself at
## res://output (i.e. tools/game-editor/output/) so they're version-controlled and committed straight
## back to the repo — the maintainer copies each <map_id>.meta.json into the server's map-data/<map_id>/
## directory. (res:// is writable when the tool is run from the Godot editor / a debug build, which is
## how designers use it; an exported build would make res:// read-only.)

const TILE_SIZE := 16
const OUTPUT_DIR := "res://output/"


## Output file for a map's authored overlay (what the designer sends back: <map_id>.meta.json).
## `map_id` is the baked map slug — "kanto" for the overworld, a name-based slug for interiors (see Catalog.maps).
func output_path(map_id: String) -> String:
	return OUTPUT_DIR.path_join("%s.meta.json" % map_id)
