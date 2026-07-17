extends Node
## ROM provisioning for the editor. The designer supplies their own ROMs (never shipped); each is
## copied to user://roms/ and read on demand. All three are required, exactly as the game client needs
## them:
##  - FireRed (GBA) — overworld map rendering (GbaMapReader, stitched on demand; freed after stitch).
##  - HGSS (NDS)    — overworld NPC / follower sprite sheets (PokemonRomReader.get_npc_sheet).
##  - B/W (NDS)     — Pokémon box icons + poké-item icons (PokemonRomReader.get_box_icon/get_item_icon).

const ROMS_DIR := "user://roms/"
const FIRERED_PATH := "user://roms/firered.gba"
const HGSS_PATH := "user://roms/hgss.nds"
const BW_PATH := "user://roms/bw.nds"

var _reader: GbaMapReader
var _seed := Vector2i(-1, -1)

## Shared NDS reader: HGSS (overworld sprites) + B/W (icons). Loaded on launch if provisioned.
var pokemon_reader: PokemonRomReader


func _ready() -> void:
	pokemon_reader = PokemonRomReader.new()
	if FileAccess.file_exists(HGSS_PATH):
		pokemon_reader.load_hgss(HGSS_PATH)
	if FileAccess.file_exists(BW_PATH):
		pokemon_reader.load_bw(BW_PATH)


## True only when all three ROMs are present and the NDS pair is loaded (gates both editor modes).
func is_configured() -> bool:
	return FileAccess.file_exists(FIRERED_PATH) and is_hgss_loaded() and is_bw_loaded()


func is_hgss_loaded() -> bool:
	return pokemon_reader != null and pokemon_reader.is_hgss_loaded()


func is_bw_loaded() -> bool:
	return pokemon_reader != null and pokemon_reader.is_bw_loaded()


## Validate a candidate ROM by parsing its header. Returns the game code on success ("" on failure).
## The NDS validators also leave the ROM loaded in pokemon_reader.
func try_load_firered(path: String) -> String:
	return GbaMapReader.new().load_rom(path)


func try_load_hgss(path: String) -> String:
	return pokemon_reader.load_hgss(path)


func try_load_bw(path: String) -> String:
	return pokemon_reader.load_bw(path)


## Copy the three selected ROMs into user://roms/ and load the NDS pair. Returns true on success.
func import_roms(firered_src: String, hgss_src: String, bw_src: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ROMS_DIR)
	if not _copy_into_place(firered_src, FIRERED_PATH, "FireRed"):
		return false
	if not _copy_into_place(hgss_src, HGSS_PATH, "HGSS"):
		return false
	if not _copy_into_place(bw_src, BW_PATH, "B/W"):
		return false
	pokemon_reader.load_hgss(HGSS_PATH)
	pokemon_reader.load_bw(BW_PATH)
	return is_configured()


func _copy_into_place(src: String, dest: String, label: String) -> bool:
	if src == dest:
		return true
	var err := DirAccess.copy_absolute(src, dest)
	if err != OK:
		push_error("RomManager: failed to copy %s ROM: %s" % [label, str(err)])
		return false
	return true


## A GbaMapReader with the given stitched region prepared (cached; re-stitches only on change).
## Returns null on failure.
func get_stitched_reader(group: int, num: int) -> GbaMapReader:
	var seed_map := Vector2i(group, num)
	if _reader == null:
		_reader = GbaMapReader.new()
	if _seed != seed_map:
		if not _reader.is_loaded() and _reader.load_rom(FIRERED_PATH).is_empty():
			push_error("RomManager: failed to load FireRed ROM at %s" % FIRERED_PATH)
			return null
		if not _reader.prepare_stitched(group, num):
			push_error("RomManager: prepare_stitched(%d, %d) failed" % [group, num])
			return null
		_seed = seed_map
	return _reader
