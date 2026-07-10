class_name ItemReqList
extends VBoxContainer
## Editable list of item requirements — rows of [item SearchPicker | qty SpinBox | ✕] plus an add
## button. Stores Array of { "item_id": int, "min_qty": int }; emits `changed(reqs)`. Item entries
## ([{value=str(id), label=name}]) are supplied by the caller from GameData.

signal changed(reqs: Array)

var _entries: Array = []
var _reqs: Array = []
var _add: Button
var _rows: VBoxContainer


func _ready() -> void:
	_add = Button.new()
	_add.text = "+ add item"
	_add.pressed.connect(_on_add)
	add_child(_add)
	_rows = VBoxContainer.new()
	add_child(_rows)
	_rebuild()  # apply anything set before we entered the tree


## Safe to call before the node is in the tree — applied in _ready once _rows exists.
func set_entries(entries: Array) -> void:
	_entries = entries
	if _rows != null:
		_rebuild()


func set_reqs(reqs: Array) -> void:
	_reqs = reqs.duplicate(true)
	if _rows != null:
		_rebuild()


func get_reqs() -> Array:
	return _reqs


func _on_add() -> void:
	_reqs.append({ "item_id": 0, "min_qty": 1 })
	_rebuild()
	changed.emit(_reqs)


func _on_item_changed(value: String, i: int) -> void:
	_reqs[i]["item_id"] = int(value) if value != "" else 0
	changed.emit(_reqs)


func _on_qty_changed(value: float, i: int) -> void:
	_reqs[i]["min_qty"] = int(value)
	changed.emit(_reqs)


func _on_remove(i: int) -> void:
	_reqs.remove_at(i)
	_rebuild()
	changed.emit(_reqs)


func _rebuild() -> void:
	for c in _rows.get_children():
		c.queue_free()
	for i in _reqs.size():
		var req: Dictionary = _reqs[i]
		var row := HBoxContainer.new()
		var pick := SearchPicker.new()
		pick.allow_none = false
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.set_entries(_entries)
		pick.set_value(str(int(req.get("item_id", 0))))
		pick.value_changed.connect(_on_item_changed.bind(i))
		row.add_child(pick)
		var qty := SpinBox.new()
		qty.min_value = 1
		qty.max_value = 999
		qty.value = int(req.get("min_qty", 1))
		qty.value_changed.connect(_on_qty_changed.bind(i))
		row.add_child(qty)
		var x := Button.new()
		x.text = "✕"
		x.pressed.connect(_on_remove.bind(i))
		row.add_child(x)
		_rows.add_child(row)
