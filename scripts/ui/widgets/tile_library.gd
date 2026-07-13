class_name TileLibrary
extends PanelContainer

signal tile_selected(atlas_coords: Vector2i, layer: int)

const TILE_SIZE := 16
const GROUND_COLOR := Color(0.4, 0.9, 0.4, 0.9)
const OVERLAY_COLOR := Color(1.0, 0.6, 0.3, 0.9)
const CLEAR_BTN_TEXT := "Clear"

var _atlas_image: Image
var _grid := Vector2i.ZERO
var _active_layer := 0  ## 0 = Ground, 1 = Overlay
var _ground_tile := Vector2i(-1, -1)
var _overlay_tile := Vector2i(-1, -1)
var _tiles: Dictionary = {}
var _atlas_tex: ImageTexture
var _grid_container: GridContainer
var _clear_btn: Button
var _ground_btn: Button
var _overlay_btn: Button
var _dragging := false
var _drag_offset := Vector2.ZERO


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	add_child(vb)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.gui_input.connect(_on_header_input)
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	vb.add_child(header)

	var lbl := Label.new()
	lbl.text = "Tiles"
	header.add_child(lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_clear_btn = Button.new()
	_clear_btn.text = CLEAR_BTN_TEXT
	_clear_btn.tooltip_text = "Deselect the current tile brush."
	_clear_btn.pressed.connect(clear_selection)
	header.add_child(_clear_btn)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	vb.add_child(tabs)

	_ground_btn = Button.new()
	_ground_btn.text = "Ground"
	_ground_btn.toggle_mode = true
	_ground_btn.button_pressed = true
	_ground_btn.pressed.connect(_on_tab_pressed.bind(0))
	tabs.add_child(_ground_btn)

	_overlay_btn = Button.new()
	_overlay_btn.text = "Overlay"
	_overlay_btn.toggle_mode = true
	_overlay_btn.pressed.connect(_on_tab_pressed.bind(1))
	tabs.add_child(_overlay_btn)

	_update_tab_styles()

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)

	_grid_container = GridContainer.new()
	_grid_container.columns = 12
	_grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid_container)


func setup(atlas_image: Image, grid: Vector2i, _source_id: int) -> void:
	_atlas_image = atlas_image
	_grid = grid
	_ground_tile = Vector2i(-1, -1)
	_overlay_tile = Vector2i(-1, -1)
	_build_grid()
	_update_tab_styles()


func _build_grid() -> void:
	for child in _grid_container.get_children():
		child.queue_free()
	_tiles.clear()

	if _atlas_image == null or _grid.x <= 0 or _grid.y <= 0:
		return

	_atlas_tex = ImageTexture.create_from_image(_atlas_image)

	for row in _grid.y:
		for col in _grid.x:
			var coords := Vector2i(col, row)
			var region := Rect2(col * TILE_SIZE, row * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			var atlas_tex := AtlasTexture.new()
			atlas_tex.atlas = _atlas_tex
			atlas_tex.region = region

			var tex_rect := TextureRect.new()
			tex_rect.texture = atlas_tex
			tex_rect.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tex_rect.gui_input.connect(_on_tile_input.bind(coords))
			tex_rect.tooltip_text = "(%d, %d)" % [col, row]

			_grid_container.add_child(tex_rect)
			_tiles[coords] = tex_rect

	_apply_all_highlights()


func _on_tab_pressed(layer: int) -> void:
	_active_layer = layer
	_ground_btn.button_pressed = layer == 0
	_overlay_btn.button_pressed = layer == 1
	_update_tab_styles()
	_refresh_highlight()


func _update_tab_styles() -> void:
	_apply_tab_style(_ground_btn, GROUND_COLOR, _active_layer == 0)
	_apply_tab_style(_overlay_btn, OVERLAY_COLOR, _active_layer == 1)


func _apply_tab_style(btn: Button, color: Color, active: bool) -> void:
	if active:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(color.r, color.g, color.b, 0.25)
		style.border_color = color
		style.set_border_width_all(1)
		style.set_corner_radius_all(3)
		btn.add_theme_stylebox_override("normal", style)
		var pressed_style := style.duplicate()
		pressed_style.bg_color = Color(color.r, color.g, color.b, 0.4)
		btn.add_theme_stylebox_override("hover_pressed", pressed_style)
		btn.add_theme_stylebox_override("pressed", pressed_style)
	else:
		btn.remove_theme_stylebox_override("normal")
		btn.remove_theme_stylebox_override("hover_pressed")
		btn.remove_theme_stylebox_override("pressed")


func _on_tile_input(event: InputEvent, coords: Vector2i) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var current := _ground_tile if _active_layer == 0 else _overlay_tile
		if current == coords:
			clear_selection()
		else:
			_select_tile(coords)


func _select_tile(coords: Vector2i) -> void:
	_refresh_highlight()
	if _active_layer == 0:
		_ground_tile = coords
	else:
		_overlay_tile = coords
	_apply_all_highlights()
	tile_selected.emit(coords, _active_layer)


func clear_selection() -> void:
	_refresh_highlight()
	if _active_layer == 0:
		_ground_tile = Vector2i(-1, -1)
	else:
		_overlay_tile = Vector2i(-1, -1)
	_apply_all_highlights()
	tile_selected.emit(Vector2i(-1, -1), _active_layer)


func clear_all() -> void:
	_ground_tile = Vector2i(-1, -1)
	_overlay_tile = Vector2i(-1, -1)
	_apply_all_highlights()
	tile_selected.emit(Vector2i(-1, -1), 0)
	tile_selected.emit(Vector2i(-1, -1), 1)


func get_ground_tile() -> Vector2i:
	return _ground_tile


func get_overlay_tile() -> Vector2i:
	return _overlay_tile


func _apply_all_highlights() -> void:
	_clear_all_highlights()
	_apply_highlight_for(_ground_tile, GROUND_COLOR)
	_apply_highlight_for(_overlay_tile, OVERLAY_COLOR)


func _clear_all_highlights() -> void:
	for tex_rect: TextureRect in _tiles.values():
		tex_rect.remove_theme_stylebox_override("panel")


func _apply_highlight_for(coords: Vector2i, color: Color) -> void:
	if not _tiles.has(coords):
		return
	var tex_rect: TextureRect = _tiles[coords]
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.15)
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	tex_rect.add_theme_stylebox_override("panel", style)


func _refresh_highlight() -> void:
	pass  # _apply_all_highlights handles everything


func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if _dragging:
				_drag_offset = mb.position
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		offset_left += mm.position.x - _drag_offset.x
		offset_top += mm.position.y - _drag_offset.y
		offset_right += mm.position.x - _drag_offset.x
		offset_bottom += mm.position.y - _drag_offset.y
