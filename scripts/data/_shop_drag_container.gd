class_name ShopDragContainer
extends VBoxContainer
## Drag-and-drop reordering for shop entry rows. Uses manual mouse tracking on the grip
## area (left ~30 px of each row) so SearchPicker buttons don't swallow the drag gesture.

var _entries: Array = []
var _rebuild_cb: Callable
var _dirty_cb: Callable

var _dragging := false
var _drag_from := -1
var _drag_preview: PanelContainer


func _input(event: InputEvent) -> void:
	if not visible or not is_inside_tree():
		return
	if not get_global_rect().has_point(get_viewport().get_mouse_position()):
		if _dragging:
			_cancel_drag()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not _dragging:
			var row := _row_at(get_viewport().get_mouse_position())
			if row != null and _is_grip(row, get_viewport().get_mouse_position()):
				_start_drag(row.get_index())
		elif not event.pressed and _dragging:
			_finish_drag(get_viewport().get_mouse_position())
	elif event is InputEventMouseMotion and _dragging:
		_update_drag_preview(get_viewport().get_mouse_position())


func _start_drag(index: int) -> void:
	_dragging = true
	_drag_from = index
	_drag_preview = PanelContainer.new()
	var lbl := Label.new()
	lbl.text = "  %s  " % str(_entries[index].get("item", "?"))
	lbl.add_theme_font_size_override("font_size", 13)
	_drag_preview.add_child(lbl)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.35, 0.55)
	style.border_color = Color(0.5, 0.7, 1.0)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	_drag_preview.add_theme_stylebox_override("panel", style)
	add_child(_drag_preview)
	_update_drag_preview(get_viewport().get_mouse_position())


func _update_drag_preview(mouse_pos: Vector2) -> void:
	if _drag_preview == null:
		return
	var local := get_global_transform().affine_inverse() * mouse_pos
	_drag_preview.position = local + Vector2(8, -16)
	var row := _row_at(mouse_pos)
	for c in get_children():
		if c is HBoxContainer:
			if c == row and c.get_index() != _drag_from:
				c.modulate = Color(0.6, 1.0, 0.6, 1.0)
			else:
				c.modulate = Color.WHITE


func _finish_drag(mouse_pos: Vector2) -> void:
	var row := _row_at(mouse_pos)
	var drop_idx := -1
	if row != null:
		drop_idx = row.get_index()
	_cleanup_preview()
	_dragging = false
	if drop_idx < 0 or drop_idx == _drag_from:
		return
	var moved: Variant = _entries[_drag_from]
	_entries.remove_at(_drag_from)
	_entries.insert(drop_idx, moved)
	_rebuild_cb.call()
	_dirty_cb.call()


func _cancel_drag() -> void:
	_cleanup_preview()
	_dragging = false


func _cleanup_preview() -> void:
	if _drag_preview != null:
		_drag_preview.queue_free()
		_drag_preview = null
	for c in get_children():
		if c is HBoxContainer:
			c.modulate = Color.WHITE


func _row_at(mouse_pos: Vector2) -> Control:
	var local := get_global_transform().affine_inverse() * mouse_pos
	for c in get_children():
		if c is HBoxContainer:
			var r: Rect2 = c.get_rect()
			if local.y >= r.position.y and local.y <= r.position.y + r.size.y:
				return c
	return null


func _is_grip(row: HBoxContainer, mouse_pos: Vector2) -> bool:
	var local := get_global_transform().affine_inverse() * mouse_pos
	var row_rect := row.get_rect()
	return local.x - row_rect.position.x < 30.0
