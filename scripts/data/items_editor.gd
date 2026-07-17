extends DatasetEditor
## items.json — [ { item_id, name, item_type, category, description, cost, sell_price, stackable,
## tradable, sellable, rom_item_id?, move_id? }, ... ]: the owned catalog of every flat item
## (Pokémon + custom). Clothing (id >= 10000) is edited in the Clothing editor. Effects and use-target
## are NOT here — the generator derives them (effects stay Python-only in helpers/item_effects.py).
## Master-detail: filter + list, edit the selected item below. item_type/category options are the
## distinct values already in the file.

var _raw: Array = []
var _path := ""
var _types: Array = []
var _cats: Array = []
var _filter: LineEdit
var _list: ItemList
var _form: VBoxContainer
var _rows: Array[int] = []  # list row -> _raw index
var _selected := -1


func load_data() -> void:
	_path = base_dir + "/items.json"
	var loaded: Variant = JsonIO.load_file(_path)
	_raw = loaded if typeof(loaded) == TYPE_ARRAY else []
	_types = _distinct_entries(_raw, "item_type")
	_cats = _distinct_entries(_raw, "category")

	var hint := Label.new()
	hint.text = "All items (Pokémon + custom). Clothing → Clothing editor; effects live in the Python generator, not here."
	add_child(hint)
	_filter = LineEdit.new()
	_filter.placeholder_text = "filter by name or id…"
	_filter.text_changed.connect(func(_t: String) -> void: _populate())
	add_child(_filter)
	var bar := HBoxContainer.new()
	var add := Button.new()
	add.text = "+ add item"
	add.tooltip_text = "Append a new custom item with the next free id (>= 1000)."
	add.pressed.connect(_on_add)
	bar.add_child(add)
	var del := Button.new()
	del.text = "✕ remove selected"
	del.tooltip_text = "Delete the item currently shown below."
	del.pressed.connect(_on_remove_selected)
	bar.add_child(del)
	add_child(bar)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 520)
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
		var move := _machine_move_name(int(it.get("item_id", 0)))
		var label := "%s  (%s)" % [str(it.get("name", "?")), str(it.get("item_id", ""))]
		if move != "":
			label += " — %s" % move
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
	_form.add_child(_row("item_id", _int_field(it, "item_id", 0, 1, 99999), "Unique id (Pokémon < 1000, custom 1000-9999)."))
	_form.add_child(_row("name", _str_field(it, "name"), "Display name. Its slug keys effects + shop/trainer references."))
	_form.add_child(_row("item_type", _picker_field(_types, it, "item_type", false), "Classification — drives holdability, battle use, and target."))
	_form.add_child(_row("category", _picker_field(_cats, it, "category", false), "Display sub-category."))
	_form.add_child(_row("description", _str_field(it, "description"), "Inventory description."))
	_form.add_child(_row("cost", _int_field(it, "cost", 0, 0, 10000000), "Buy price (what a shop charges)."))
	_form.add_child(_row("sell_price", _int_field(it, "sell_price", 0, 0, 10000000), "Sell price (what a shop pays)."))
	_form.add_child(_row("stackable", _bool_field(it, "stackable", true), "Stacks into one bag slot."))
	_form.add_child(_row("tradable", _bool_field(it, "tradable", true), "Players can trade it."))
	_form.add_child(_row("sellable", _bool_field(it, "sellable", true), "Can be sold to shops."))
	_form.add_child(_row("rom_item_id", _optional_int_field(it, "rom_item_id", -1, -1, 999), "Optional: Gen 5 ROM icon index. -1 = bundled PNG. Data rebuild required."))
	_form.add_child(_row("move_id", _optional_int_field(it, "move_id", -1, -1, 99999), "TM/HM only: the move id it teaches. -1 = none."))


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
	var maxid := 999
	for it in _raw:
		var id := int(it.get("item_id", 0))
		if id >= 1000 and id < 10000:
			maxid = maxi(maxid, id)
	_raw.append({
		"item_id": maxid + 1, "name": "New Item",
		"item_type": "tool", "category": "",
		"description": "", "cost": 0, "sell_price": 0,
		"stackable": true, "tradable": true, "sellable": true,
	})
	_populate()
	dirty.emit()
