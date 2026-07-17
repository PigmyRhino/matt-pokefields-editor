class_name MapEditor
extends Node2D
## Renders a stitched FireRed region, overlays authored interactables, and lets the designer place /
## select / edit / delete them, saving the canonical meta.json the server reads. Render path mirrors
## the client's `map_loader.gd::load_rom_map`.

const MIN_ZOOM := 0.25
const MAX_ZOOM := 8.0
const ZOOM_STEP := 1.1

enum Tool { SELECT, PLACE }
## Top-level editing mode (the "Mode" dropdown). Objects = place NPCs/warps/zones; Tiles = paint art;
## Collision = paint walkability + terrain types. Tiles and Collision are their own paint editors.
enum Mode { OBJECTS, TILES, COLLISION }

## Collision-type brushes for Collision mode: label + the tile_flags bit it sets on left-click. Right-
## click ignores the brush and resets the tile's collision to the ROM original. "Walkable" (flag 0) is
## special — left-click clears the blocking bits. Mirrors the bits in crates/pkmn-core/src/tile_flags.rs;
## add a row here to expose another flag.
const COLLISION_BRUSHES := [
	{ "label": "Walkable (clear block)", "flag": 0 },
	{ "label": "Blocked (wall)", "flag": CollisionOverride.COLLISION },
	{ "label": "Swim (surf)", "flag": CollisionOverride.SWIM },
	{ "label": "Ocean (deep water)", "flag": CollisionOverride.OCEAN },
	{ "label": "Grass", "flag": CollisionOverride.GRASS },
	{ "label": "Tall Grass", "flag": CollisionOverride.TALL_GRASS },
	# Ledges are one-way-passable walls: the direction bit AND COLLISION, so the client (which only
	# ledge-jumps off a blocked tile) and server agree. Matches how the ROM marks ledges.
	{ "label": "Ledge ↓", "flag": CollisionOverride.LEDGE_DOWN | CollisionOverride.COLLISION },
	{ "label": "Ledge ←", "flag": CollisionOverride.LEDGE_LEFT | CollisionOverride.COLLISION },
	{ "label": "Ledge →", "flag": CollisionOverride.LEDGE_RIGHT | CollisionOverride.COLLISION },
	{ "label": "Ledge ↑", "flag": CollisionOverride.LEDGE_UP | CollisionOverride.COLLISION },
	{ "label": "Ice", "flag": CollisionOverride.ICE },
	{ "label": "Stairs L", "flag": CollisionOverride.STAIRS_L },
	{ "label": "Stairs R", "flag": CollisionOverride.STAIRS_R },
	{ "label": "Ladder", "flag": CollisionOverride.LADDER },
	{ "label": "Waterfall ↑", "flag": CollisionOverride.WATERFALL_UP },
	{ "label": "Bridge", "flag": CollisionOverride.BRIDGE },
]

@onready var _tile: int = EditorConfig.TILE_SIZE
@onready var _camera: Camera2D = %Camera
@onready var _ground: TileMapLayer = %RomGround
@onready var _overlay: TileMapLayer = %RomOverlay
@onready var _collision_overlay: CollisionOverlay = %CollisionOverlay
@onready var _grid_overlay: GridOverlay = %GridOverlay
@onready var _object_layer: ObjectLayer = %ObjectLayer
@onready var _coord_label: Label = %CoordLabel
@onready var _region_label: Label = %RegionLabel
@onready var _collision_toggle: CheckButton = %CollisionToggle
@onready var _tool_option: OptionButton = %ToolOption
@onready var _kind_palette: OptionButton = %KindPalette
@onready var _save_btn: Button = %SaveBtn
@onready var _load_btn: Button = %LoadBtn
@onready var _open_folder_btn: Button = %OpenFolderBtn
@onready var _undo_btn: Button = %UndoBtn
@onready var _redo_btn: Button = %RedoBtn
@onready var _inspector: Inspector = %Inspector
@onready var _warp_inspector: WarpInspector = %WarpInspector
@onready var _zone_inspector: ZoneInspector = %ZoneInspector
@onready var _map_inspector: MapInspector = %MapInspector
@onready var _finish_poly_btn: Button = %FinishPolyBtn
@onready var _mode_option: OptionButton = %ModeOption
@onready var _layer_option: OptionButton = %LayerOption
@onready var _flag_option: OptionButton = %FlagOption
@onready var _tool_label: Label = %ToolLabel
@onready var _kind_label: Label = %KindLabel
@onready var _data_panel: MapDataPanel = %MapDataPanel
@onready var _tile_library: TileLibrary = %TileLibrary

var _data_btn: Button
var _reader: GbaMapReader
var _size := Vector2i.ZERO
var _panning := false
var _doc := MapDoc.new()
var _selected: Variant = null
var _waypoint_mode := false
var _mode := Mode.OBJECTS
var _painting := false
var _paint_erase := false
var _box_paint := false             ## mid Ctrl-drag rectangle (copy-region in Tiles, box-fill in Collision)
var _box_erase := false
var _box_start := Vector2i.ZERO
var _source_id := -1                ## tileset source id of the ROM atlas (for painting tile overrides)
var _rom_cells: Dictionary = {}     ## "layer:x:y" -> original ROM atlas coords, for reverting tile edits
var _clipboard: Array = []          ## copied tile region: rows of atlas coords (Vector2i; (-1,-1) = empty)
var _clip_size := Vector2i.ZERO
var _library_ground := Vector2i(-1, -1)  ## library brush for ground layer
var _library_overlay := Vector2i(-1, -1)  ## library brush for overlay layer
## Undo/redo: each entry is a full MapDoc snapshot (to_dict). One snapshot per discrete edit / stroke.
const _MAX_UNDO := 40
var _undo_stack: Array = []
var _redo_stack: Array = []
var _panel: ProblemsPanel
var _trainer_names: Dictionary = {}
var _shop_ids: Dictionary = {}   ## { shop_id: true } from content/shops — scanned once for validation
var _encounter_groups: Dictionary = {}  ## { group: true } from content/encounter_data.json (validation)
var _object_types: Dictionary = {}       ## { type: true } from content/resource_nodes.json (validation)
var _job_board_ids: Dictionary = {}      ## { board_id: true } from content/job_boards (validation)
var _item_ids: Dictionary = {}           ## { int item_id: true } from DB snapshot ∪ content/items.json (validation)
var _place_menu: PopupMenu
var _place_menu_tile: Vector2i
var _tool_mode_label: Label
var _overlays_hidden := false
var _grid_was_enabled := false
var _enc_popup: PopupPanel
var _enc_popup_zone: Zone
var _enc_popup_terrain: OptionButton
var _enc_popup_enc: SearchPicker
var _enc_popup_fish: SearchPicker
var _enc_popup_rod: OptionButton
var _enc_popup_pokemon_box: VBoxContainer
var _enc_popup_loading := false
var _enc_popup_data: Array = []  ## raw encounter_data.json entries
var _enc_popup_collapsed: Dictionary = {}  ## group name -> bool (collapsed state)
var _enc_add_form: PanelContainer
var _enc_popup_list_box: VBoxContainer  ## wrapper hiding list when form is open
var _enc_add_group := ""
var _enc_add_species: SearchPicker
var _enc_add_min_lvl: SpinBox
var _enc_add_max_lvl: SpinBox
var _enc_add_weight: SpinBox
var _enc_add_morning: CheckBox
var _enc_add_day: CheckBox
var _enc_add_night: CheckBox
var _enc_add_pct: Label
var _enc_add_group_row: HBoxContainer
var _enc_add_group_name: LineEdit
var _enc_edit_entry: Dictionary = {}  ## non-empty = editing an existing entry (not adding)
var _enc_add_btn: Button
var _enc_add_hdr_lbl: Label
## The map currently being authored (Kanto overworld or a ROM interior). `_map_id` is the overlay
## filename + server id; `_group`/`_num` seed the ROM stitch.
var _map_id := "kanto"
var _group := 3
var _num := 0
var _map_entry: Dictionary = {}  ## the Catalog.maps entry for _map_id (ROM coords + seed warps)
var _map_option: OptionButton

func _ready() -> void:
	_collision_toggle.toggled.connect(_collision_overlay.set_enabled)
	for t in ["Select", "Place"]:
		_tool_option.add_item(t)
	_tool_option.selected = Tool.SELECT
	_tool_option.item_selected.connect(_on_tool_changed)
	_tool_mode_label = Label.new()
	_tool_mode_label.text = "Mode: Select"
	_tool_mode_label.add_theme_font_size_override("font_size", 13)
	_tool_mode_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.6))
	_tool_option.get_parent().add_child(_tool_mode_label)
	for k in Interactable.KINDS:
		_kind_palette.add_item(k)
	_kind_palette.add_item("Warp")
	_kind_palette.add_item("WarpTarget")
	for c in Zone.CATEGORIES:
		_kind_palette.add_item(c)
	_kind_palette.selected = 0
	_kind_palette.item_selected.connect(func(_i: int) -> void: _select(null))
	for m in ["Objects", "Tiles", "Collision"]:
		_mode_option.add_item(m)
	_mode_option.item_selected.connect(_on_mode_changed)
	for l in ["Both", "Ground", "Overlay"]:
		_layer_option.add_item(l)
	for b in COLLISION_BRUSHES:
		_flag_option.add_item(str(b["label"]))
	_apply_mode_visibility()
	_save_btn.pressed.connect(_on_save)
	_load_btn.pressed.connect(_load_overlay)
	_open_folder_btn.pressed.connect(_on_open_folder)
	_data_btn = Button.new()
	_data_btn.text = "Data"
	_data_btn.tooltip_text = "Toggle data editor panel (edit trainers, shops, encounters, etc. alongside the map)."
	_data_btn.toggle_mode = true
	_data_btn.toggled.connect(_on_data_toggled)
	var bar := _open_folder_btn.get_parent()
	bar.add_child(_data_btn)
	bar.move_child(_data_btn, _open_folder_btn.get_index() + 1)
	_undo_btn.pressed.connect(_undo)
	_redo_btn.pressed.connect(_redo)
	_finish_poly_btn.pressed.connect(func() -> void: _select(null))
	_inspector.changed.connect(_object_layer.refresh)
	_inspector.changed.connect(_revalidate)
	_inspector.deleted.connect(_delete_selected)
	_inspector.waypoint_edit_toggled.connect(_on_waypoint_edit_toggled)
	_warp_inspector.changed.connect(_object_layer.refresh)
	_warp_inspector.changed.connect(_revalidate)
	_warp_inspector.deleted.connect(_delete_selected)
	_warp_inspector.goto_target.connect(_goto_warp_target)
	_zone_inspector.changed.connect(_object_layer.refresh)
	_zone_inspector.changed.connect(_revalidate)
	_zone_inspector.deleted.connect(_delete_selected)
	_tile_library.tile_selected.connect(_on_library_tile_selected)
	_make_draggable(_inspector, "Inspector")
	_make_draggable(_warp_inspector, "Warp Inspector")
	_make_draggable(_zone_inspector, "Zone Inspector")
	_make_draggable(_map_inspector, "Map Info")
	_make_draggable(_data_panel, "Encounters")
	_build_problems_panel()
	_trainer_names = _scan_trainer_names()
	_shop_ids = ContentScan.shop_id_set()
	_encounter_groups = ValCheck.value_set(ContentScan.encounter_groups())
	_object_types = ValCheck.value_set(ContentScan.object_types())
	_job_board_ids = ContentScan.job_board_id_set()
	_item_ids = ValCheck.item_id_set("res://content")
	_build_map_selector()
	_build_place_menu()
	_build_enc_popup()
	_load_enc_popup_data()


## Top-bar dropdown of every authorable map (Kanto overworld + ROM interiors), from the baked map
## index (Catalog.maps). Selecting one renders it and loads/seeds its overlay.
func _build_map_selector() -> void:
	_map_option = OptionButton.new()
	_map_option.tooltip_text = "Map to author — Kanto overworld + every ROM interior."
	var maps := Catalog.maps
	for m in maps:
		_map_option.add_item("%s  (%s)" % [str(m["name"]), str(m["map_id"])])
	var bar := _tool_option.get_parent()
	bar.add_child(_map_option)
	bar.move_child(_map_option, 0)
	_map_option.item_selected.connect(_on_map_selected)
	if maps.is_empty():
		push_error("MapEditor: empty map index — copy maps.json into res://data (run map-baker + regenerate.py)")
		return
	_map_option.selected = 0
	_on_map_selected(0)


func _on_map_selected(idx: int) -> void:
	var maps := Catalog.maps
	if idx < 0 or idx >= maps.size():
		return
	var m: Dictionary = maps[idx]
	_map_entry = m
	_map_id = str(m["map_id"])
	_render_map(int(m["group"]), int(m["num"]))
	_load_overlay()


## "Follow" a warp to where it lands: open its target map (if different) and select the warp-target it
## arrives at, centering the view. One click to trace a door to its destination. An empty/own map_id
## means a same-map warp — the target is looked up on the map already open.
func _goto_warp_target(map_id: String, warp_name: String) -> void:
	if map_id != "" and map_id != _map_id:
		var idx := _map_index(map_id)
		if idx < 0:
			_region_label.text = "%s   ✕ target map '%s' is not in the map index" % [_map_id, map_id]
			return
		_map_option.selected = idx
		_on_map_selected(idx)  # renders the destination + loads/seeds its overlay
	for t in _doc.warp_targets:
		if t.name == warp_name:
			_select(t)
			_camera.position = Vector2(t.tile) * _tile + Vector2(_tile, _tile) * 0.5
			_collision_overlay.notify_camera_changed()
			_grid_overlay.notify_camera_changed()
			return
	_region_label.text = "%s   ✕ no warp-target named '%s' on this map" % [_map_id, warp_name]


## Cross-mode jump target (from the Flag Browser): open `map_id`, then select + center the interactable
## (by id) or zone (by name). Mirrors _goto_warp_target's open-then-select pattern.
func reveal(map_id: String, object_id: String, object_kind: String) -> void:
	if map_id != "" and map_id != _map_id:
		var idx := _map_index(map_id)
		if idx < 0:
			_region_label.text = "✕ map '%s' is not in the map index" % map_id
			return
		_map_option.selected = idx
		_on_map_selected(idx)  # renders the map + loads/seeds its overlay
	if object_kind == "zone":
		for z in _doc.zones:
			if z.name == object_id:
				_select(z)
				if not z.polygon.is_empty():
					_camera.position = Vector2(z.polygon[0]) * _tile + Vector2(_tile, _tile) * 0.5
					_collision_overlay.notify_camera_changed()
					_grid_overlay.notify_camera_changed()
				return
	else:
		for it in _doc.interactables:
			if it.id == object_id:
				_select(it)
				_camera.position = Vector2(it.tile) * _tile + Vector2(_tile, _tile) * 0.5
				_collision_overlay.notify_camera_changed()
				_grid_overlay.notify_camera_changed()
				return
	_region_label.text = "%s   ✕ couldn't find %s '%s'" % [_map_id, object_kind, object_id]


## Index of a map_id in the baked map list (Catalog.maps), or -1 if it isn't there.
func _map_index(map_id: String) -> int:
	for i in Catalog.maps.size():
		if str(Catalog.maps[i]["map_id"]) == map_id:
			return i
	return -1


## Render the ROM map at (group, num) into the tile layers + collision overlay.
func _render_map(group: int, num: int) -> void:
	_group = group
	_num = num
	_reader = RomManager.get_stitched_reader(group, num)
	if _reader == null:
		return

	var atlas: Image = _reader.stitched_atlas_image()
	var grid := _reader.stitched_atlas_grid()
	if atlas == null or grid.x <= 0:
		push_error("MapEditor: ROM atlas unavailable")
		return

	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(_tile, _tile)
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(atlas)
	source.texture_region_size = Vector2i(_tile, _tile)
	# Mirror the client's load_rom_map EXACTLY (animation-aware), so what's painted/copied here renders
	# identically in-game: an animated tile's extra frames (atlas_x+1..) are absorbed into the base tile
	# and must NOT be created as standalone tiles, and the base tile gets the animation. Diverging here
	# (creating every cell static) lets you paint frame-cells the client can't render and shows animated
	# tiles as a static frame.
	var anims := _reader.stitched_animations()  # Vector3i(atlas_x, atlas_y, frame_count)
	var frame_cells := {}
	for a: Vector3i in anims:
		for f in range(1, a.z):
			frame_cells[Vector2i(a.x + f, a.y)] = true
	for r in grid.y:
		for c in grid.x:
			var cell := Vector2i(c, r)
			if not frame_cells.has(cell):
				source.create_tile(cell)
	var fps := _reader.stitched_animation_fps()
	for a: Vector3i in anims:
		var base := Vector2i(a.x, a.y)
		source.set_tile_animation_frames_count(base, a.z)
		source.set_tile_animation_speed(base, fps)
	var source_id := tileset.add_source(source)
	_source_id = source_id
	_rom_cells.clear()  # fresh ROM baseline — tile-edit revert cache no longer applies

	_ground.clear()
	_overlay.clear()
	_ground.tile_set = tileset
	_overlay.tile_set = tileset
	_reader.paint_stitched(_ground, _overlay, source_id)

	_size = _reader.stitched_size()
	_collision_overlay.setup(_reader, _size, _camera)
	_grid_overlay.setup(_size, _camera)
	_tile_library.setup(atlas, grid, source_id)
	_region_label.text = "%s   %d×%d" % [_map_id, _size.x, _size.y]
	_camera.position = Vector2(_size.x, _size.y) * _tile * 0.5
	_collision_overlay.notify_camera_changed()
	_grid_overlay.notify_camera_changed()


## Load this map's authored overlay (or an empty doc for a never-authored map), then seed-heal the ROM
## doors if the overlay carries none (seed-once: the designer starts from the ROM's own warps and owns
## them thereafter).
func _load_overlay() -> void:
	_revert_all_tile_edits()  # Reload path: drop unsaved tile edits back to the ROM before reloading
	_doc = MapDoc.load_from(EditorConfig.output_path(_map_id))
	_seed_rom_warps_if_absent()
	_object_layer.set_doc(_doc)
	_object_layer.set_warp_context(_map_id, Catalog.incoming_sources(_map_id))
	_apply_all_tile_overrides()
	_collision_overlay.set_overrides(_doc.collision_override_map())
	_undo_stack.clear()  # undo history is per-map
	_redo_stack.clear()
	_update_undo_buttons()
	_select(null)
	_revalidate()


## Restore every painted cell to the ROM original recorded in the revert cache (used before a reload).
## A no-op right after _render_map, which clears the cache and repaints a pristine ROM.
func _revert_all_tile_edits() -> void:
	for key in _rom_cells:
		var parts := (key as String).split(":")
		var layer_node: TileMapLayer = _ground if int(parts[0]) == 0 else _overlay
		var t := Vector2i(int(parts[1]), int(parts[2]))
		var orig: Vector2i = _rom_cells[key]
		if orig == Vector2i(-1, -1):
			layer_node.erase_cell(t)
		else:
			layer_node.set_cell(t, _source_id, orig)
	_rom_cells.clear()


## Repaint the saved tile overrides over the freshly-rendered ROM layers (and seed the revert cache so
## an erase can restore the ROM cell underneath).
func _apply_all_tile_overrides() -> void:
	for ov in _doc.tile_overrides:
		var layer_node: TileMapLayer = _ground if ov.layer == 0 else _overlay
		var key := "%d:%d:%d" % [ov.layer, ov.tile.x, ov.tile.y]
		if not _rom_cells.has(key):
			_rom_cells[key] = layer_node.get_cell_atlas_coords(ov.tile)
		if ov.src == Vector2i(-1, -1):
			layer_node.erase_cell(ov.tile)
		else:
			layer_node.set_cell(ov.tile, _source_id, ov.src)


## Seed-once heal: the ROM door warps/targets are a map's structural baseline. A never-authored map (no
## overlay) — or a legacy/empty overlay that predates baked ROM warps (e.g. the original kanto overlay)
## — opens with none, so import them from the baked map index (Catalog.maps → `_map_entry`). A
## populated overlay owns its warps and is left untouched, matching the server's seed-once "overlay
## owns warps" contract (an authored `.meta.json` replaces, not concatenates with, the baked ROM layer).
func _seed_rom_warps_if_absent() -> void:
	if not _doc.warps.is_empty() or not _doc.warp_targets.is_empty():
		return
	for raw in _map_entry.get("warps", []):
		_doc.warps.append(Warp.from_dict(raw))
	for raw in _map_entry.get("warp_targets", []):
		_doc.warp_targets.append(WarpTarget.from_dict(raw))


func _on_save() -> void:
	if Problem.error_count(MapRules.validate(_doc, _trainer_names, _map_id, _tile_blocked, _shop_ids, _encounter_groups, _object_types, _job_board_ids, _item_ids)) > 0:
		_region_label.text = "%s   ✕ fix errors before saving" % _map_id
		return
	if _doc.save_to(EditorConfig.output_path(_map_id)):
		var n := _doc.interactables.size() + _doc.warps.size() + _doc.warp_targets.size()
		_region_label.text = "%s   saved ✓ (%d objects) → %s.meta.json" % [_map_id, n, _map_id]


func _on_open_folder() -> void:
	var dir := ProjectSettings.globalize_path(EditorConfig.OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	OS.shell_open(dir)


# -- undo / redo -------------------------------------------------------------------------------------

## Capture the doc before a discrete edit (place/delete/nudge) or the start of a paint stroke, so it
## undoes as one step. Clears the redo branch. Per-map; reset on map load.
func _snapshot() -> void:
	_undo_stack.append(_doc.to_dict())
	if _undo_stack.size() > _MAX_UNDO:
		_undo_stack.pop_front()
	_redo_stack.clear()
	_update_undo_buttons()


func _undo() -> void:
	if _undo_stack.is_empty():
		return
	_redo_stack.append(_doc.to_dict())
	_restore_doc(_undo_stack.pop_back())


func _redo() -> void:
	if _redo_stack.is_empty():
		return
	_undo_stack.append(_doc.to_dict())
	_restore_doc(_redo_stack.pop_back())


## Replace the live doc with a snapshot and re-render everything (tile edits, collision, objects).
func _restore_doc(snapshot: Dictionary) -> void:
	_revert_all_tile_edits()  # undo the painted cells currently on the layers
	_doc = MapDoc.from_dict(snapshot)
	_apply_all_tile_overrides()
	_collision_overlay.set_overrides(_doc.collision_override_map())
	_object_layer.set_doc(_doc)
	_object_layer.set_warp_context(_map_id, Catalog.incoming_sources(_map_id))
	_select(null)
	_revalidate()
	_update_undo_buttons()


func _update_undo_buttons() -> void:
	_undo_btn.disabled = _undo_stack.is_empty()
	_redo_btn.disabled = _redo_stack.is_empty()


func _select(obj: Variant) -> void:
	_selected = obj
	_object_layer.set_selected(obj)
	_inspector.bind(null)
	_warp_inspector.bind(null)
	_zone_inspector.bind(null)
	_map_inspector.bind(null)
	if obj is Interactable:
		_inspector.bind(obj)
	elif obj is Warp or obj is WarpTarget:
		_warp_inspector.bind(obj, _map_id, _doc.warp_targets)
	elif obj is Zone:
		_zone_inspector.bind(obj)
		# Show encounter quick-edit popup when clicking an Encounter zone.
		if obj.category == "Encounter":
			# Toggle: clicking the same zone closes the popup.
			if _enc_popup != null and _enc_popup.visible and _enc_popup_zone == obj:
				_enc_popup.hide()
				return
			_show_enc_popup(obj, Vector2.ZERO)
			return
	elif obj == null:
		_map_inspector.bind(_doc, _map_id, "%d × %d tiles   ·   ROM %d:%d" % [_size.x, _size.y, _group, _num])
	# Close the encounter popup when clicking anything other than an encounter zone.
	if not (obj is Zone and obj.category == "Encounter") and _enc_popup != null and _enc_popup.visible:
		_enc_popup.hide()


func _delete_selected() -> void:
	if _selected == null:
		return
	_snapshot()
	if _selected is Interactable:
		_doc.interactables.erase(_selected)
	elif _selected is Warp:
		_doc.warps.erase(_selected)
	elif _selected is WarpTarget:
		_doc.warp_targets.erase(_selected)
	elif _selected is Zone:
		_doc.zones.erase(_selected)
	_object_layer.set_doc(_doc)
	_select(null)
	_revalidate()


## Nudge the selected point placeable (interactable / warp / target) one tile with the arrow keys,
## clamped to the map. Hold an arrow to move continuously. Zones are painted, not nudged.
func _nudge_selected(keycode: int) -> void:
	if not (_selected is Interactable or _selected is Warp or _selected is WarpTarget):
		return
	var d := Vector2i.ZERO
	match keycode:
		KEY_LEFT: d = Vector2i(-1, 0)
		KEY_RIGHT: d = Vector2i(1, 0)
		KEY_UP: d = Vector2i(0, -1)
		KEY_DOWN: d = Vector2i(0, 1)
	var t: Vector2i = _selected.tile + d
	t.x = clampi(t.x, 0, maxi(0, _size.x - 1))
	t.y = clampi(t.y, 0, maxi(0, _size.y - 1))
	_selected.tile = t
	_object_layer.set_selected(_selected)  # redraws markers + moves the highlight
	if _selected is Interactable:
		_inspector.bind(_selected)
	else:
		_warp_inspector.bind(_selected, _map_id, _doc.warp_targets)
	_revalidate()


func _on_waypoint_edit_toggled(on: bool) -> void:
	_waypoint_mode = on


func _on_library_tile_selected(atlas_coords: Vector2i, layer: int) -> void:
	if layer == 0:
		_library_ground = atlas_coords
	else:
		_library_overlay = atlas_coords
	if atlas_coords != Vector2i(-1, -1):
		_clipboard = []  # library and clipboard are mutually exclusive


func _on_click(screen_pos: Vector2) -> void:
	var tile := _tile_at(screen_pos)
	if _waypoint_mode and _selected is Interactable:
		_selected.waypoints.append(tile)
		_object_layer.refresh()
		_inspector.update_waypoint_count()
		_revalidate()
		return
	var stack: Array = _object_layer.placeables_at(tile)
	if not stack.is_empty():
		var chosen: Variant = _next_in_stack(stack)  # repeated clicks cycle stacked objects (warp ↔ target)
		_select(chosen)
		if stack.size() > 1:
			_region_label.text = "%s   %d objects on (%d, %d) — click again to cycle (%d/%d)" % [
				_map_id, stack.size(), tile.x, tile.y, stack.find(chosen) + 1, stack.size()]
		return
	if _tool_option.selected == Tool.PLACE:
		_place_new(tile)
		return
	# SELECT mode, no point object here: cycle through any overlapping zones (topmost first) on repeated
	# clicks, so an Encounter zone sitting under an Area polygon is still reachable.
	var zones: Array = _object_layer.zones_at(tile)
	var chosen_zone: Variant = _next_in_stack(zones) if not zones.is_empty() else null
	_select(chosen_zone)
	if zones.size() > 1:
		_region_label.text = "%s   %d zones on (%d, %d) — click again to cycle (%d/%d)" % [
			_map_id, zones.size(), tile.x, tile.y, zones.find(chosen_zone) + 1, zones.size()]


## When placeables share a tile, repeated clicks step through them (wrapping), so a warp-target sitting
## under a warp is reachable. Returns the one after the current selection, or the topmost on a fresh tile.
func _next_in_stack(stack: Array) -> Variant:
	var idx := stack.find(_selected)
	return stack[(idx + 1) % stack.size()] if idx != -1 else stack[0]


func _place_new(tile: Vector2i) -> void:
	_snapshot()
	var idx := maxi(0, _kind_palette.selected)
	if idx < Interactable.KINDS.size():
		var it := Interactable.new()
		it.kind = Interactable.KINDS[idx]
		it.tile = tile
		it.id = "%s_%d_%d" % [it.kind.to_lower(), tile.x, tile.y]
		_doc.interactables.append(it)
		_object_layer.set_doc(_doc)
		_select(it)
	elif idx == Interactable.KINDS.size():
		var w := Warp.new()
		w.tile = tile
		w.name = "warp_%d_%d" % [tile.x, tile.y]
		w.target_map = _map_id  # default to a same-map warp; change Target Map for cross-map
		_doc.warps.append(w)
		_object_layer.set_doc(_doc)
		_select(w)
	else:
		var t := WarpTarget.new()
		t.tile = tile
		t.name = "t_%d_%d" % [tile.x, tile.y]
		_doc.warp_targets.append(t)
		_object_layer.set_doc(_doc)
		_select(t)
	_revalidate()


## Kind palette layout (Objects mode): [interactable kinds…][Warp][WarpTarget][zone categories…].
func _zone_base() -> int:
	return Interactable.KINDS.size() + 2


func _on_tool_changed(_index: int) -> void:
	_update_tool_label()


func _update_tool_label() -> void:
	if _tool_mode_label == null:
		return
	var names := ["Select", "Place"]
	_tool_mode_label.text = "Mode: %s" % names[_tool_option.selected]


func _palette_is_zone() -> bool:
	return _kind_palette.selected >= _zone_base()


func _zone_paint_mode() -> bool:
	return _mode == Mode.OBJECTS and _tool_option.selected == Tool.PLACE and _palette_is_zone()


func _make_popup_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.95)
	style.border_color = Color(0.35, 0.35, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	return style


func _build_enc_popup() -> void:
	_enc_popup = PopupPanel.new()
	_enc_popup.title = "Encounter Zone"
	_enc_popup.add_theme_stylebox_override("panel", _make_popup_style())
	_enc_popup.set_flag(Window.FLAG_NO_FOCUS, true)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.add_theme_constant_override("margin", 8)
	# Terrain row
	var terrain_hb := HBoxContainer.new()
	var terrain_lbl := Label.new()
	terrain_lbl.text = "Terrain"
	terrain_lbl.custom_minimum_size.x = 70
	terrain_hb.add_child(terrain_lbl)
	_enc_popup_terrain = OptionButton.new()
	for t in Zone.ENCOUNTER_TERRAINS:
		_enc_popup_terrain.add_item(t)
	_enc_popup_terrain.item_selected.connect(_on_enc_popup_terrain)
	terrain_hb.add_child(_enc_popup_terrain)
	vb.add_child(terrain_hb)
	# Encounter group row
	var enc_hb := HBoxContainer.new()
	var enc_lbl := Label.new()
	enc_lbl.text = "Encounter"
	enc_lbl.custom_minimum_size.x = 70
	enc_hb.add_child(enc_lbl)
	_enc_popup_enc = SearchPicker.new()
	_enc_popup_enc.custom_minimum_size = Vector2(160, 0)
	_enc_popup_enc.set_entries(ContentScan.encounter_groups())
	_enc_popup_enc.value_changed.connect(_on_enc_popup_enc)
	enc_hb.add_child(_enc_popup_enc)
	vb.add_child(enc_hb)
	# Fish group row
	var fish_hb := HBoxContainer.new()
	var fish_lbl := Label.new()
	fish_lbl.text = "Fish"
	fish_lbl.custom_minimum_size.x = 70
	fish_hb.add_child(fish_lbl)
	_enc_popup_fish = SearchPicker.new()
	_enc_popup_fish.custom_minimum_size = Vector2(160, 0)
	_enc_popup_fish.set_entries(ContentScan.encounter_groups())
	_enc_popup_fish.value_changed.connect(_on_enc_popup_fish)
	fish_hb.add_child(_enc_popup_fish)
	vb.add_child(fish_hb)
	# Rod tier row
	var rod_hb := HBoxContainer.new()
	var rod_lbl := Label.new()
	rod_lbl.text = "Min Rod"
	rod_lbl.custom_minimum_size.x = 70
	rod_hb.add_child(rod_lbl)
	_enc_popup_rod = OptionButton.new()
	for rod_name: String in ContentScan.fishing_rods():
		_enc_popup_rod.add_item(rod_name)
	_enc_popup_rod.item_selected.connect(_on_enc_popup_rod)
	rod_hb.add_child(_enc_popup_rod)
	vb.add_child(rod_hb)
	# Pokemon list (wrapped so we can hide it when the add/edit form is open).
	_enc_popup_list_box = VBoxContainer.new()
	_enc_popup_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var list_sep := HSeparator.new()
	_enc_popup_list_box.add_child(list_sep)
	_enc_popup_pokemon_box = VBoxContainer.new()
	_enc_popup_pokemon_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enc_popup_pokemon_box.add_theme_constant_override("separation", 2)
	_enc_popup_list_box.add_child(_enc_popup_pokemon_box)
	vb.add_child(_enc_popup_list_box)
	# Add/Edit pokemon form (hidden by default, shown inline).
	_enc_add_form = PanelContainer.new()
	_enc_add_form.add_theme_stylebox_override("panel", _make_popup_style())
	_enc_add_form.visible = false
	var form_vb := VBoxContainer.new()
	form_vb.add_theme_constant_override("separation", 4)
	form_vb.add_theme_constant_override("margin", 8)
	# Header row with title + close button
	var hdr := HBoxContainer.new()
	var hdr_lbl := Label.new()
	hdr_lbl.text = "Add Pokemon"
	hdr_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(hdr_lbl)
	_enc_add_hdr_lbl = hdr_lbl
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(24, 24)
	close_btn.pressed.connect(func() -> void: _close_enc_add_form())
	hdr.add_child(close_btn)
	form_vb.add_child(hdr)
	# Group name row (hidden when group already exists).
	_enc_add_group_row = HBoxContainer.new()
	var grp_lbl := Label.new()
	grp_lbl.text = "Group"
	grp_lbl.custom_minimum_size.x = 70
	_enc_add_group_row.add_child(grp_lbl)
	_enc_add_group_name = LineEdit.new()
	_enc_add_group_name.custom_minimum_size = Vector2(160, 0)
	_enc_add_group_name.placeholder_text = "encounter_group_id"
	_enc_add_group_row.add_child(_enc_add_group_name)
	form_vb.add_child(_enc_add_group_row)
	# Species row
	var species_hb := HBoxContainer.new()
	var species_lbl := Label.new()
	species_lbl.text = "Species"
	species_lbl.custom_minimum_size.x = 70
	species_hb.add_child(species_lbl)
	_enc_add_species = SearchPicker.new()
	_enc_add_species.custom_minimum_size = Vector2(160, 0)
	_enc_add_species.set_entries(Catalog.species_slugs)
	species_hb.add_child(_enc_add_species)
	form_vb.add_child(species_hb)
	# Min Level row
	var min_hb := HBoxContainer.new()
	var min_lbl := Label.new()
	min_lbl.text = "Min Lv"
	min_lbl.custom_minimum_size.x = 70
	min_hb.add_child(min_lbl)
	_enc_add_min_lvl = SpinBox.new()
	_enc_add_min_lvl.min_value = 1
	_enc_add_min_lvl.max_value = 100
	_enc_add_min_lvl.value = 5
	min_hb.add_child(_enc_add_min_lvl)
	form_vb.add_child(min_hb)
	# Max Level row
	var max_hb := HBoxContainer.new()
	var max_lbl := Label.new()
	max_lbl.text = "Max Lv"
	max_lbl.custom_minimum_size.x = 70
	max_hb.add_child(max_lbl)
	_enc_add_max_lvl = SpinBox.new()
	_enc_add_max_lvl.min_value = 1
	_enc_add_max_lvl.max_value = 100
	_enc_add_max_lvl.value = 10
	max_hb.add_child(_enc_add_max_lvl)
	form_vb.add_child(max_hb)
	# Weight row
	var wt_hb := HBoxContainer.new()
	var wt_lbl := Label.new()
	wt_lbl.text = "Weight"
	wt_lbl.custom_minimum_size.x = 70
	wt_hb.add_child(wt_lbl)
	_enc_add_weight = SpinBox.new()
	_enc_add_weight.min_value = 1
	_enc_add_weight.max_value = 1000
	_enc_add_weight.value = 10
	wt_hb.add_child(_enc_add_weight)
	form_vb.add_child(wt_hb)
	# Percentage preview.
	_enc_add_pct = Label.new()
	_enc_add_pct.add_theme_font_size_override("font_size", 12)
	_enc_add_pct.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	form_vb.add_child(_enc_add_pct)
	_enc_add_weight.value_changed.connect(func(_v: float) -> void: _update_enc_add_pct())
	# Time of day row
	var tod_hb := HBoxContainer.new()
	var tod_lbl := Label.new()
	tod_lbl.text = "Time"
	tod_lbl.custom_minimum_size.x = 70
	tod_hb.add_child(tod_lbl)
	_enc_add_morning = CheckBox.new()
	_enc_add_morning.text = "Morning"
	_enc_add_morning.button_pressed = true
	_enc_add_morning.toggled.connect(func(_b: bool) -> void: _update_enc_add_pct())
	tod_hb.add_child(_enc_add_morning)
	_enc_add_day = CheckBox.new()
	_enc_add_day.text = "Day"
	_enc_add_day.button_pressed = true
	_enc_add_day.toggled.connect(func(_b: bool) -> void: _update_enc_add_pct())
	tod_hb.add_child(_enc_add_day)
	_enc_add_night = CheckBox.new()
	_enc_add_night.text = "Night"
	_enc_add_night.button_pressed = true
	_enc_add_night.toggled.connect(func(_b: bool) -> void: _update_enc_add_pct())
	tod_hb.add_child(_enc_add_night)
	form_vb.add_child(tod_hb)
	# Add/Update button
	var add_btn := Button.new()
	add_btn.text = "Add"
	add_btn.pressed.connect(_on_enc_add_confirm)
	form_vb.add_child(add_btn)
	_enc_add_btn = add_btn
	_enc_add_form.add_child(form_vb)
	vb.add_child(_enc_add_form)
	_enc_popup.add_child(vb)
	add_child(_enc_popup)


func _show_enc_popup(zone: Zone, screen_pos: Vector2) -> void:
	_enc_popup_zone = zone
	_enc_popup_loading = true
	_enc_popup_terrain.selected = maxi(0, Zone.ENCOUNTER_TERRAINS.find(zone.terrain))
	_enc_popup_enc.set_value(zone.encounter_group)
	_enc_popup_fish.set_value(zone.fish_encounter_group)
	_enc_popup_rod.selected = zone.fish_rod_tier
	_rebuild_enc_popup_list()
	_enc_popup_loading = false
	if _enc_popup != null and _enc_popup.visible:
		return
	_enc_popup.position = Vector2i(8, 80)
	_enc_popup.popup()


func _load_enc_popup_data() -> void:
	var loaded: Variant = JsonIO.load_file("res://content/encounter_data.json")
	if typeof(loaded) == TYPE_DICTIONARY and loaded.has("entries"):
		_enc_popup_data = loaded["entries"]


func _show_enc_add_popup(group: String) -> void:
	_enc_edit_entry = {}
	_enc_add_btn.text = "Add"
	_enc_add_hdr_lbl.text = "Add Pokemon"
	_enc_add_group = group
	_enc_add_species.set_value("")
	_enc_add_min_lvl.value = 5
	_enc_add_max_lvl.value = 10
	_enc_add_weight.value = 10
	_enc_add_morning.button_pressed = true
	_enc_add_day.button_pressed = true
	_enc_add_night.button_pressed = true
	# Show group name field only when no group is assigned yet.
	if group == "":
		_enc_add_group_row.visible = true
		_enc_add_group_name.text = "%s_%s" % [_map_id, _enc_popup_zone.name]
		_enc_add_group_name.editable = true
	else:
		_enc_add_group_row.visible = false
	_update_enc_add_pct()
	_enc_popup_list_box.visible = false
	_enc_add_form.visible = true


func _show_enc_edit_popup(group: String, entry: Dictionary) -> void:
	_enc_edit_entry = entry
	_enc_add_btn.text = "Update"
	_enc_add_hdr_lbl.text = "Edit Pokemon"
	_enc_add_group = group
	_enc_add_species.set_value(str(entry.get("pokemon", "")))
	_enc_add_min_lvl.value = int(entry.get("min_level", 1))
	_enc_add_max_lvl.value = int(entry.get("max_level", 1))
	_enc_add_weight.value = int(entry.get("slots", 10))
	_enc_add_morning.button_pressed = bool(entry.get("morning_allowed", true))
	_enc_add_day.button_pressed = bool(entry.get("day_allowed", true))
	_enc_add_night.button_pressed = bool(entry.get("night_allowed", true))
	_enc_add_group_row.visible = false
	_update_enc_add_pct()
	_enc_popup_list_box.visible = false
	_enc_add_form.visible = true


func _close_enc_add_form() -> void:
	_enc_add_form.visible = false
	_enc_popup_list_box.visible = true
	_enc_edit_entry = {}
	_rebuild_enc_popup_list()


func _update_enc_add_pct() -> void:
	var w: int = int(_enc_add_weight.value)
	# Compute per-phase totals from existing group entries.
	var totals := { "morning": 0, "day": 0, "night": 0 }
	for e in _enc_popup_data:
		if str(e.get("encounter", "")) != _enc_add_group:
			continue
		var ew: int = int(e.get("slots", 0))
		if bool(e.get("morning_allowed", true)):
			totals["morning"] += ew
		if bool(e.get("day_allowed", true)):
			totals["day"] += ew
		if bool(e.get("night_allowed", true)):
			totals["night"] += ew
	var parts: Array = []
	if _enc_add_morning.button_pressed:
		var total: int = int(totals["morning"]) + w
		parts.append("M %d%%" % (roundi(100.0 * w / total) if total > 0 else 0))
	if _enc_add_day.button_pressed:
		var total: int = int(totals["day"]) + w
		parts.append("D %d%%" % (roundi(100.0 * w / total) if total > 0 else 0))
	if _enc_add_night.button_pressed:
		var total: int = int(totals["night"]) + w
		parts.append("N %d%%" % (roundi(100.0 * w / total) if total > 0 else 0))
	_enc_add_pct.text = "  ".join(parts) if not parts.is_empty() else "—"


func _on_enc_add_confirm() -> void:
	var species: String = _enc_add_species.get_value()
	if species.strip_edges() == "":
		return
	# Auto-generate encounter group name if none assigned yet.
	if _enc_add_group == "":
		var custom_name := _enc_add_group_name.text.strip_edges()
		_enc_add_group = custom_name if custom_name != "" else "%s_%s" % [_map_id, _enc_popup_zone.name]
		_enc_popup_zone.encounter_group = _enc_add_group
		_object_layer.refresh()
		_revalidate()
	if not _enc_edit_entry.is_empty():
		# UPDATE existing entry.
		_enc_edit_entry["pokemon"] = species
		_enc_edit_entry["min_level"] = int(_enc_add_min_lvl.value)
		_enc_edit_entry["max_level"] = int(_enc_add_max_lvl.value)
		_enc_edit_entry["slots"] = int(_enc_add_weight.value)
		_enc_edit_entry["morning_allowed"] = _enc_add_morning.button_pressed
		_enc_edit_entry["day_allowed"] = _enc_add_day.button_pressed
		_enc_edit_entry["night_allowed"] = _enc_add_night.button_pressed
		_save_enc_data()
		_close_enc_add_form()
	else:
		# ADD new entry (reject duplicates in same group).
		for e in _enc_popup_data:
			if str(e.get("pokemon", "")) == species and str(e.get("encounter", "")) == _enc_add_group:
				return
		var entry := {
			"encounter": _enc_add_group,
			"pokemon": species,
			"min_level": int(_enc_add_min_lvl.value),
			"max_level": int(_enc_add_max_lvl.value),
			"slots": int(_enc_add_weight.value),
			"held_item_groups": "",
			"morning_allowed": _enc_add_morning.button_pressed,
			"day_allowed": _enc_add_day.button_pressed,
			"night_allowed": _enc_add_night.button_pressed,
		}
		_enc_popup_data.append(entry)
		_save_enc_data()
		_close_enc_add_form()


func _save_enc_data() -> void:
	var raw: Variant = JsonIO.load_file("res://content/encounter_data.json")
	if typeof(raw) == TYPE_DICTIONARY:
		if not raw.has("entries"):
			raw["entries"] = []
		raw["entries"] = _enc_popup_data
		JsonIO.save_file("res://content/encounter_data.json", raw)


func _rebuild_enc_popup_list() -> void:
	for c in _enc_popup_pokemon_box.get_children():
		c.queue_free()
	if _enc_popup_zone == null:
		return
	var groups: Array[String] = []
	if _enc_popup_zone.encounter_group != "":
		groups.append(_enc_popup_zone.encounter_group)
	if _enc_popup_zone.fish_encounter_group != "":
		groups.append(_enc_popup_zone.fish_encounter_group)
	# No groups assigned yet — show a single "Add Pokemon" to bootstrap one.
	if groups.is_empty():
		var add_btn := Button.new()
		add_btn.text = "+ Add Pokemon"
		add_btn.add_theme_font_size_override("font_size", 12)
		add_btn.pressed.connect(func() -> void: _show_enc_add_popup(""))
		_enc_popup_pokemon_box.add_child(add_btn)
		return
	for grp in groups:
		var collapsed: bool = _enc_popup_collapsed.get(grp, false)
		# Collect this group's entries.
		var group_entries: Array = []
		for e in _enc_popup_data:
			if str(e.get("encounter", "")) == grp:
				group_entries.append(e)
		# Per-phase total weights.
		var totals := { "morning": 0, "day": 0, "night": 0 }
		for e in group_entries:
			var w: int = int(e.get("slots", 0))
			if bool(e.get("morning_allowed", true)):
				totals["morning"] += w
			if bool(e.get("day_allowed", true)):
				totals["day"] += w
			if bool(e.get("night_allowed", true)):
				totals["night"] += w
		# Header label (clickable).
		var header := Button.new()
		header.flat = true
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.text = "%s  %s  (Σ %d)" % ["▸" if collapsed else "▾", grp,
			totals["morning"] + totals["day"] + totals["night"]]
		header.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
		header.add_theme_color_override("font_hover_color", Color(0.8, 0.9, 1.0))
		header.add_theme_color_override("font_pressed_color", Color(0.6, 0.8, 1.0))
		var entries_box := VBoxContainer.new()
		entries_box.add_theme_constant_override("separation", 1)
		var g := grp
		header.pressed.connect(func() -> void:
			_enc_popup_collapsed[g] = not _enc_popup_collapsed.get(g, false)
			_rebuild_enc_popup_list())
		_enc_popup_pokemon_box.add_child(header)
		if not collapsed:
			# Add Pokemon button.
			var add_btn := Button.new()
			add_btn.text = "+ Add Pokemon"
			add_btn.add_theme_font_size_override("font_size", 12)
			var grp_capture := g
			add_btn.pressed.connect(func() -> void: _show_enc_add_popup(grp_capture))
			entries_box.add_child(add_btn)
			# Pokemon entries.
			for e in group_entries:
				var pokemon: String = str(e.get("pokemon", ""))
				var min_lvl: int = int(e.get("min_level", 1))
				var max_lvl: int = int(e.get("max_level", 1))
				var wt: int = int(e.get("slots", 0))
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 4)
				row.mouse_filter = Control.MOUSE_FILTER_STOP
				# Icon.
				var icon_tex := GameData.get_pokemon_icon(GameData.species_id_for_slug(pokemon))
				if icon_tex != null:
					var icon_rect := TextureRect.new()
					icon_rect.texture = icon_tex
					icon_rect.custom_minimum_size = Vector2(24, 24)
					icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
					icon_rect.mouse_filter = Control.MOUSE_FILTER_PASS
					row.add_child(icon_rect)
				# Label.
				var lbl := Label.new()
				lbl.text = "%s  Lv%d-%d  (wt %d)" % [pokemon, min_lvl, max_lvl, wt]
				lbl.add_theme_font_size_override("font_size", 13)
				lbl.mouse_filter = Control.MOUSE_FILTER_PASS
				row.add_child(lbl)
				# Per-phase percentages.
				var pct_parts: Array = []
				for ph in [["morning", "M"], ["day", "D"], ["night", "N"]]:
					if bool(e.get(ph[0] + "_allowed", true)) and totals[ph[0]] > 0:
						pct_parts.append("%s %d%%" % [ph[1], roundi(100.0 * wt / totals[ph[0]])])
				if not pct_parts.is_empty():
					var pct_lbl := Label.new()
					pct_lbl.text = "  ".join(pct_parts)
					pct_lbl.add_theme_font_size_override("font_size", 11)
					pct_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
					pct_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
					row.add_child(pct_lbl)
				# Click to edit, right-click to delete.
				var entry_ref: Dictionary = e
				var grp_ref: String = g
				var poke_name: String = pokemon
				row.gui_input.connect(func(event: InputEvent) -> void:
					if event is InputEventMouseButton and event.pressed:
						if event.button_index == MOUSE_BUTTON_LEFT:
							_show_enc_edit_popup(grp_ref, entry_ref)
						elif event.button_index == MOUSE_BUTTON_RIGHT:
							_confirm_delete_enc_entry(grp_ref, entry_ref, poke_name))
				row.tooltip_text = "Left-click to edit · Right-click to delete"
				entries_box.add_child(row)
			_enc_popup_pokemon_box.add_child(entries_box)


func _on_enc_popup_terrain(index: int) -> void:
	if _enc_popup_loading or _enc_popup_zone == null:
		return
	_enc_popup_zone.terrain = Zone.ENCOUNTER_TERRAINS[index]
	_object_layer.refresh()
	_revalidate()


func _confirm_delete_enc_entry(grp: String, entry: Dictionary, poke_name: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Delete Pokemon"
	dialog.dialog_text = "Remove %s from %s?" % [poke_name, grp]
	dialog.confirmed.connect(func() -> void:
		_delete_enc_entry(grp, entry))
	_enc_popup.add_child(dialog)
	dialog.popup_centered(Vector2i(260, 80))
	dialog.tree_exited.connect(func() -> void: dialog.queue_free())


func _delete_enc_entry(grp: String, entry: Dictionary) -> void:
	# Remove from in-memory data.
	_enc_popup_data.erase(entry)
	# Persist to file.
	_save_enc_data()
	# If the group is now empty, clear it from the zone.
	var has_entries := false
	for e in _enc_popup_data:
		if str(e.get("encounter", "")) == grp:
			has_entries = true
			break
	if not has_entries:
		if _enc_popup_zone.encounter_group == grp:
			_enc_popup_zone.encounter_group = ""
		elif _enc_popup_zone.fish_encounter_group == grp:
			_enc_popup_zone.fish_encounter_group = ""
		_object_layer.refresh()
		_revalidate()
	_rebuild_enc_popup_list()


func _on_enc_popup_enc(v: String) -> void:
	if _enc_popup_loading or _enc_popup_zone == null:
		return
	_enc_popup_zone.encounter_group = v
	_rebuild_enc_popup_list()
	_object_layer.refresh()
	_revalidate()


func _on_enc_popup_fish(v: String) -> void:
	if _enc_popup_loading or _enc_popup_zone == null:
		return
	_enc_popup_zone.fish_encounter_group = v
	_rebuild_enc_popup_list()
	_object_layer.refresh()
	_revalidate()


func _on_enc_popup_rod(index: int) -> void:
	if _enc_popup_loading or _enc_popup_zone == null:
		return
	_enc_popup_zone.fish_rod_tier = index




func _build_place_menu() -> void:
	_place_menu = PopupMenu.new()
	_place_menu.id_pressed.connect(_on_place_menu_item_selected)
	_inspector.get_parent().add_child(_place_menu)


func _show_place_menu(screen_pos: Vector2) -> void:
	_place_menu.clear()
	_place_menu_tile = _tile_at(screen_pos)
	var idx := 0
	for k in Interactable.KINDS:
		_place_menu.add_item(k, idx)
		idx += 1
	_place_menu.add_separator()
	_place_menu.add_item("Warp", idx)
	idx += 1
	_place_menu.add_item("WarpTarget", idx)
	idx += 1
	_place_menu.add_separator()
	for c in Zone.CATEGORIES:
		_place_menu.add_item(c, idx)
		idx += 1
	_place_menu.position = Vector2i(screen_pos)
	_place_menu.popup()


func _on_place_menu_item_selected(id: int) -> void:
	_snapshot()
	var tile := _place_menu_tile
	if id < Interactable.KINDS.size():
		var it := Interactable.new()
		it.kind = Interactable.KINDS[id]
		it.tile = tile
		it.id = "%s_%d_%d" % [it.kind.to_lower(), tile.x, tile.y]
		_doc.interactables.append(it)
		_object_layer.set_doc(_doc)
		_select(it)
		_kind_palette.selected = id
	elif id == Interactable.KINDS.size():
		var w := Warp.new()
		w.tile = tile
		w.name = "warp_%d_%d" % [tile.x, tile.y]
		w.target_map = _map_id
		_doc.warps.append(w)
		_object_layer.set_doc(_doc)
		_select(w)
		_kind_palette.selected = id
	elif id == Interactable.KINDS.size() + 1:
		var t := WarpTarget.new()
		t.tile = tile
		t.name = "t_%d_%d" % [tile.x, tile.y]
		_doc.warp_targets.append(t)
		_object_layer.set_doc(_doc)
		_select(t)
		_kind_palette.selected = id
	else:
		var zone_idx := id - Interactable.KINDS.size() - 2
		if zone_idx >= 0 and zone_idx < Zone.CATEGORIES.size():
			var z := Zone.new()
			z.category = Zone.CATEGORIES[zone_idx]
			z.name = "%s_%d" % [z.category.to_lower(), _doc.zones.size()]
			z.paint(tile)
			_doc.zones.append(z)
			_object_layer.set_doc(_doc)
			_select(z)
			_kind_palette.selected = _zone_base() + zone_idx
			_kind_palette.set_item_disabled(_zone_base() + zone_idx, false)
			_tool_option.selected = Tool.PLACE
			_update_tool_label()
	_revalidate()


## Switch top-level editing mode: toggle which toolbar controls show, auto-reveal the collision overlay
## for Collision mode, and clear any selection / copied tiles.
func _on_mode_changed(m: int) -> void:
	_mode = m
	_apply_mode_visibility()
	_tool_option.selected = Tool.SELECT
	_update_tool_label()
	_clipboard = []
	_library_ground = Vector2i(-1, -1)
	_library_overlay = Vector2i(-1, -1)
	_tile_library.clear_all()
	_object_layer.set_paint_box(Rect2i())  # drop any stamp/box preview
	if _mode == Mode.COLLISION:
		_collision_toggle.button_pressed = true
	else:
		_collision_toggle.button_pressed = false
	_select(null)


func _apply_mode_visibility() -> void:
	var objects := _mode == Mode.OBJECTS
	_tool_label.visible = objects
	_tool_option.visible = objects
	_kind_label.visible = objects
	_kind_palette.visible = objects
	_finish_poly_btn.visible = objects
	_tile_library.visible = _mode == Mode.TILES
	_layer_option.visible = _mode == Mode.TILES
	_flag_option.visible = _mode == Mode.COLLISION


func _on_data_toggled(on: bool) -> void:
	_data_panel.visible = on
	if on:
		_inspector.visible = false
		_warp_inspector.visible = false
		_zone_inspector.visible = false
		_map_inspector.visible = false
	else:
		_select(_selected)


## Zone painting targets the selected zone, or (when adding tiles) a fresh zone of the palette category.
func _active_paint_zone() -> Zone:
	if _selected is Zone:
		return _selected as Zone
	if _paint_erase:
		return null
	var z := Zone.new()
	z.category = Zone.CATEGORIES[_kind_palette.selected - (Interactable.KINDS.size() + 2)]
	z.name = "%s_%d" % [z.category.to_lower(), _doc.zones.size()]
	_doc.zones.append(z)
	_object_layer.set_doc(_doc)
	_select(z)
	return z


## Drag-paint dispatch (motion while a button is held): Objects mode paints a zone, Tiles/Collision
## modes paint the grid.
func _paint_at(screen_pos: Vector2) -> void:
	if _mode == Mode.OBJECTS:
		_paint_zone_at(screen_pos)
	else:
		_paint_grid_at(screen_pos)


func _paint_zone_at(screen_pos: Vector2) -> void:
	var z := _active_paint_zone()
	if z == null:
		return
	var tile := _tile_at(screen_pos)
	if _paint_erase:
		z.erase(tile)
		if z.tile_count() == 0:  # erased the whole zone away
			_doc.zones.erase(z)
			_object_layer.set_doc(_doc)
			_select(null)
			_revalidate()
			return
	else:
		z.paint(tile)
	if z.rebuild_warning != "":
		_region_label.text = z.rebuild_warning
	_zone_inspector.update_verts()
	_object_layer.refresh()
	_revalidate()


# -- tile / collision painting (overrides over the ROM) ----------------------------------------------

func _paint_grid_at(screen_pos: Vector2) -> void:
	var tile := _tile_at(screen_pos)
	if tile.x < 0 or tile.y < 0 or tile.x >= _size.x or tile.y >= _size.y:
		return
	if _mode == Mode.COLLISION:
		_paint_collision(tile, _paint_erase)
		_collision_overlay.set_overrides(_doc.collision_override_map())
	elif _paint_erase:
		_erase_tile(tile)
	elif _library_ground != Vector2i(-1, -1) or _library_overlay != Vector2i(-1, -1):
		_paint_library_tile(tile)
	else:
		_stamp(tile)


## Paint the library-selected tiles at `tile`. Ground tile goes to layer 0, overlay to layer 1.
## Each layer paints independently — only if a tile was picked for that layer.
func _paint_library_tile(tile: Vector2i) -> void:
	if _library_ground != Vector2i(-1, -1):
		_set_tile_override(tile, 0, _library_ground)
	if _library_overlay != Vector2i(-1, -1):
		_set_tile_override(tile, 1, _library_overlay)


## Apply the selected collision brush at `tile`. Left-click (erase=false) sets the flag bit, building on
## the tile's current flags so types stack (e.g. grass + ledge); "Walkable" (flag 0) instead clears the
## blocking + ledge bits. Right-click (erase=true) resets the tile's collision to the ROM original —
## drops the whole override, whatever brush is selected — so the overlay tint falls back to ROM.
func _paint_collision(tile: Vector2i, erase: bool) -> void:
	var rom_flags := _reader.stitched_tile_flags(tile.x, tile.y) if _reader != null else 0
	if erase:  # full reset: revert this tile's collision to the ROM baseline (equal flags drops the override)
		_doc.set_collision_override(tile, rom_flags, rom_flags)
		return
	var ov := _doc.collision_override_at(tile)
	var base: int = ov.flags if ov != null else rom_flags
	var flag := int(COLLISION_BRUSHES[_flag_option.selected]["flag"])
	var want: int
	if flag == 0:  # "Walkable" — clear blocking AND ledge bits (a walkable tile is neither)
		want = base & ~(CollisionOverride.BLOCKED | CollisionOverride.LEDGES)
	else:
		want = base | flag
	_doc.set_collision_override(tile, want, rom_flags)


## Copy both layers' tiles in `rect` into the clipboard (captured on a Ctrl-drag), so a stamp reproduces
## ground + overlay exactly. Each cell stores [ground_coord, overlay_coord].
func _copy_region(rect: Rect2i) -> void:
	_clip_size = rect.size
	_clipboard = []
	_library_ground = Vector2i(-1, -1)
	_library_overlay = Vector2i(-1, -1)
	_tile_library.clear_all()
	for y in rect.size.y:
		var row: Array = []
		for x in rect.size.x:
			var cell := rect.position + Vector2i(x, y)
			row.append([_ground.get_cell_atlas_coords(cell), _overlay.get_cell_atlas_coords(cell)])
		_clipboard.append(row)
	_region_label.text = "%s   copied %d × %d tiles — move to place, left-click to stamp" % [_map_id, rect.size.x, rect.size.y]


## Stamp the copied region (both layers) with its top-left at `anchor`. Empty cells erase to empty.
func _stamp(anchor: Vector2i) -> void:
	if _clipboard.is_empty():
		_region_label.text = "%s   Ctrl+drag to copy tiles first" % _map_id
		return
	for dy in _clip_size.y:
		var row: Array = _clipboard[dy]
		for dx in _clip_size.x:
			var t := anchor + Vector2i(dx, dy)
			if t.x >= 0 and t.y >= 0 and t.x < _size.x and t.y < _size.y:
				var pair: Array = row[dx]
				if _layer_affects(0):
					_set_tile_override(t, 0, pair[0] as Vector2i)  # ground
				if _layer_affects(1):
					_set_tile_override(t, 1, pair[1] as Vector2i)  # overlay


## Paint atlas cell `src` at (tile, layer): update the doc + the rendered layer, capturing the ROM cell
## on first touch so an erase can restore it. src == (-1, -1) erases the cell to empty.
func _set_tile_override(tile: Vector2i, layer_idx: int, src: Vector2i) -> void:
	var layer_node: TileMapLayer = _ground if layer_idx == 0 else _overlay
	var key := "%d:%d:%d" % [layer_idx, tile.x, tile.y]
	if not _rom_cells.has(key):
		_rom_cells[key] = layer_node.get_cell_atlas_coords(tile)
	_doc.set_tile_override(tile, layer_idx, src)
	if src == Vector2i(-1, -1):
		layer_node.erase_cell(tile)
	else:
		layer_node.set_cell(tile, _source_id, src)


## Revert tile edits at `tile` (the layers the Layer target selects) back to the ROM cells underneath.
func _erase_tile(tile: Vector2i) -> void:
	if _layer_affects(0):
		_revert_tile(tile, 0)
	if _layer_affects(1):
		_revert_tile(tile, 1)


## Whether the Layer target (Both / Ground / Overlay) writes to layer 0 (ground) or 1 (overlay).
func _layer_affects(layer_idx: int) -> bool:
	return _layer_option.selected == 0 or _layer_option.selected == layer_idx + 1


func _revert_tile(tile: Vector2i, layer_idx: int) -> void:
	if _doc.tile_override_at(tile, layer_idx) == null:
		return
	var layer_node: TileMapLayer = _ground if layer_idx == 0 else _overlay
	var key := "%d:%d:%d" % [layer_idx, tile.x, tile.y]
	_doc.erase_tile_override(tile, layer_idx)
	if _rom_cells.has(key):
		var orig: Vector2i = _rom_cells[key]
		if orig == Vector2i(-1, -1):
			layer_node.erase_cell(tile)
		else:
			layer_node.set_cell(tile, _source_id, orig)
		_rom_cells.erase(key)


## Inclusive tile-space rectangle between two corners, clamped to the map.
func _tile_rect(a: Vector2i, b: Vector2i) -> Rect2i:
	var x0 := clampi(mini(a.x, b.x), 0, _size.x - 1)
	var y0 := clampi(mini(a.y, b.y), 0, _size.y - 1)
	var x1 := clampi(maxi(a.x, b.x), 0, _size.x - 1)
	var y1 := clampi(maxi(a.y, b.y), 0, _size.y - 1)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


func _update_box_preview(screen_pos: Vector2) -> void:
	_object_layer.set_paint_box(_tile_rect(_box_start, _tile_at(screen_pos)))


## Finish a Ctrl-drag rectangle: in Tiles mode copy the region to the clipboard; in Collision mode fill
## the rectangle with the brush (right-drag resets it to the ROM original).
func _commit_box(screen_pos: Vector2) -> void:
	var r := _tile_rect(_box_start, _tile_at(screen_pos))
	_box_paint = false
	_object_layer.set_paint_box(Rect2i())
	if _mode == Mode.TILES:
		_copy_region(r)
		return
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			_paint_collision(Vector2i(x, y), _box_erase)
	_collision_overlay.set_overrides(_doc.collision_override_map())
	_region_label.text = "%s   set %d × %d tiles" % [_map_id, r.size.x, r.size.y]
	_revalidate()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			var is_right := mb.button_index == MOUSE_BUTTON_RIGHT
			if _box_paint and not mb.pressed:
				_commit_box(mb.position)  # finish the Ctrl rectangle on release
			elif _mode == Mode.OBJECTS:
				if _zone_paint_mode():
					_painting = mb.pressed
					_paint_erase = is_right
					if mb.pressed:
						_snapshot()
						_paint_at(mb.position)
				elif mb.pressed:
					if is_right:
						_show_place_menu(mb.position)
					else:
						_on_click(mb.position)
			elif mb.pressed and mb.ctrl_pressed:
				if _mode == Mode.COLLISION:
					_snapshot()   # collision box-fill mutates; the Tiles copy doesn't
				_box_paint = true   # Tiles: copy a region; Collision: box-fill the brush
				_box_erase = is_right
				_box_start = _tile_at(mb.position)
				_update_box_preview(mb.position)
			else:
				_painting = mb.pressed   # Tiles: stamp/erase; Collision: set the flag / reset to ROM
				_paint_erase = is_right
				if mb.pressed:
					_snapshot()
					_paint_grid_at(mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			_camera.position -= mm.relative / _camera.zoom
			_collision_overlay.notify_camera_changed()
			_grid_overlay.notify_camera_changed()
		elif _box_paint:
			_update_box_preview(mm.position)
		elif _painting:
			_paint_at(mm.position)
		elif _mode == Mode.TILES:
			if _library_ground != Vector2i(-1, -1) or _library_overlay != Vector2i(-1, -1):
				_object_layer.set_paint_box(Rect2i(_tile_at(mm.position), Vector2i.ONE))
			elif not _clipboard.is_empty():
				_object_layer.set_paint_box(Rect2i(_tile_at(mm.position), _clip_size))  # stamp placement preview
		_update_coord_label(mm.position)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed:
			return
		if k.ctrl_pressed and k.keycode == KEY_Z:
			if k.shift_pressed:
				_redo()
			else:
				_undo()
			return
		if k.ctrl_pressed and k.keycode == KEY_Y:
			_redo()
			return
		match k.keycode:
			KEY_T:
				_mode_option.selected = Mode.TILES
				_on_mode_changed(_mode_option.selected)
			KEY_1:
				_mode_option.selected = Mode.OBJECTS
				_on_mode_changed(_mode_option.selected)
				_tool_option.selected = Tool.SELECT
				_update_tool_label()
			KEY_2:
				_mode_option.selected = Mode.OBJECTS
				_on_mode_changed(_mode_option.selected)
				_tool_option.selected = Tool.PLACE
				_update_tool_label()
			KEY_3:
				_mode_option.selected = Mode.COLLISION
				_on_mode_changed(_mode_option.selected)
			KEY_F5:
				_grid_overlay.toggle()
			KEY_H:
				_overlays_hidden = not _overlays_hidden
				_object_layer.set_overlays_hidden(_overlays_hidden)
				if _overlays_hidden:
					_grid_was_enabled = _grid_overlay._enabled
					_collision_overlay.set_enabled(false)
					_grid_overlay.set_enabled(false)
				else:
					_collision_overlay.set_enabled(_collision_toggle.button_pressed)
					_grid_overlay.set_enabled(_grid_was_enabled)
			KEY_DELETE: _delete_selected()
			KEY_ESCAPE:
				_painting = false
				_mode_option.selected = Mode.OBJECTS
				_on_mode_changed(_mode_option.selected)
				_tool_option.selected = Tool.SELECT
				_update_tool_label()
				_select(null)
			KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
				if not k.echo:
					_snapshot()
				_nudge_selected(k.keycode)


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := _screen_to_world(screen_pos)
	var z := clampf(_camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	_camera.zoom = Vector2(z, z)
	var after := _screen_to_world(screen_pos)
	_camera.position += before - after
	_collision_overlay.notify_camera_changed()
	_grid_overlay.notify_camera_changed()


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return _camera.position + (screen_pos - get_viewport_rect().size * 0.5) / _camera.zoom


func _tile_at(screen_pos: Vector2) -> Vector2i:
	var w := _screen_to_world(screen_pos)
	return Vector2i(int(floor(w.x / _tile)), int(floor(w.y / _tile)))


func _update_coord_label(screen_pos: Vector2) -> void:
	var t := _tile_at(screen_pos)
	_coord_label.text = "(%d, %d)" % [t.x, t.y]


# -- validation --------------------------------------------------------------------------------------

func _build_problems_panel() -> void:
	_panel = ProblemsPanel.new()
	var ui := _inspector.get_parent()  # the UI CanvasLayer
	ui.add_child(_panel)
	_panel.anchor_left = 0.0
	_panel.anchor_top = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 8.0
	_panel.offset_right = -310.0  # clear of the right-hand inspectors
	_panel.offset_top = 0.0       # auto-height: grows up from the bottom by its content
	_panel.offset_bottom = -44.0  # clear of the Map/Data switcher
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.problem_activated.connect(_on_problem_activated)
	_panel.collapsed_changed.connect(_on_problems_collapsed)
	_on_problems_collapsed(true)  # the panel starts minimized — match its width anchor


## Collapsed, the panel hugs its header width (anchored to the left); expanded, it spans the wide
## bottom strip up to the right-hand inspectors.
func _on_problems_collapsed(collapsed: bool) -> void:
	if collapsed:
		_panel.anchor_right = 0.0
		_panel.offset_right = 0.0
		_panel.grow_horizontal = Control.GROW_DIRECTION_END
	else:
		_panel.anchor_right = 1.0
		_panel.offset_right = -310.0
		_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH


## Re-run map validation; drive the panel, the Save gate, and the per-object rings on the overlay.
func _revalidate() -> void:
	if _panel == null:
		return
	var problems := MapRules.validate(_doc, _trainer_names, _map_id, _tile_blocked, _shop_ids, _encounter_groups, _object_types, _job_board_ids, _item_ids)
	_panel.set_problems(problems)
	_save_btn.disabled = Problem.error_count(problems) > 0
	var probmap: Dictionary = {}
	for p in problems:
		if typeof((p as Problem).locator) != TYPE_OBJECT:
			continue
		var obj: Variant = (p as Problem).locator
		if (p as Problem).severity == Problem.Severity.ERROR:
			probmap[obj] = true
		elif not probmap.has(obj):
			probmap[obj] = false
	_object_layer.set_problem_objects(probmap)


func _on_problem_activated(p: Problem) -> void:
	if typeof(p.locator) != TYPE_OBJECT:
		return
	_select(p.locator)
	if p.locator is Interactable or p.locator is Warp or p.locator is WarpTarget:
		_camera.position = Vector2(p.locator.tile) * _tile + Vector2(_tile, _tile) * 0.5
		_collision_overlay.notify_camera_changed()
		_grid_overlay.notify_camera_changed()


func _tile_blocked(t: Vector2i) -> bool:
	return _reader != null and (_reader.stitched_tile_flags(t.x, t.y) & 0x07) != 0


func _scan_trainer_names() -> Dictionary:
	var out: Dictionary = {}
	_scan_trainers_dir("res://content/trainers", out)
	return out


func _scan_trainers_dir(dir: String, out: Dictionary) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var full := dir + "/" + n
		if d.current_is_dir():
			if not n.begins_with("."):
				_scan_trainers_dir(full, out)
		elif n.ends_with(".json"):
			var t: Variant = JsonIO.load_file(full)
			if typeof(t) == TYPE_DICTIONARY and t.has("unique_name"):
				out[str(t["unique_name"])] = true
		n = d.get_next()
	d.list_dir_end()


func _make_draggable(panel: PanelContainer, title: String) -> void:
	# Title bar and resize grip are separate floating Controls in the CanvasLayer,
	# NOT children of the panel (which would break its Container layout).
	var bar := PanelContainer.new()
	var lbl := Label.new()
	lbl.text = "  " + title
	lbl.add_theme_font_size_override("font_size", 13)
	bar.add_child(lbl)
	panel.get_parent().add_child(bar)
	# Resize grip: small Control at the bottom-right
	var grip := Control.new()
	grip.custom_minimum_size = Vector2(16, 16)
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.get_parent().add_child(grip)
	grip.draw.connect(func() -> void:
		for i in range(4):
			var x := grip.size.x - 2.0 - i * 3.0
			var y := grip.size.y - 2.0 - i * 3.0
			grip.draw_line(Vector2(x, grip.size.y), Vector2(grip.size.x, y), Color(0.5, 0.5, 0.5, 0.6), 1.0)
	)
	# --- Position helpers ---
	var _layout: Callable = func() -> void:
		bar.offset_left = panel.offset_left
		bar.offset_top = panel.offset_top - 24
		bar.offset_right = panel.offset_right
		bar.offset_bottom = panel.offset_top
		grip.offset_left = panel.offset_right - 16
		grip.offset_top = panel.offset_bottom - 16
		grip.offset_right = panel.offset_right
		grip.offset_bottom = panel.offset_bottom
	_layout.call()
	panel.resized.connect(_layout)
	panel.visibility_changed.connect(func() -> void:
		bar.visible = panel.visible
		grip.visible = panel.visible
	)
	# --- Drag (title bar) ---
	var dragging := false
	var drag_offset := Vector2.ZERO
	bar.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				dragging = mb.pressed
				if dragging:
					drag_offset = mb.position
		elif event is InputEventMouseMotion and dragging:
			var mm := event as InputEventMouseMotion
			panel.offset_left += mm.position.x - drag_offset.x
			panel.offset_top += mm.position.y - drag_offset.y
			panel.offset_right += mm.position.x - drag_offset.x
			panel.offset_bottom += mm.position.y - drag_offset.y
			_layout.call()
	)
	# --- Resize (grip) ---
	var resizing := false
	var resize_start := Vector2.ZERO
	var resize_orig := Vector4.ZERO
	grip.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				resizing = mb.pressed
				if resizing:
					resize_start = mb.global_position
					resize_orig = Vector4(panel.offset_left, panel.offset_top, panel.offset_right, panel.offset_bottom)
		elif event is InputEventMouseMotion and resizing:
			var mm := event as InputEventMouseMotion
			var delta := mm.global_position - resize_start
			panel.offset_right = maxf(resize_orig.z + delta.x, panel.offset_left + panel.custom_minimum_size.x)
			panel.offset_bottom = maxf(resize_orig.w + delta.y, panel.offset_top + 40)
			_layout.call()
	)
