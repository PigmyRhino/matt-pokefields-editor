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
var _dropdown: PanelContainer
var _filter: LineEdit
var _list: ItemList


func _ready() -> void:
	clip_text = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size.x = 150
	pressed.connect(_open)
	_build_dropdown()
	_refresh_text()


func set_entries(entries: Array) -> void:
	_entries = entries
	_refresh_text()


func set_value(value: String) -> void:
	_value = value
	_refresh_text()


func get_value() -> String:
	return _value


func _build_dropdown() -> void:
	_dropdown = PanelContainer.new()
	_dropdown.visible = false
	_dropdown.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.16, 0.2)
	style.border_color = Color(0.4, 0.4, 0.45)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_dropdown.add_theme_stylebox_override("panel", style)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(220, 300)
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	_dropdown.add_child(vb)
	var hdr := HBoxContainer.new()
	var title := Label.new()
	title.text = "Select…"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(24, 24)
	close_btn.pressed.connect(_close)
	hdr.add_child(close_btn)
	vb.add_child(hdr)
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
	if _dropdown.visible:
		_close()
		return
	# Add to the same Window (viewport) this button lives in so coordinates match.
	var win: Window = get_window()
	if _dropdown.get_parent() != win:
		if _dropdown.get_parent():
			_dropdown.get_parent().remove_child(_dropdown)
		win.add_child(_dropdown)
	_filter.text = ""
	_populate()
	_dropdown.position = position + Vector2(0, size.y)
	_dropdown.custom_minimum_size = Vector2(int(maxf(size.x, 220)), 320)
	_dropdown.visible = true
	_filter.grab_focus()


func _close() -> void:
	_dropdown.visible = false


func _input(event: InputEvent) -> void:
	if not _dropdown.visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var rect := Rect2(_dropdown.global_position, _dropdown.size)
		if not rect.has_point(Vector2(event.position)):
			_close()


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
	_close()
	value_changed.emit(_value)
