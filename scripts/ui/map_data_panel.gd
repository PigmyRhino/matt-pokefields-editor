class_name MapDataPanel
extends PanelContainer

const CONTENT_DIR := "res://content"
const _ERR_COLOR := Color(1.0, 0.5, 0.5)
const _WARN_COLOR := Color(1.0, 0.82, 0.4)

const DATASETS := [
	{ "name": "Tips", "script": preload("res://scripts/data/tips_editor.gd") },
	{ "name": "Tool categories", "script": preload("res://scripts/data/tool_categories_editor.gd") },
	{ "name": "Loot tables", "script": preload("res://scripts/data/loot_tables_editor.gd") },
	{ "name": "Resource defs", "script": preload("res://scripts/data/resource_defs_editor.gd") },
	{ "name": "Resource nodes", "script": preload("res://scripts/data/resource_nodes_editor.gd") },
	{ "name": "Shops", "script": preload("res://scripts/data/shops_editor.gd") },
	{ "name": "Clothing", "script": preload("res://scripts/data/clothing_editor.gd") },
	{ "name": "Items", "script": preload("res://scripts/data/custom_items_editor.gd") },
	{ "name": "Encounters", "script": preload("res://scripts/data/encounter_data_editor.gd") },
	{ "name": "Trainers", "script": preload("res://scripts/data/trainers_editor.gd") },
	{ "name": "Job boards", "script": preload("res://scripts/data/job_boards_editor.gd") },
	{ "name": "Flags", "script": preload("res://scripts/data/flag_browser.gd") },
]

@onready var _list: ItemList = %List
@onready var _content: ScrollContainer = %Content
@onready var _status: Label = %Status
@onready var _save: Button = %SaveBtn
@onready var _check_all: Button = %CheckAllBtn

var _editor: DatasetEditor = null
var _active_name := ""
var _dirty := false


func _ready() -> void:
	for d in DATASETS:
		_list.add_item(d["name"])
	_list.item_selected.connect(_on_select)
	_save.pressed.connect(_on_save)
	_save.disabled = true
	_check_all.pressed.connect(_on_check_all)
	if not DATASETS.is_empty():
		_list.select(0)
		_on_select(0)


func _on_select(idx: int) -> void:
	if _editor != null:
		_editor.queue_free()
		_editor = null
	var script: GDScript = DATASETS[idx]["script"]
	_editor = script.new()
	_editor.base_dir = CONTENT_DIR
	_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor.add_theme_constant_override("separation", 4)
	_content.add_child(_editor)
	_editor.load_data()
	_editor.dirty.connect(_on_dirty)
	_active_name = str(DATASETS[idx]["name"])
	_dirty = false
	_revalidate()


func _on_dirty() -> void:
	_dirty = true
	_revalidate()


func _revalidate() -> void:
	if _editor == null:
		return
	var problems := DataValidator.validate(_active_name, CONTENT_DIR, _editor.current_data())
	var errs := Problem.error_count(problems)
	_save.disabled = (not _dirty) or errs > 0
	_badge(_active_name, errs, problems.size() - errs)
	if errs > 0:
		_status.text = "● %d error(s)" % errs
	elif _dirty:
		_status.text = "● unsaved"
	else:
		_status.text = _active_name


func _on_save() -> void:
	if _editor == null:
		return
	if _editor.save_data():
		_dirty = false
		_revalidate()
		_status.text = "saved ✓"
	else:
		_status.text = "save FAILED"


func _on_check_all() -> void:
	for d in DATASETS:
		var nm := str(d["name"])
		var override: Variant = _editor.current_data() if nm == _active_name else null
		var probs := DataValidator.validate(nm, CONTENT_DIR, override)
		_badge(nm, Problem.error_count(probs), probs.size() - Problem.error_count(probs))
	_status.text = "all datasets checked"


func _badge(name: String, errs: int, warns: int) -> void:
	var idx := _index_of(name)
	if idx < 0:
		return
	var base := str(DATASETS[idx]["name"])
	if errs > 0:
		_list.set_item_text(idx, "%s  ✕%d" % [base, errs])
		_list.set_item_custom_fg_color(idx, _ERR_COLOR)
	elif warns > 0:
		_list.set_item_text(idx, "%s  ⚠%d" % [base, warns])
		_list.set_item_custom_fg_color(idx, _WARN_COLOR)
	else:
		_list.set_item_text(idx, base)
		_list.set_item_custom_fg_color(idx, Color.WHITE)


func clear_filter() -> void:
	if _editor != null and _editor.has_method("reveal"):
		var p := Problem.warn("", "")
		_editor.reveal(p)


func reveal_encounter(group_id: String) -> void:
	var idx := _index_of("Encounters")
	if idx < 0:
		return
	# Switch to the Encounters dataset if not already active.
	if _active_name != "Encounters":
		_list.select(idx)
		_on_select(idx)
	# Filter the encounter editor to show only this group.
	if _editor != null:
		var p := Problem.warn("", group_id)
		_editor.reveal(p)


func _index_of(name: String) -> int:
	for i in DATASETS.size():
		if str(DATASETS[i]["name"]) == name:
			return i
	return -1
