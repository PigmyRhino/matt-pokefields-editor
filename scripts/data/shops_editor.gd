extends DatasetEditor
## shops/<region>/*.json — { "shop_id", "entries": [ { item (slug), min_badges, price?, stock? } ] }.
## All shop files load at once and show as a collapsible list (expand one to edit its items); Save
## writes every shop. price/stock are optional and absent stays absent. `shop_id` is editable and kept
## in sync with the filename — editing it renames the .json (same folder) on the next Save, via the
## shared filename-stem rename in DatasetEditor (same deferred-delete queue as removals).

var _shops: Dictionary = {}      # path -> raw dict
var _paths: Array[String] = []
var _list: VBoxContainer
var _expanded: Dictionary = {}   # path -> bool
var _deleted: Array[String] = [] # paths removed from the UI, deleted from disk on Save


func load_data() -> void:
	_paths = _find_jsons(base_dir + "/shops")
	for p in _paths:
		_shops[p] = JsonIO.load_file(p)
	var hint := Label.new()
	hint.text = "Shop inventories. Each item is gated by a minimum badge count."
	add_child(hint)
	var newb := Button.new()
	newb.text = "+ new shop (kanto)"
	newb.tooltip_text = "Create a new empty shop file under shops/kanto."
	newb.pressed.connect(_on_new_shop)
	add_child(newb)
	_list = VBoxContainer.new()
	add_child(_list)
	_rebuild()


func save_data() -> bool:
	var ok := true
	for p in _deleted:
		var abs := ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs):
			ok = DirAccess.remove_absolute(abs) == OK and ok
	_deleted.clear()
	for p in _shops:
		ok = JsonIO.save_file(p, _shops[p]) and ok
	return ok


func current_data() -> Variant:
	return _shops


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	for p in _paths:
		var raw: Dictionary = _shops[p]
		var title := "%s   (%d items)" % [p.get_file().get_basename(), (raw.get("entries", []) as Array).size()]
		var expanded: bool = _expanded.get(p, false)
		var sec := _collapsible(title, expanded, func() -> void:
			_expanded[p] = not bool(_expanded.get(p, false))
			_rebuild())
		var hrow := HBoxContainer.new()
		sec["header"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hrow.add_child(sec["header"])
		hrow.add_child(_icon_remove_button(func() -> void: _delete_shop(p)))
		_list.add_child(hrow)
		if expanded:
			_build_shop(raw, p, sec["body"])
			_list.add_child(sec["indent"])


## Remove a shop from the UI and queue its file for deletion on the next Save (Reload restores it).
func _delete_shop(path: String) -> void:
	_paths.erase(path)
	_shops.erase(path)
	_expanded.erase(path)
	_deleted.append(path)
	dirty.emit()
	_rebuild()


func _build_shop(raw: Dictionary, path: String, into: VBoxContainer) -> void:
	into.add_child(_row("shop_id", _shop_id_field(raw, path),
		"Unique id and filename stem. Editing this renames the shop's .json file (same folder) on the next Save."))
	if not raw.has("entries"):
		raw["entries"] = []
	var entries: Array = raw["entries"]
	for i in entries.size():
		var e: Dictionary = entries[i]
		var row := HBoxContainer.new()
		var pick := _item_slug_picker(e, "item", false)
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.tooltip_text = "Item for sale (by name)."
		row.add_child(pick)
		row.add_child(_mini("badges", _int_field(e, "min_badges", 0, 0, 8)))
		row.add_child(_icon_remove_button(func() -> void:
			entries.remove_at(i)
			_rebuild()
			dirty.emit()))
		into.add_child(row)
	var add := Button.new()
	add.text = "+ add item"
	add.pressed.connect(func() -> void:
		entries.append({ "item": "", "min_badges": 0 })
		_rebuild()
		dirty.emit())
	into.add_child(add)


## Editable shop_id field — kept in sync with the filename (see DatasetEditor._rename_stem_record).
func _shop_id_field(raw: Dictionary, path: String) -> LineEdit:
	return _stem_id_field(str(raw.get("shop_id", "")),
		func(le: LineEdit) -> void: _commit_shop_id(raw, path, le))


func _commit_shop_id(raw: Dictionary, old_path: String, le: LineEdit) -> void:
	# A prior commit (Enter) rebuilds the list and frees this field; ignore the trailing focus-out it fires.
	if not is_instance_valid(le):
		return
	var new_name := le.text.strip_edges()
	if new_name == str(raw.get("shop_id", "")):
		return
	if _rename_stem_record(old_path, new_name, "shop_id", _shops, _paths, _expanded, _deleted) == "":
		le.text = str(raw.get("shop_id", ""))  # illegal, or would clobber a file — revert
		return
	dirty.emit()
	_rebuild()


func _on_new_shop() -> void:
	var n := 1
	var dir := base_dir + "/shops/kanto"
	while FileAccess.file_exists("%s/new_shop_%d.json" % [dir, n]):
		n += 1
	var sid := "new_shop_%d" % n
	var path := "%s/%s.json" % [dir, sid]
	_shops[path] = { "shop_id": sid, "entries": [] }
	JsonIO.save_file(path, _shops[path])
	_paths.append(path)
	_expanded[path] = true
	_rebuild()
	dirty.emit()
