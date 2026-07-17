extends DatasetEditor
## game_tips.json — { "tips": [string, ...] }. Editable list of loading-screen tips.

var _raw: Dictionary = {}
var _path := ""
var _list_box: VBoxContainer


func load_data() -> void:
	_path = base_dir + "/game_tips.json"
	var loaded: Variant = JsonIO.load_file(_path)
	_raw = loaded if typeof(loaded) == TYPE_DICTIONARY else { "tips": [] }
	if not _raw.has("tips"):
		_raw["tips"] = []
	var hint := Label.new()
	hint.text = "Loading-screen tips shown to players. One line each."
	add_child(hint)
	var add := Button.new()
	add.text = "+ add tip"
	add.tooltip_text = "Add a new tip line."
	add.pressed.connect(func() -> void:
		(_raw["tips"] as Array).append("New tip")
		_rebuild()
		dirty.emit())
	add_child(add)
	_list_box = VBoxContainer.new()
	add_child(_list_box)
	_rebuild()


func save_data() -> bool:
	return JsonIO.save_file(_path, _raw)


func current_data() -> Variant:
	return _raw


func _rebuild() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	var tips: Array = _raw["tips"]
	for i in tips.size():
		var row := HBoxContainer.new()
		var le := LineEdit.new()
		le.text = str(tips[i])
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.text_changed.connect(func(t: String) -> void:
			tips[i] = t
			dirty.emit())
		row.add_child(le)
		row.add_child(_icon_remove_button(func() -> void:
			tips.remove_at(i)
			_rebuild()
			dirty.emit()))
		_list_box.add_child(row)
