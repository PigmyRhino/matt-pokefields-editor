extends DatasetEditor
## tool_categories.json — { "categories": { <cat>: { min_id, max_id, description, damage: { "<id>": [min,max] } } } }
## Tool tiers per skill + the per-tool swing damage used by the multi-swing gather loop. One category
## at a time via NamedCatalog (New / Rename / Delete); tools (damage rows) can be added and removed.

var _raw: Dictionary = {}
var _path := ""
var _cat: NamedCatalog


func load_data() -> void:
	_path = base_dir + "/tool_categories.json"
	_raw = JsonIO.load_file(_path)
	if not _raw.has("categories"):
		_raw["categories"] = {}
	var hint := Label.new()
	hint.text = "Tool tiers per skill and the per-tool swing damage used by the gather loop."
	add_child(hint)
	_cat = NamedCatalog.new()
	add_child(_cat)
	_cat.setup(_raw["categories"], "new_category", _make_category, _build_category)
	_cat.dirty.connect(func() -> void: dirty.emit())


func save_data() -> bool:
	return JsonIO.save_file(_path, _raw)


func current_data() -> Variant:
	return _raw.get("categories", {})


func reveal(p: Problem) -> void:
	_cat.reveal(p.context)


func _make_category() -> Variant:
	return { "min_id": 0, "max_id": 0, "description": "", "damage": {} }


func _build_category(_name: String, record: Variant, into: VBoxContainer) -> void:
	var c: Dictionary = record
	into.add_child(_row("Min id", _int_field(c, "min_id", 0, 0, 99999), "Lowest item id in this tool tier range."))
	into.add_child(_row("Max id", _int_field(c, "max_id", 0, 0, 99999), "Highest item id in this tool tier range."))
	into.add_child(_row("Description", _str_field(c, "description"), "Human note for this category."))
	into.add_child(_section("Per-tool swing damage [min, max] — higher tiers hit harder"))
	if not c.has("damage"):
		c["damage"] = {}
	var dmg: Dictionary = c["damage"]
	for id_key in dmg:
		var pair: Array = dmg[id_key]
		var row := HBoxContainer.new()
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(22, 22)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = GameData.get_item_icon(int(str(id_key)))
		row.add_child(icon)
		var name := Label.new()
		name.text = Catalog.label_of(Catalog.items, str(id_key))
		name.tooltip_text = "Item id %s" % id_key
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		row.add_child(_mini("min", _pair_spin(pair, 0)))
		row.add_child(_mini("max", _pair_spin(pair, 1)))
		row.add_child(_icon_remove_button(func() -> void:
			dmg.erase(id_key)
			_cat.refresh_detail()
			dirty.emit()))
		into.add_child(row)
	# One-click add: picking an item appends its damage row.
	var add_pick := _item_id_picker({}, "_unused", false)
	add_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_pick.value_changed.connect(func(v: String) -> void:
		if v != "" and not dmg.has(v):
			dmg[v] = [1, 1]
			_cat.refresh_detail()
			dirty.emit())
	into.add_child(_row("Add tool", add_pick, "Pick an item to add a swing-damage row for it."))


func _pair_spin(pair: Array, idx: int) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = 0
	sb.max_value = 999
	sb.custom_minimum_size.x = 60
	sb.value = int(pair[idx])
	sb.value_changed.connect(func(v: float) -> void:
		pair[idx] = int(v)
		dirty.emit())
	return sb
