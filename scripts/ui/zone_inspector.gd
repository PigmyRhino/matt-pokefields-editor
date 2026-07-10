class_name ZoneInspector
extends PanelContainer
## Edits the selected Zone. The four category sections (Area / Encounter / Gate / Resource) show by
## the zone's category (fixed at creation). Every value-set field is a picker — no free text or CSV.

signal changed
signal deleted

@onready var _category: Label = %ZCategory
@onready var _name: LineEdit = %ZName
@onready var _verts: Label = %ZVerts
# Area
@onready var _area_box: Control = %AreaBox
@onready var _display_name: LineEdit = %ZDisplayName
@onready var _day_track: SearchPicker = %DayTrack
@onready var _night_track: SearchPicker = %NightTrack
@onready var _day_amb: SearchPicker = %DayAmbience
@onready var _night_amb: SearchPicker = %NightAmbience
@onready var _climate: OptionButton = %ClimateOpt
# Encounter
@onready var _enc_box: Control = %EncBox
@onready var _terrain: OptionButton = %TerrainOpt
@onready var _enc_group: SearchPicker = %EncGroup
@onready var _fish_group: SearchPicker = %FishGroup
# Gate
@onready var _gate_box: Control = %GateBox
@onready var _req_flags: ChipSelect = %ReqFlags
@onready var _forbid_flags: ChipSelect = %ForbidFlags
@onready var _req_badges: ChipSelect = %ReqBadges
@onready var _req_items: ItemReqList = %ReqItems
@onready var _party_check: CheckBox = %PartyCheck
@onready var _party_spin: SpinBox = %PartySpin
# Resource
@onready var _res_box: Control = %ResBox
@onready var _object_types: ChipSelect = %ObjectTypes
@onready var _max_active: SpinBox = %MaxActive
@onready var _delete: Button = %ZDelete

var _z: Zone = null
var _loading := false
## Per-predicate blocked-message fields (GATE_MESSAGES), rebuilt as the gate's predicates change.
var _gate_msgs: VBoxContainer


func _ready() -> void:
	for c in Zone.CLIMATES:
		_climate.add_item(c)
	for t in Zone.ENCOUNTER_TERRAINS:
		_terrain.add_item(t)
	_day_track.set_entries(Catalog.bgm)
	_night_track.set_entries(Catalog.bgm)
	_day_amb.set_entries(Catalog.ambience)
	_night_amb.set_entries(Catalog.ambience)
	# Encounter groups + resource OBJECT_TYPEs read LIVE from content/ (designer edits them on the Data
	# cards); the bundled Catalog snapshot drifts and misses freshly-added groups.
	_enc_group.set_entries(ContentScan.encounter_groups())
	_fish_group.set_entries(ContentScan.encounter_groups())
	# Suggest flags already used anywhere (set/read in scripts, or gating another zone), but allow typing
	# a brand-new one — gate flags share the one registry with the node editor's flag picker.
	_req_flags.allow_custom = true
	_forbid_flags.allow_custom = true
	_req_flags.set_entries(FlagRegistry.entries())
	_forbid_flags.set_entries(FlagRegistry.entries())
	_req_badges.set_entries(Catalog.badges)
	_req_items.set_entries(Catalog.items)
	_object_types.set_entries(ContentScan.object_types())

	_name.text_changed.connect(_on_name)
	_display_name.text_changed.connect(_on_display_name)
	_day_track.value_changed.connect(_on_day_track)
	_night_track.value_changed.connect(_on_night_track)
	_day_amb.value_changed.connect(_on_day_amb)
	_night_amb.value_changed.connect(_on_night_amb)
	_climate.item_selected.connect(_on_climate)
	_terrain.item_selected.connect(_on_terrain)
	_enc_group.value_changed.connect(_on_enc_group)
	_fish_group.value_changed.connect(_on_fish_group)
	_req_flags.changed.connect(_on_req_flags)
	_forbid_flags.changed.connect(_on_forbid_flags)
	_req_badges.changed.connect(_on_req_badges)
	_req_items.changed.connect(_on_req_items)
	_party_check.toggled.connect(_write_party)
	_party_spin.value_changed.connect(_write_party)
	_object_types.changed.connect(_on_object_types)
	_max_active.value_changed.connect(_on_max_active)
	_delete.pressed.connect(func() -> void: deleted.emit())
	_gate_msgs = VBoxContainer.new()
	_gate_box.add_child(_gate_msgs)
	visible = false


func bind(z: Zone) -> void:
	_z = z
	visible = z != null
	if z == null:
		return
	_loading = true
	_category.text = "%s zone" % z.category
	_name.text = z.name
	_verts.text = "%d tiles" % z.tile_count()
	_area_box.visible = z.category == "Area"
	_enc_box.visible = z.category == "Encounter"
	_gate_box.visible = z.category == "Gate"
	_res_box.visible = z.category == "ResourceArea"
	match z.category:
		"Area":
			_display_name.text = z.display_name
			_day_track.set_value(z.day_track)
			_night_track.set_value(z.night_track)
			_day_amb.set_value(z.day_ambience)
			_night_amb.set_value(z.night_ambience)
			_climate.selected = maxi(0, Zone.CLIMATES.find(z.climate))
		"Encounter":
			_terrain.selected = maxi(0, Zone.ENCOUNTER_TERRAINS.find(z.terrain))
			_enc_group.set_value(z.encounter_group)
			_fish_group.set_value(z.fish_encounter_group)
		"Gate":
			_req_flags.set_values(z.requires_flag.duplicate())
			_forbid_flags.set_values(z.forbids_flag.duplicate())
			_req_badges.set_values(_badges_to_values(z.requires_badge))
			_req_items.set_reqs(z.requires_item)
			_party_check.button_pressed = z.requires_party_min >= 0
			_party_spin.value = z.requires_party_min if z.requires_party_min >= 0 else 0
			_party_spin.editable = z.requires_party_min >= 0
		"ResourceArea":
			_object_types.set_values(z.object_types.duplicate())
			_max_active.value = z.max_active
	_rebuild_gate_messages()  # clears for non-gate categories
	_loading = false


func update_verts() -> void:
	if _z != null:
		_verts.text = "%d tiles" % _z.tile_count()


func _guarded() -> bool:
	return _loading or _z == null


# -- common / area --

func _on_name(t: String) -> void:
	if _guarded(): return
	_z.name = t
	changed.emit()


func _on_display_name(t: String) -> void:
	if _guarded(): return
	_z.display_name = t
	changed.emit()


func _on_day_track(v: String) -> void:
	if _guarded(): return
	_z.day_track = v
	changed.emit()


func _on_night_track(v: String) -> void:
	if _guarded(): return
	_z.night_track = v
	changed.emit()


func _on_day_amb(v: String) -> void:
	if _guarded(): return
	_z.day_ambience = v
	changed.emit()


func _on_night_amb(v: String) -> void:
	if _guarded(): return
	_z.night_ambience = v
	changed.emit()


func _on_climate(index: int) -> void:
	if _guarded(): return
	_z.climate = _climate.get_item_text(index)
	changed.emit()


# -- encounter --

func _on_terrain(index: int) -> void:
	if _guarded(): return
	_z.terrain = _terrain.get_item_text(index)
	changed.emit()


func _on_enc_group(v: String) -> void:
	if _guarded(): return
	_z.encounter_group = v
	changed.emit()


func _on_fish_group(v: String) -> void:
	if _guarded(): return
	_z.fish_encounter_group = v
	changed.emit()


# -- gate --

func _on_req_flags(values: Array) -> void:
	if _guarded(): return
	_z.requires_flag = _str_array(values)
	_rebuild_gate_messages()
	changed.emit()


func _on_forbid_flags(values: Array) -> void:
	if _guarded(): return
	_z.forbids_flag = _str_array(values)
	_rebuild_gate_messages()
	changed.emit()


func _on_req_badges(values: Array) -> void:
	if _guarded(): return
	var out: Array[int] = []
	for v in values:
		out.append(int(v))
	_z.requires_badge = out
	_rebuild_gate_messages()
	changed.emit()


func _on_req_items(reqs: Array) -> void:
	if _guarded(): return
	_z.requires_item = reqs.duplicate(true)
	_rebuild_gate_messages()
	changed.emit()


func _write_party(_ignored: Variant = null) -> void:
	if _guarded(): return
	_z.requires_party_min = int(_party_spin.value) if _party_check.button_pressed else -1
	_party_spin.editable = _party_check.button_pressed
	_rebuild_gate_messages()
	changed.emit()


## A blocked-message field per current gate predicate, bound to GATE_MESSAGES (keyed by predicate, so
## the copy is shared by every gate with that same requirement). Cleared for non-gate zones.
func _rebuild_gate_messages() -> void:
	for c in _gate_msgs.get_children():
		c.queue_free()
	if _z == null or _z.category != "Gate":
		return
	var entries: Array = []  # [predicate_key, label]
	for f in _z.requires_flag:
		entries.append(["flag:%s" % f, "requires flag: %s" % f])
	for f in _z.forbids_flag:
		entries.append(["forbids:%s" % f, "forbidden by flag: %s" % f])
	for b in _z.requires_badge:
		entries.append(["badge:%d" % int(b), "requires badge %d" % int(b)])
	for it in _z.requires_item:
		var iid := int((it as Dictionary).get("item_id", 0))
		entries.append(["item:%d" % iid, "requires item %d" % iid])
	if _z.requires_party_min >= 0:
		entries.append(["party_min", "party too small"])
	if entries.is_empty():
		return
	var header := Label.new()
	header.text = "— blocked messages —"
	_gate_msgs.add_child(header)
	for e in entries:
		var key: String = e[0]
		var lbl := Label.new()
		lbl.text = e[1]
		_gate_msgs.add_child(lbl)
		var te := TextEdit.new()
		te.custom_minimum_size = Vector2(0, 52)
		te.placeholder_text = "shown when this requirement blocks the player"
		te.text = str(_z.gate_messages.get(key, ""))
		te.text_changed.connect(func() -> void:
			var t := te.text
			if t.strip_edges() == "":
				_z.gate_messages.erase(key)
			else:
				_z.gate_messages[key] = t
			changed.emit())
		_gate_msgs.add_child(te)


# -- resource --

func _on_object_types(values: Array) -> void:
	if _guarded(): return
	_z.object_types = _str_array(values)
	changed.emit()


func _on_max_active(value: float) -> void:
	if _guarded(): return
	_z.max_active = int(value)
	changed.emit()


# -- helpers --

func _str_array(values: Array) -> Array[String]:
	var out: Array[String] = []
	for v in values:
		out.append(str(v))
	return out


func _badges_to_values(badges: Array) -> Array:
	var out: Array = []
	for b in badges:
		out.append(str(b))
	return out
