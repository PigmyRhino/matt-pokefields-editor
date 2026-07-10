class_name SearchPicker
extends Button
## Searchable single-select dropdown over a Catalog entries array ([{value,label}]). Displays the
## entry's `label`, stores its `value`, and emits `value_changed(value)`. An empty value renders as
## `placeholder`; when `allow_none` the popup offers a "(none)" choice that clears the value.

signal value_changed(value: String)

var allow_none := true
## When set, the popup offers the typed filter text as a brand-new value (a ➕ row) whenever it matches
## no existing entry — so a picker can suggest known values yet still author a fresh one (e.g. flags).
var allow_custom := false
var placeholder := "(none)"
## If set, each entry's value V resolves to the icon "{icon_dir}/{V}.png" (shown in the popup list
## and on the closed button). Used to match item ids / sprite names to their art.
var icon_dir := ""
## If set, takes precedence over icon_dir: maps an entry value (String) -> Texture2D (or null). For
## sprites that aren't plain files — e.g. Pokémon box icons / poké-item icons from the ROM.
var icon_provider: Callable

static var _icons: Dictionary = {}

var _entries: Array = []
var _value := ""
var _popup: PopupPanel
var _filter: LineEdit
var _list: ItemList


func _ready() -> void:
	clip_text = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size.x = 150
	pressed.connect(_open)
	_build_popup()
	_refresh_text()


func set_entries(entries: Array) -> void:
	_entries = entries
	_refresh_text()


func set_value(value: String) -> void:
	_value = value
	_refresh_text()


func get_value() -> String:
	return _value


func _build_popup() -> void:
	_popup = PopupPanel.new()
	add_child(_popup)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(220, 300)
	_popup.add_child(vb)
	_filter = LineEdit.new()
	_filter.placeholder_text = "search…"
	_filter.text_changed.connect(func(_t: String) -> void: _populate())
	vb.add_child(_filter)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	vb.add_child(_list)


func _refresh_text() -> void:
	text = placeholder if _value == "" else Catalog.label_of(_entries, _value)
	icon = _icon_for(_value)


func _icon_for(value: String) -> Texture2D:
	if value == "":
		return null
	if icon_provider.is_valid():
		return icon_provider.call(value) as Texture2D
	if icon_dir == "":
		return null
	var path := "%s/%s.png" % [icon_dir, value]
	if not _icons.has(path):
		_icons[path] = load(path) if ResourceLoader.exists(path) else null
	return _icons[path]


func _open() -> void:
	_filter.text = ""
	_populate()
	_popup.popup(Rect2i(get_screen_position() + Vector2(0, size.y), Vector2i(int(maxf(size.x, 220)), 320)))
	_filter.grab_focus()


func _populate() -> void:
	_list.clear()
	var q := _filter.text.to_lower()
	if allow_none and q == "":
		_list.add_item(placeholder)
		_list.set_item_metadata(_list.item_count - 1, "")
	var exact := false
	for e in _entries:
		var label: String = e["label"]
		var value: String = e["value"]
		if q == "" or label.to_lower().contains(q) or value.to_lower().contains(q):
			var tex := _icon_for(value)
			if tex != null:
				_list.add_item(label, tex)
			else:
				_list.add_item(label)
			_list.set_item_metadata(_list.item_count - 1, value)
		if value.to_lower() == q:
			exact = true
	# Offer the typed text as a new value when it matches nothing (preserve its case in the metadata).
	if allow_custom and _filter.text != "" and not exact:
		_list.add_item("➕  \"%s\"" % _filter.text)
		_list.set_item_metadata(_list.item_count - 1, _filter.text)


func _on_selected(index: int) -> void:
	_value = str(_list.get_item_metadata(index))
	_refresh_text()
	_popup.hide()
	value_changed.emit(_value)
