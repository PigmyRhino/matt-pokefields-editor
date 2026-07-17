class_name ChipSelect
extends VBoxContainer
## Multi-select over a Catalog entries array, shown as removable chips with a SearchPicker to add.
## Stores an Array of `value` strings; emits `changed(values)`. Callers that need ints (e.g. badges)
## convert on read.

signal changed(values: Array)

## When set, the add-picker offers the typed text as a brand-new value (see SearchPicker.allow_custom),
## so a chip list can suggest known values yet still author fresh ones (e.g. gate flags).
var allow_custom := false:
	set(value):
		allow_custom = value
		if _adder != null:
			_adder.allow_custom = value

var _entries: Array = []
var _values: Array = []
var _adder: SearchPicker
var _chips: HFlowContainer


func _ready() -> void:
	_adder = SearchPicker.new()
	_adder.allow_none = false
	_adder.allow_custom = allow_custom
	_adder.placeholder = "+ add"
	add_child(_adder)
	_adder.value_changed.connect(_on_add)
	_chips = HFlowContainer.new()
	add_child(_chips)
	_adder.set_entries(_entries)  # apply anything set before we entered the tree
	_rebuild()


## set_entries/set_values are safe to call before the node is in the tree — values are stored and
## applied in _ready once the inner controls exist.
func set_entries(entries: Array) -> void:
	_entries = entries
	if _adder != null:
		_adder.set_entries(entries)
		_rebuild()


func set_values(values: Array) -> void:
	_values = values.duplicate()
	if _chips != null:
		_rebuild()


func get_values() -> Array:
	return _values


func _on_add(value: String) -> void:
	if value != "" and not _values.has(value):
		_values.append(value)
		_rebuild()
		changed.emit(_values)
	_adder.set_value("")  # reset back to "+ add"


func _on_remove(value: String) -> void:
	_values.erase(value)
	_rebuild()
	changed.emit(_values)


func _rebuild() -> void:
	for c in _chips.get_children():
		c.queue_free()
	for v in _values:
		var chip := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = Catalog.label_of(_entries, v)
		chip.add_child(lbl)
		var x := Button.new()
		x.text = "✕"
		x.pressed.connect(_on_remove.bind(v))
		chip.add_child(x)
		_chips.add_child(chip)
