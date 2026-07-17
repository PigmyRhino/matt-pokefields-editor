extends Node
## App entry. A persistent Map/Data switch (bottom-left overlay) toggles between the map editor
## (needs a FireRed ROM → ROM setup first) and the data editor (no ROM; edits content/ working copy).

const ROM_SETUP_SCENE := preload("res://scenes/RomSetup.tscn")
const MAP_EDITOR_SCENE := preload("res://scenes/MapEditor.tscn")
const DATA_EDITOR_SCENE := preload("res://scenes/DataEditor.tscn")

var _current: Node
var _pending_mode := "map"
var _map_btn: Button
var _data_btn: Button


func _ready() -> void:
	_build_switcher()
	_set_mode("map")


## A persistent segmented Map/Data switch (bottom-left overlay). The two buttons share a ButtonGroup so
## the active mode reads as the pressed tab — the old plain buttons gave no indication of where you were.
func _build_switcher() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 0)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_left = 8
	bar.offset_top = -36
	bar.offset_bottom = -8
	layer.add_child(bar)
	var group := ButtonGroup.new()
	_map_btn = _tab("🗺 Map", group, func() -> void: _set_mode("map"))
	_data_btn = _tab("📋 Data", group, func() -> void: _set_mode("data"))
	bar.add_child(_map_btn)
	bar.add_child(_data_btn)


func _tab(label: String, group: ButtonGroup, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(84, 0)
	b.pressed.connect(on_press)
	return b


func _set_mode(mode: String) -> void:
	# All three ROMs are required up front (maps + sprites), so both modes gate on setup.
	if not RomManager.is_configured():
		_pending_mode = mode
		var setup := _show(ROM_SETUP_SCENE) as RomSetup
		setup.setup_complete.connect(_on_setup_complete)
		return
	if mode == "data":
		_show(DATA_EDITOR_SCENE)
	else:
		_show(MAP_EDITOR_SCENE)
	# Reflect the active mode on the tabs (no_signal so this doesn't re-enter _set_mode).
	_map_btn.set_pressed_no_signal(mode == "map")
	_data_btn.set_pressed_no_signal(mode == "data")


func _on_setup_complete() -> void:
	_set_mode(_pending_mode)


## Jump from another mode (e.g. the Flag Browser) to a specific object on a map: switch to the Map
## editor and have it open `map_id` and select the interactable (by id) or zone (by name).
func open_map_object(map_id: String, object_id: String, object_kind: String) -> void:
	_set_mode("map")
	if _current != null and _current.has_method("reveal"):
		_current.reveal(map_id, object_id, object_kind)


func _show(scene: PackedScene) -> Node:
	if _current != null:
		_current.queue_free()
	_current = scene.instantiate()
	add_child(_current)
	return _current
