class_name WarpInspector
extends PanelContainer
## Edits the selected Warp or WarpTarget. The warp-only fields and target-only fields show/hide by
## type; `target_warp` is a cross-reference dropdown of the warp-target names on the warp's *destination*
## map (`target_map`) — the live targets of the map being edited when it's a same-map warp, else the
## baked targets of the other map (Catalog).

signal changed
signal deleted
## "Follow" the selected warp to where it lands: (target_map, target_warp). The MapEditor switches map
## if needed and selects the target.
signal goto_target(map_id: String, warp_name: String)

@onready var _name: LineEdit = %WName
@onready var _tile_label: Label = %WTile
@onready var _warp_box: Control = %WarpBox
@onready var _target_map: SearchPicker = %TargetMap
@onready var _target_warp_opt: OptionButton = %TargetWarpOpt
@onready var _goto: Button = %GotoTarget
@onready var _warp_type: SearchPicker = %WarpType
@onready var _door_type: SearchPicker = %DoorType
@onready var _target_box: Control = %TargetBox
@onready var _direction: OptionButton = %TDirection
@onready var _delete: Button = %WDelete

var _obj: Variant = null  # Warp or WarpTarget
var _loading := false
var _self_map := ""          # the map being edited (so same-map warps see its live, unsaved targets)
var _self_targets: Array = []  # that map's warp_targets (live)


func _ready() -> void:
	for d in Interactable.DIRECTIONS:
		_direction.add_item(d)
	var map_entries: Array = []
	for m in Catalog.maps:
		map_entries.append({ "value": str(m["map_id"]), "label": "%s  (%s)" % [str(m["name"]), str(m["map_id"])] })
	_target_map.set_entries(map_entries)
	_warp_type.set_entries(Catalog.warp_types)
	_door_type.set_entries(Catalog.door_types)
	_name.text_changed.connect(_on_name)
	_target_map.value_changed.connect(_on_target_map)
	_target_warp_opt.item_selected.connect(_on_target_warp)
	_goto.pressed.connect(_on_goto)
	_warp_type.value_changed.connect(_on_warp_type)
	_door_type.value_changed.connect(_on_door_type)
	_direction.item_selected.connect(_on_direction)
	_delete.pressed.connect(func() -> void: deleted.emit())
	visible = false


## Bind a Warp or WarpTarget. `self_map`/`self_targets` are the map being edited and its live warp-target
## list, used to populate the Target Warp dropdown for same-map warps (cross-map warps read Catalog).
func bind(obj: Variant, self_map := "", self_targets: Array = []) -> void:
	_obj = obj
	_self_map = self_map
	_self_targets = self_targets
	visible = obj != null
	if obj == null:
		return
	_loading = true
	var is_warp := obj is Warp
	_name.text = obj.name
	_tile_label.text = "tile (%d, %d)" % [obj.tile.x, obj.tile.y]
	_warp_box.visible = is_warp
	_target_box.visible = not is_warp
	if is_warp:
		_target_map.set_value(obj.target_map)
		_fill_targets(obj.target_warp)
		_warp_type.set_value(obj.warp_type)
		_door_type.set_value(obj.door_type)
	else:
		_direction.selected = obj.direction
	_update_goto()
	_loading = false


func _guarded() -> bool:
	return _loading or _obj == null


func _on_name(text: String) -> void:
	if _guarded(): return
	_obj.name = text
	changed.emit()


func _on_target_map(text: String) -> void:
	if _guarded(): return
	_obj.target_map = text
	_fill_targets(str(_obj.target_warp))  # destination changed — repopulate its target list
	_update_goto()
	changed.emit()


func _on_target_warp(index: int) -> void:
	if _guarded(): return
	_obj.target_warp = _target_warp_opt.get_item_text(index)
	_update_goto()
	changed.emit()


func _on_goto() -> void:
	if _obj is Warp and str(_obj.target_warp) != "":
		goto_target.emit(str(_obj.target_map), str(_obj.target_warp))


## The Go button only applies to a warp that names a destination target.
func _update_goto() -> void:
	_goto.disabled = not (_obj is Warp) or str(_obj.target_warp) == ""


func _on_warp_type(text: String) -> void:
	if _guarded(): return
	_obj.warp_type = text
	changed.emit()


func _on_door_type(text: String) -> void:
	if _guarded(): return
	_obj.door_type = text
	changed.emit()


func _on_direction(index: int) -> void:
	if _guarded(): return
	_obj.direction = index
	changed.emit()


## Names to offer for a warp pointing at `target_map`: the live targets of the map being edited (so
## just-added, unsaved ones show), else the baked targets of the destination map (Catalog).
func _target_names_for(map_id: String) -> Array:
	if map_id == _self_map:
		var out: Array = []
		for t in _self_targets:
			out.append(str(t.name))
		return out
	return Catalog.warp_target_names(map_id)


## Fill the Target Warp dropdown from the destination map's targets, preserving the current value even
## when it isn't among them (shown as an extra entry, so a hand-set / cross-map id is never dropped).
func _fill_targets(value: String) -> void:
	_target_warp_opt.clear()
	for n in _target_names_for(str(_obj.target_map)):
		_target_warp_opt.add_item(n)
	for i in _target_warp_opt.item_count:
		if _target_warp_opt.get_item_text(i) == value:
			_target_warp_opt.selected = i
			return
	if value != "":
		_target_warp_opt.add_item(value)
		_target_warp_opt.selected = _target_warp_opt.item_count - 1
	else:
		_target_warp_opt.selected = -1
