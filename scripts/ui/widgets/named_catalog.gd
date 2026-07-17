class_name NamedCatalog
extends VBoxContainer
## Master list for a dict of name -> record, shown the way the encounter editor works: a filter +
## a scrollable list of collapsible entries (no dropdown). Click an entry's ▸/▾ to expand its editor
## inline; rename in place via the header field; New / Delete per the toolbar / row. Records are
## mutated in place (the owning editor keeps its dict reference); rename rebuilds the dict contents in
## place so insertion order — and a clean save diff — is preserved.
##
## Set `editable_keys = false` before setup() for a fixed key set (e.g. clothing slots): no New /
## Rename / Delete, just a collapsible list.

signal dirty

## Set BEFORE setup() to allow/forbid New, Rename and Delete of keys.
var editable_keys := true

var _dict: Dictionary
var _prefix: String
var _make_new: Callable      ## () -> Variant — a fresh record for "New"
var _build_detail: Callable  ## (name: String, record: Variant, into: VBoxContainer) -> void

var _filter: LineEdit
var _list: VBoxContainer
var _expanded: Dictionary = {}  ## name -> bool (persisted across rebuilds)


func setup(dict: Dictionary, new_prefix: String, make_new: Callable, build_detail: Callable) -> void:
	_dict = dict
	_prefix = new_prefix
	_make_new = make_new
	_build_detail = build_detail

	var bar := HBoxContainer.new()
	_filter = LineEdit.new()
	_filter.placeholder_text = "filter…"
	_filter.size_flags_horizontal = SIZE_EXPAND_FILL
	_filter.text_changed.connect(func(_t: String) -> void: _rebuild())
	bar.add_child(_filter)
	if editable_keys:
		var newb := Button.new()
		newb.text = "+ new"
		newb.pressed.connect(_on_new)
		bar.add_child(newb)
	add_child(bar)

	_list = VBoxContainer.new()
	add_child(_list)
	_rebuild()


func refresh_detail() -> void:
	_rebuild()


## Surface and expand one entry (used by validation navigation). No-op if the key is gone.
func reveal(key: String) -> void:
	if not _dict.has(key):
		return
	_filter.text = key
	_expanded[key] = true
	_rebuild()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var q := _filter.text.strip_edges().to_lower()
	for name in _dict:
		var sname := str(name)
		if q != "" and not sname.to_lower().contains(q):
			continue
		var expanded := q != "" or bool(_expanded.get(sname, false))
		_list.add_child(_header(sname, expanded))
		if expanded:
			var body := VBoxContainer.new()
			_build_detail.call(sname, _dict[sname], body)
			var indent := MarginContainer.new()
			indent.add_theme_constant_override("margin_left", 16)
			indent.add_child(body)
			_list.add_child(indent)


func _header(name: String, expanded: bool) -> HBoxContainer:
	var hrow := HBoxContainer.new()
	var toggle := Button.new()
	toggle.text = "▾" if expanded else "▸"
	toggle.custom_minimum_size.x = 28
	toggle.pressed.connect(func() -> void:
		_expanded[name] = not bool(_expanded.get(name, false))
		_rebuild())
	hrow.add_child(toggle)
	if editable_keys:
		var name_edit := LineEdit.new()
		name_edit.text = name
		name_edit.size_flags_horizontal = SIZE_EXPAND_FILL
		name_edit.tooltip_text = "Rename this entry."
		var commit := func() -> void:
			var nn := name_edit.text.strip_edges()
			if nn != "" and nn != name and not _dict.has(nn):
				_rename_key_in_place(name, nn)
				_expanded[nn] = _expanded.get(name, false)
				_expanded.erase(name)
				dirty.emit()
				_rebuild()
		name_edit.text_submitted.connect(func(_t: String) -> void: commit.call())
		name_edit.focus_exited.connect(commit)
		hrow.add_child(name_edit)
		var delb := Button.new()
		delb.text = "✕"
		delb.tooltip_text = "Delete this entry."
		delb.pressed.connect(func() -> void:
			_dict.erase(name)
			_expanded.erase(name)
			dirty.emit()
			_rebuild())
		hrow.add_child(delb)
	else:
		var lbl := Label.new()
		lbl.text = name
		lbl.size_flags_horizontal = SIZE_EXPAND_FILL
		hrow.add_child(lbl)
	return hrow


func _on_new() -> void:
	var nm := _unique_name()
	_dict[nm] = _make_new.call()
	_expanded[nm] = true
	dirty.emit()
	_rebuild()


## Rename a key while preserving insertion order and the dict object's identity (the editor still
## holds the same reference): snapshot ordered pairs with the key swapped, clear, re-insert.
func _rename_key_in_place(old_key: String, new_key: String) -> void:
	var pairs: Array = []
	for k in _dict:
		pairs.append([new_key if k == old_key else k, _dict[k]])
	_dict.clear()
	for pair in pairs:
		_dict[pair[0]] = pair[1]


func _unique_name() -> String:
	var n := 1
	while _dict.has("%s_%d" % [_prefix, n]):
		n += 1
	return "%s_%d" % [_prefix, n]
