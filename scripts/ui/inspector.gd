class_name Inspector
extends PanelContainer
## Edits the selected interactable. Per-kind field groups show/hide by kind; every edit writes back
## to the bound model and emits `changed` so markers refresh. Covers all InteractableDef fields:
## id/kind/script/object-type/properties, and for NPCs sprite/direction/name, time-of-day
## visibility, trainer vision, behaviour + params, and patrol waypoints (placed on the map).

signal changed
signal deleted
signal waypoint_edit_toggled(enabled: bool)

const BEHAVIORS := ["Stationary", "Look Around", "Wander", "Patrol"]
const PATROL_MODES := ["Loop", "Ping-Pong"]
const SPRITE_SOURCES := ["Character", "Pokémon"]

@onready var _id: LineEdit = %IdEdit
@onready var _kind: OptionButton = %KindOption
@onready var _tile_label: Label = %TileLabel
@onready var _script_row: Control = %ScriptRow
@onready var _script: SearchPicker = %ScriptOption
@onready var _objtype_row: Control = %ObjectTypeRow
@onready var _objtype: SearchPicker = %ObjectTypeOption
@onready var _encounter_row: Control = %EncounterRow
@onready var _encounter: SearchPicker = %EncounterEdit
@onready var _shop_link_row: Control = %ShopLinkRow
@onready var _shop_link: SearchPicker = %ShopLinkOption
@onready var _job_board_link_row: Control = %JobBoardLinkRow
@onready var _job_board_link: SearchPicker = %JobBoardLinkOption
@onready var _npc_box: Control = %NpcBox
@onready var _sprite: SearchPicker = %SpriteSpin
@onready var _sprite_source: OptionButton = %SpriteSourceOption
@onready var _sprite_row: Control = %SpriteRow
@onready var _pokemon_row: Control = %PokemonRow
@onready var _pokemon: SearchPicker = %PokemonSpin
@onready var _direction: OptionButton = %DirectionOption
@onready var _display_name: LineEdit = %DisplayNameEdit
@onready var _trainer_link_row: Control = %TrainerLinkRow
@onready var _trainer_link: SearchPicker = %TrainerLinkOption
@onready var _tod: Array[CheckBox] = [%TodMorning, %TodDay, %TodDusk, %TodNight]
@onready var _trainer: CheckBox = %TrainerCheck
@onready var _vision: SpinBox = %VisionSpin
@onready var _behavior: OptionButton = %BehaviorOption
@onready var _look_params: Control = %LookParams
@onready var _look_pause: SpinBox = %LookPauseSpin
@onready var _look_dirs: Array[CheckBox] = [%LookDown, %LookLeft, %LookRight, %LookUp]
@onready var _wander_params: Control = %WanderParams
@onready var _wander_radius: SpinBox = %WanderRadiusSpin
@onready var _wander_pause: SpinBox = %WanderPauseSpin
@onready var _patrol_params: Control = %PatrolParams
@onready var _patrol_mode: OptionButton = %PatrolModeOption
@onready var _patrol_pause: SpinBox = %PatrolPauseSpin
@onready var _waypoint_edit: CheckButton = %WaypointEditToggle
@onready var _waypoint_clear: Button = %WaypointClearBtn
@onready var _waypoint_count: Label = %WaypointCountLabel
@onready var _delete: Button = %DeleteBtn

var _it: Interactable = null
var _loading := false

@onready var _fields: VBoxContainer = $Margin/Scroll/Fields
## Sign / plain-NPC dialogue, authored inline on the object (saved as properties["dialogue"] in
## meta.json) — no global table, no id to match. Trainer battle lines live in the trainer file and
## are edited on the Trainers card, not here.
var _dlg_header: Label
var _npc_dlg: TextEdit
## Generic `scripted` interaction — a node graph (say / give_item / conditions / choices) authored in
## the full-screen GraphCanvas, saved as `graph` in meta.json and run by scripted.lua. Here it's a
## header + a button that opens the canvas for the selected object.
var _scripted_header: Label
var _graph_btn: Button
var _graph_canvas: GraphCanvas


func _ready() -> void:
	for k in Interactable.KINDS:
		_kind.add_item(k)
	for d in Interactable.DIRECTIONS:
		_direction.add_item(d)
	for b in BEHAVIORS:
		_behavior.add_item(b)
	for m in PATROL_MODES:
		_patrol_mode.add_item(m)
	for s in SPRITE_SOURCES:
		_sprite_source.add_item(s)

	_script.set_entries(Catalog.scripts)
	# Resource OBJECT_TYPE + encounter group read LIVE from content/ (the Data cards), not the bundled
	# Catalog snapshot, so newly-authored groups/types show up here.
	_objtype.set_entries(ContentScan.object_types())
	_encounter.set_entries(ContentScan.encounter_groups())
	_sprite.set_entries(Catalog.sprites)
	# Show the actual NPC overworld sprite (down-facing idle) beside each sprite-id option.
	_sprite.icon_provider = func(v: String) -> Texture2D:
		return GameData.get_npc_icon(int(v)) if v.is_valid_int() else null
	# Alternate NPC visual: a Pokémon overworld sprite. The picker offers a species; the model stores
	# its follower-sheet index (GameData.npc_sprite_for_species), which renders through the same
	# overworld-sheet path as a character sprite. Rows are shown one at a time by the Sprite-type toggle.
	_pokemon.set_entries(GameData.overworld_species_entries())
	# Preview the actual overworld sprite the NPC will show (its down-facing idle frame), not the box
	# icon — so the dropdown matches the map marker and the in-game entity.
	_pokemon.icon_provider = func(v: String) -> Texture2D:
		return GameData.get_npc_icon(GameData.npc_sprite_for_species(int(v))) if v.is_valid_int() else null
	# Trainer NPCs link to a configured trainer by id == unique_name; pick from the trainer list.
	_trainer_link.set_entries(ContentScan.trainers())
	_trainer_link.value_changed.connect(_on_trainer_link_selected)
	# poke_mart objects link to a configured shop by shop_id; pick from the Data shop list (no id matching).
	_shop_link.set_entries(ContentScan.shops())
	_shop_link.value_changed.connect(_on_shop_link_selected)
	# job_board Facilities link to an authored board by job_board_id; pick from the Data job-board list.
	_job_board_link.set_entries(ContentScan.job_boards())
	_job_board_link.value_changed.connect(_on_job_board_link_selected)

	_id.text_changed.connect(_on_id_changed)
	_kind.item_selected.connect(_on_kind_selected)
	_script.value_changed.connect(_on_script_selected)
	_objtype.value_changed.connect(_on_objtype_selected)
	_encounter.value_changed.connect(_on_encounter_changed)
	_sprite.value_changed.connect(_on_sprite_changed)
	_sprite_source.item_selected.connect(_on_sprite_source_selected)
	_pokemon.value_changed.connect(_on_pokemon_changed)
	_direction.item_selected.connect(_on_direction_selected)
	_display_name.text_changed.connect(_on_display_name_changed)
	for cb in _tod:
		cb.toggled.connect(_on_tod_changed)
	_trainer.toggled.connect(_write_vision)
	_vision.value_changed.connect(_write_vision)
	_behavior.item_selected.connect(_write_behavior)
	_look_pause.value_changed.connect(_write_behavior)
	for cb in _look_dirs:
		cb.toggled.connect(_write_behavior)
	_wander_radius.value_changed.connect(_write_behavior)
	_wander_pause.value_changed.connect(_write_behavior)
	_patrol_mode.item_selected.connect(_write_behavior)
	_patrol_pause.value_changed.connect(_write_behavior)
	_waypoint_edit.toggled.connect(func(on: bool) -> void: waypoint_edit_toggled.emit(on))
	_waypoint_clear.pressed.connect(_on_waypoint_clear)
	_delete.pressed.connect(func() -> void: deleted.emit())

	_build_dialogue_ui()
	_build_scripted_ui()
	visible = false


## A dialogue box for signs / plain NPCs, inserted just above Delete.
func _build_dialogue_ui() -> void:
	_dlg_header = Label.new()
	_dlg_header.text = "— dialogue —"
	_fields.add_child(_dlg_header)
	_npc_dlg = TextEdit.new()
	_npc_dlg.custom_minimum_size = Vector2(0, 90)
	_npc_dlg.placeholder_text = "What this sign/NPC says (blank = silent). Enter for line breaks."
	_npc_dlg.text_changed.connect(_on_npc_dlg_changed)
	_fields.add_child(_npc_dlg)
	for n in [_dlg_header, _npc_dlg]:
		_fields.move_child(n, _delete.get_index())


## The `scripted` graph affordance — a header + "open the visual editor" button, inserted just above
## Delete (mirrors the dialogue box). The GraphCanvas is a CanvasLayer added once and opened on demand.
func _build_scripted_ui() -> void:
	_scripted_header = Label.new()
	_scripted_header.text = "— scripted interaction —"
	_fields.add_child(_scripted_header)
	_graph_btn = Button.new()
	_graph_btn.pressed.connect(func() -> void:
		if _it != null:
			_graph_canvas.open(_it))
	_fields.add_child(_graph_btn)
	for n in [_scripted_header, _graph_btn]:
		_fields.move_child(n, _delete.get_index())
	_graph_canvas = GraphCanvas.new()
	_graph_canvas.changed.connect(_on_graph_changed)
	_graph_canvas.closed.connect(_refresh_graph_btn)
	add_child(_graph_canvas)


func bind(it: Interactable) -> void:
	_it = it
	visible = it != null
	if it == null:
		return
	_loading = true
	_id.text = it.id
	_kind.selected = Interactable.KINDS.find(it.kind)
	_tile_label.text = "tile (%d, %d)" % [it.tile.x, it.tile.y]
	_script.set_value(it.script_name)
	_objtype.set_value(str(it.properties.get("OBJECT_TYPE", "")))
	_encounter.set_value(str(it.properties.get("ENCOUNTER_GROUP", "")))
	_shop_link.set_value(str(it.properties.get("shop_id", "")))
	_job_board_link.set_value(str(it.properties.get("job_board_id", "")))
	_load_sprite_source(it)
	_direction.selected = it.direction
	_display_name.text = it.display_name
	_trainer_link.set_value(it.id)
	_load_time_of_day(it)
	_load_vision(it)
	_load_behavior(it)
	_waypoint_edit.button_pressed = false
	update_waypoint_count()
	_load_dialogue()
	_refresh_graph_btn()
	_refresh_visibility()
	_loading = false


func update_waypoint_count() -> void:
	if _it != null:
		_waypoint_count.text = "%d waypoints" % _it.waypoints.size()


func _refresh_visibility() -> void:
	if _it == null:
		return
	# Triggers are scriptable too (a step-on cutscene / gift), so they get the script picker as well.
	_script_row.visible = _it.kind in ["Npc", "Sign", "Facility", "Trigger"]
	_objtype_row.visible = _it.kind == "ResourceNode"
	_encounter_row.visible = _it.kind == "ResourceNode"
	# Shop link shows for any poke_mart object (a Facility counter or an NPC clerk) — it owns the shop_id.
	_shop_link_row.visible = _it.script_name == "poke_mart"
	# Job-board link shows for any job_board object — it owns the job_board_id the board panel opens on.
	_job_board_link_row.visible = _it.script_name == "job_board"
	# The graph editor button shows only for the generic `scripted` interpreter.
	var scripted := _it.script_name == "scripted"
	_scripted_header.visible = scripted
	_graph_btn.visible = scripted
	_npc_box.visible = _it.kind == "Npc"
	_trainer_link_row.visible = _it.kind == "Npc" and _it.script_name == "trainer"
	_look_params.visible = _behavior.selected == 1
	_wander_params.visible = _behavior.selected == 2
	_patrol_params.visible = _behavior.selected == 3
	# Dialogue box shows for signs and plain NPCs (those that talk via simple_dialogue). A trainer or
	# other-scripted NPC speaks via its own script (trainer.lua reads the trainer file), so no line here.
	_npc_dlg.visible = _uses_npc_dialogue()
	_dlg_header.visible = _uses_npc_dialogue()


# -- common field handlers --

func _guarded() -> bool:
	return _loading or _it == null


func _on_id_changed(text: String) -> void:
	if _guarded(): return
	_it.id = text
	changed.emit()


func _on_kind_selected(index: int) -> void:
	if _guarded(): return
	_it.kind = Interactable.KINDS[index]
	_refresh_visibility()
	changed.emit()


func _on_script_selected(value: String) -> void:
	if _guarded(): return
	_it.script_name = value
	# A scripted NPC (trainer, pc, …) speaks via its script, so an inline `dialogue` property would be
	# dead data — drop it when the script no longer renders it.
	if not _uses_npc_dialogue() and _it.properties.has("dialogue"):
		_it.properties.erase("dialogue")
		_loading = true
		_npc_dlg.text = ""
		_loading = false
	# shop_id only means anything to the poke_mart script — drop it (and clear the picker) otherwise.
	if value != "poke_mart" and _it.properties.has("shop_id"):
		_it.properties.erase("shop_id")
		_shop_link.set_value("")
	# job_board_id only means anything to the job_board script — drop it (and clear the picker) otherwise.
	if value != "job_board" and _it.properties.has("job_board_id"):
		_it.properties.erase("job_board_id")
		_job_board_link.set_value("")
	# The interaction graph only means anything to the scripted interpreter — drop it otherwise.
	if value != "scripted" and not _it.graph.is_empty():
		_it.graph.clear()
		_refresh_graph_btn()
	_refresh_visibility()  # the trainer-link / shop-link / scripted pickers show only for their script
	changed.emit()


# -- dialogue (inline on the interactable, stored in properties["dialogue"]) --

## True when the selected object talks via simple_dialogue (a sign, or an NPC with no/explicit
## simple_dialogue script). Trainers and other scripted NPCs speak via their script, not this line.
func _uses_npc_dialogue() -> bool:
	return _it != null and (_it.kind == "Sign" or (_it.kind == "Npc" and _it.script_name in ["", "simple_dialogue"]))


## Fill the dialogue box from the object. Self-guards so its text-set doesn't write back.
func _load_dialogue() -> void:
	if _it == null:
		return
	var was := _loading
	_loading = true
	_npc_dlg.text = str(_it.properties.get("dialogue", ""))
	_loading = was


func _on_npc_dlg_changed() -> void:
	if _guarded(): return
	var text := _npc_dlg.text
	if text.strip_edges() == "":
		_it.properties.erase("dialogue")
	else:
		_it.properties["dialogue"] = text
		# A talking object needs the simple_dialogue script to render it; set it once, automatically.
		if _it.script_name == "":
			_it.script_name = "simple_dialogue"
			_script.set_value("simple_dialogue")
	changed.emit()


# -- NPC: trainer link (id == trainer unique_name) --

func _on_trainer_link_selected(value: String) -> void:
	if _guarded(): return
	if value == "":
		return
	_it.id = value
	_id.text = value  # the link IS the id; keep the id field in sync
	changed.emit()


# -- NPC / Facility: shop link (poke_mart → properties["shop_id"]) --

func _on_shop_link_selected(value: String) -> void:
	if _guarded(): return
	if value == "":
		_it.properties.erase("shop_id")
	else:
		_it.properties["shop_id"] = value
	changed.emit()


# -- Facility: job-board link (job_board → properties["job_board_id"]) --

func _on_job_board_link_selected(value: String) -> void:
	if _guarded(): return
	if value == "":
		_it.properties.erase("job_board_id")
	else:
		_it.properties["job_board_id"] = value
	changed.emit()


# -- scripted: interaction graph (graph on the object, edited in GraphCanvas, run by scripted.lua) --

## The GraphCanvas mutates `_it.graph` in place; refresh the button's node count and re-validate.
func _on_graph_changed() -> void:
	if _guarded(): return
	_refresh_graph_btn()
	changed.emit()


## Label the open-editor button with the current node count (so the inspector shows graph size at a glance).
func _refresh_graph_btn() -> void:
	if _it == null:
		return
	var n: int = (_it.graph.get("nodes", []) as Array).size()
	_graph_btn.text = "Edit interaction graph  (%d node%s) ▸" % [n, "" if n == 1 else "s"]


func _on_objtype_selected(value: String) -> void:
	if _guarded(): return
	if value == "":
		_it.properties.erase("OBJECT_TYPE")
	else:
		_it.properties["OBJECT_TYPE"] = value
	changed.emit()


func _on_sprite_changed(value: String) -> void:
	if _guarded(): return
	_it.sprite = int(value) if value != "" else -1
	changed.emit()


## Show the Character sprite picker or the Pokémon species picker for the bound NPC, and preselect
## from the stored sprite id: a Pokémon overworld sprite (a follower NARC index) round-trips back to
## its species; anything else is a character sprite.
func _load_sprite_source(it: Interactable) -> void:
	var species := GameData.species_for_npc_sprite(it.sprite)
	var is_pokemon := species > 0
	_sprite_source.selected = 1 if is_pokemon else 0
	_sprite_row.visible = not is_pokemon
	_pokemon_row.visible = is_pokemon
	_sprite.set_value(str(it.sprite) if (it.sprite >= 0 and not is_pokemon) else "")
	_pokemon.set_value(str(species) if is_pokemon else "")


func _on_sprite_source_selected(index: int) -> void:
	var is_pokemon := index == 1
	_sprite_row.visible = not is_pokemon
	_pokemon_row.visible = is_pokemon
	if _guarded(): return
	# Adopt the now-visible picker's current value so `sprite` matches the shown field.
	if is_pokemon:
		var species := int(_pokemon.get_value()) if _pokemon.get_value() != "" else 0
		_it.sprite = GameData.npc_sprite_for_species(species) if species > 0 else -1
	else:
		_it.sprite = int(_sprite.get_value()) if _sprite.get_value() != "" else -1
	changed.emit()


func _on_pokemon_changed(value: String) -> void:
	if _guarded(): return
	var species := int(value) if value != "" else 0
	_it.sprite = GameData.npc_sprite_for_species(species) if species > 0 else -1
	changed.emit()


func _on_direction_selected(index: int) -> void:
	if _guarded(): return
	_it.direction = index
	changed.emit()


func _on_display_name_changed(text: String) -> void:
	if _guarded(): return
	_it.display_name = text
	changed.emit()


# -- NPC: time of day --

func _load_time_of_day(it: Interactable) -> void:
	# Empty = all phases (always visible) → show all four ticked.
	var all := it.time_of_day.is_empty()
	for i in 4:
		_tod[i].button_pressed = all or (Interactable.PHASES[i] in it.time_of_day)


func _on_tod_changed(_pressed: bool) -> void:
	if _guarded(): return
	var phases: Array[String] = []
	for i in 4:
		if _tod[i].button_pressed:
			phases.append(str(Interactable.PHASES[i]))
	# All (or none) ticked means "no restriction" → empty array.
	if phases.size() == 4:
		phases.clear()
	_it.time_of_day = phases
	changed.emit()


# -- NPC: trainer vision --

func _load_vision(it: Interactable) -> void:
	var on := it.vision_range >= 0
	_trainer.button_pressed = on
	_vision.value = it.vision_range if on else 0
	_vision.editable = on


func _write_vision(_ignored: Variant = null) -> void:
	if _guarded(): return
	_it.vision_range = int(_vision.value) if _trainer.button_pressed else -1
	_vision.editable = _trainer.button_pressed
	changed.emit()


# -- NPC: behaviour --

func _load_behavior(it: Interactable) -> void:
	# Reset every param control to its default first, so the non-active behaviours (and any unset
	# sub-fields of the active one) never show stale values carried over from a prior selection.
	_look_pause.value = 2000
	for cb in _look_dirs:
		cb.button_pressed = true
	_wander_radius.value = 3
	_wander_pause.value = 0
	_patrol_mode.selected = 0
	_patrol_pause.value = 1500

	var b := it.behavior
	match str(b.get("kind", "")):
		"look_around":
			_behavior.selected = 1
			_look_pause.value = int(b.get("pause_ms", 2000))
			var dirs := PackedInt32Array()
			for d in b.get("directions", [0, 1, 2, 3]):
				dirs.append(int(d))
			for i in 4:
				_look_dirs[i].button_pressed = i in dirs
		"wander":
			_behavior.selected = 2
			_wander_radius.value = int(b.get("radius", 3))
			_wander_pause.value = int(b.get("pause_ms", 0))
		"patrol_path":
			_behavior.selected = 3
			_patrol_mode.selected = 1 if str(b.get("mode", "loop")) == "ping_pong" else 0
			_patrol_pause.value = int(b.get("pause_ms", 1500))
		_:
			_behavior.selected = 0


func _write_behavior(_ignored: Variant = null) -> void:
	if _guarded(): return
	match _behavior.selected:
		1:
			_it.behavior = { "kind": "look_around", "pause_ms": int(_look_pause.value), "directions": _checked_look_dirs() }
		2:
			_it.behavior = { "kind": "wander", "radius": int(_wander_radius.value), "pause_ms": int(_wander_pause.value) }
		3:
			_it.behavior = { "kind": "patrol_path", "mode": "ping_pong" if _patrol_mode.selected == 1 else "loop", "pause_ms": int(_patrol_pause.value) }
			if _it.waypoints.is_empty():
				_it.waypoints.append(_it.tile)  # first waypoint must be the NPC's own tile
				update_waypoint_count()
		_:
			_it.behavior = {}
	_refresh_visibility()
	changed.emit()


func _checked_look_dirs() -> Array:
	var dirs: Array = []
	for i in 4:
		if _look_dirs[i].button_pressed:
			dirs.append(i)
	return dirs if not dirs.is_empty() else [0, 1, 2, 3]


func _on_waypoint_clear() -> void:
	if _guarded(): return
	_it.waypoints.clear()
	update_waypoint_count()
	changed.emit()


# -- resource node: encounter group --

func _on_encounter_changed(text: String) -> void:
	if _guarded(): return
	if text == "":
		_it.properties.erase("ENCOUNTER_GROUP")
	else:
		_it.properties["ENCOUNTER_GROUP"] = text
	changed.emit()
