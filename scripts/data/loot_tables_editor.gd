extends DatasetEditor
## loot_tables.json — { "tables": { <name>: [ { item_id, weight, qty_min, qty_max }, ... ] } }
## Weighted drop pools referenced by name from resource_defs / encounters. One table at a time via the
## NamedCatalog selector (New / Rename / Delete); each drop shows the item icon + name.

var _raw: Dictionary = {}
var _path := ""
var _cat: NamedCatalog


func load_data() -> void:
	_path = base_dir + "/loot_tables.json"
	_raw = JsonIO.load_file(_path)
	if not _raw.has("tables"):
		_raw["tables"] = {}
	var hint := Label.new()
	hint.text = "Drop pools. A gather/kill rolls one row by weight; qty is uniform in [min, max]."
	add_child(hint)
	_cat = NamedCatalog.new()
	add_child(_cat)
	_cat.setup(_raw["tables"], "new_table", func() -> Variant: return [], _build_table)
	_cat.dirty.connect(func() -> void: dirty.emit())


func save_data() -> bool:
	return JsonIO.save_file(_path, _raw)


func current_data() -> Variant:
	return _raw.get("tables", {})


func reveal(p: Problem) -> void:
	_cat.reveal(p.context)


func _build_table(_name: String, record: Variant, into: VBoxContainer) -> void:
	var arr: Array = record
	var head := HBoxContainer.new()
	for col in [["item", 0], ["wt", 60], ["min", 46], ["max", 46], ["", 28]]:
		var l := Label.new()
		l.text = str(col[0])
		l.custom_minimum_size.x = col[1]
		if col[0] == "item":
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(l)
	into.add_child(head)
	for i in arr.size():
		var entry: Dictionary = arr[i]
		var row := HBoxContainer.new()
		var pick := _item_id_picker(entry, "item_id", false)
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.tooltip_text = "Item dropped."
		row.add_child(pick)
		row.add_child(_compact(_int_field(entry, "weight", 100, 0, 100000), 60))
		row.add_child(_compact(_int_field(entry, "qty_min", 1, 0, 999), 46))
		row.add_child(_compact(_int_field(entry, "qty_max", 1, 0, 999), 46))
		row.add_child(_icon_remove_button(func() -> void:
			arr.remove_at(i)
			_cat.refresh_detail()
			dirty.emit()))
		into.add_child(row)
	var add := Button.new()
	add.text = "+ add drop"
	add.pressed.connect(func() -> void:
		arr.append({ "item_id": 0, "weight": 100, "qty_min": 1, "qty_max": 1 })
		_cat.refresh_detail()
		dirty.emit())
	into.add_child(add)


func _compact(ctrl: Control, width: int) -> Control:
	ctrl.custom_minimum_size.x = width
	return ctrl
