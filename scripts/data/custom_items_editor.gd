extends DatasetEditor
## custom_items.json — [ { item_id, name, item_type, category, description, cost, stackable?,
## tradable?, sellable? }, ... ]. Master-detail: filter + list, edit the selected item below.
## item_type/category options are the distinct values already in the file (no hardcoded enum).

var _raw: Array = []
var _path := ""
var _types: Array = []
var _cats: Array = []
var _filter: LineEdit
var _list: ItemList
var _form: VBoxContainer
var _rows: Array[int] = []  # list row -> _raw index
var _selected := -1         # _raw index currently shown in the form


func load_data() -> void:
	_path = base_dir + "/custom_items.json"
	var loaded: Variant = JsonIO.load_file(_path)
	_raw = loaded if typeof(loaded) == TYPE_ARRAY else []
	_types = _distinct_entries(_raw, "item_type")
	_cats = _distinct_entries(_raw, "category")

	var hint := Label.new()
	hint.text = "Custom items (id 1000+). Icons load from assets/sprites/items/{id}.png, or a Gen 5 ROM icon when rom_item_id is set."
	add_child(hint)
	_filter = LineEdit.new()
	_filter.placeholder_text = "filter by name or id…"
	_filter.text_changed.connect(func(_t: String) -> void: _populate())
	add_child(_filter)
	var bar := HBoxContainer.new()
	var add := Button.new()
	add.text = "+ add item"
	add.tooltip_text = "Append a new item with the next free id."
	add.pressed.connect(_on_add)
	bar.add_child(add)
	var del := Button.new()
	del.text = "✕ remove selected"
	del.tooltip_text = "Delete the item currently shown below."
	del.pressed.connect(_on_remove_selected)
	bar.add_child(del)
	add_child(bar)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 560)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(row: int) -> void: _build_form(_rows[row]))
	add_child(_list)
	_form = VBoxContainer.new()
	add_child(_form)
	_populate()


func save_data() -> bool:
	return JsonIO.save_file(_path, _raw)


func current_data() -> Variant:
	return _raw


func reveal(p: Problem) -> void:
	_filter.text = p.context
	_populate()


func _populate() -> void:
	_list.clear()
	_rows.clear()
	var q := _filter.text.to_lower()
	for i in _raw.size():
		var it: Dictionary = _raw[i]
		var label := "%s  (%s)" % [str(it.get("name", "?")), str(it.get("item_id", ""))]
		if q == "" or label.to_lower().contains(q):
			var tex := _item_icon(int(it.get("item_id", 0)))
			if tex != null:
				_list.add_item(label, tex)
			else:
				_list.add_item(label)
			_rows.append(i)


func _build_form(idx: int) -> void:
	_selected = idx
	for c in _form.get_children():
		c.queue_free()
	var it: Dictionary = _raw[idx]
	_form.add_child(_row("item_id", _int_field(it, "item_id", 0, 1, 99999), "Unique id (custom items use 1000+). Sprite is assets/sprites/items/{id}.png."))
	_form.add_child(_row("name", _str_field(it, "name"), "Display name."))
	_form.add_child(_row("item_type", _picker_field(_types, it, "item_type", false), "Classification (tool/material/equipment/collectible)."))
	_form.add_child(_row("category", _picker_field(_cats, it, "category", false), "Sub-category used for grouping/crafting."))
	_form.add_child(_row("description", _str_field(it, "description"), "Inventory description."))
	_form.add_child(_row("cost", _int_field(it, "cost", 0, 0, 10000000), "Base sell/buy value."))
	_form.add_child(_row("rom_item_id", _optional_int_field(it, "rom_item_id", -1, -1, 999), "Optional: borrow a Gen 5 ROM item icon (e.g. Big Mushroom = 87) instead of a bundled PNG. -1 = unset. Requires a data rebuild to take effect."))
	for key in ["stackable", "tradable", "sellable"]:
		if it.has(key):
			_form.add_child(_row(key, _bool_field(it, key, true)))


func _on_remove_selected() -> void:
	if _selected < 0 or _selected >= _raw.size():
		return
	_raw.remove_at(_selected)
	_selected = -1
	for c in _form.get_children():
		c.queue_free()
	_populate()
	dirty.emit()


func _on_add() -> void:
	var maxid := 1000
	for it in _raw:
		maxid = maxi(maxid, int(it.get("item_id", 0)))
	_raw.append({
		"item_id": maxid + 1, "name": "New Item",
		"item_type": str(_types[0]["value"]) if not _types.is_empty() else "material",
		"category": str(_cats[0]["value"]) if not _cats.is_empty() else "",
		"description": "", "cost": 0,
	})
	_populate()
	dirty.emit()
