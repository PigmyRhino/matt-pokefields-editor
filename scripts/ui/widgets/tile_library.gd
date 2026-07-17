class_name TileLibrary
extends PanelContainer

signal tile_selected(atlas_coords: Vector2i, layer: int)

const TILE_SIZE := 16
const GROUND_COLOR := Color(0.4, 0.9, 0.4, 0.9)
const OVERLAY_COLOR := Color(1.0, 0.6, 0.3, 0.9)
const CLEAR_BTN_TEXT := "Clear"
const CATEGORY_FILE := "res://data/tile_categories.json"

var _atlas_image: Image
var _grid := Vector2i.ZERO
var _active_layer := 0  ## 0 = Ground, 1 = Overlay
var _ground_tile := Vector2i(-1, -1)
var _overlay_tile := Vector2i(-1, -1)
var _tiles: Dictionary = {}
var _atlas_tex: ImageTexture
var _scroll: ScrollContainer
var _grid_container: VBoxContainer
var _clear_btn: Button
var _ground_btn: Button
var _overlay_btn: Button
var _search_input: LineEdit
var _category_buttons: HBoxContainer
var _dragging := false
var _drag_offset := Vector2.ZERO
var _categories: Array = []
var _active_category := ""  ## Empty = show all
var _search_text := ""


func _ready() -> void:
	_build_ui()
	_load_categories()


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

	var search_container := HBoxContainer.new()
	search_container.add_theme_constant_override("separation", 4)
	vb.add_child(search_container)

	_search_input = LineEdit.new()
	_search_input.placeholder_text = "Search tiles..."
	_search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_input.text_changed.connect(_on_search_changed)
	search_container.add_child(_search_input)

	var search_clear := Button.new()
	search_clear.text = "X"
	search_clear.tooltip_text = "Clear search"
	search_clear.pressed.connect(func() -> void:
		_search_input.text = ""
		_on_search_changed("")
	)
	search_container.add_child(search_clear)

	_category_buttons = HBoxContainer.new()
	_category_buttons.add_theme_constant_override("separation", 2)
	vb.add_child(_category_buttons)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(_scroll)

	_grid_container = VBoxContainer.new()
	_grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid_container)


func _load_categories() -> void:
	if not FileAccess.file_exists(CATEGORY_FILE):
		push_warning("TileLibrary: missing %s" % CATEGORY_FILE)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATEGORY_FILE))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("categories"):
		push_warning("TileLibrary: invalid categories file")
		return
	_categories = parsed["categories"]
	_build_category_buttons()


func _build_category_buttons() -> void:
	for child in _category_buttons.get_children():
		child.queue_free()

	var all_btn := Button.new()
	all_btn.text = "All"
	all_btn.toggle_mode = true
	all_btn.button_pressed = _active_category == ""
	all_btn.pressed.connect(func() -> void:
		_active_category = ""
		_update_category_buttons()
		_rebuild_grid()
	)
	_category_buttons.add_child(all_btn)

	for cat in _categories:
		var btn := Button.new()
		btn.text = str(cat["name"])
		btn.toggle_mode = true
		btn.button_pressed = _active_category == str(cat["name"])
		btn.tooltip_text = str(cat.get("description", ""))
		btn.pressed.connect(func() -> void:
			_active_category = str(cat["name"])
			_update_category_buttons()
			_rebuild_grid()
		)
		_category_buttons.add_child(btn)

	_update_category_buttons()


func _update_category_buttons() -> void:
	for btn in _category_buttons.get_children():
		if btn is Button:
			var is_active: bool
			if btn.text == "All":
				is_active = _active_category == ""
			else:
				is_active = _active_category == btn.text
			btn.button_pressed = is_active
			if is_active:
				var style := StyleBoxFlat.new()
				style.bg_color = Color(0.3, 0.6, 0.9, 0.3)
				style.border_color = Color(0.3, 0.6, 0.9, 0.8)
				style.set_border_width_all(1)
				style.set_corner_radius_all(3)
				btn.add_theme_stylebox_override("normal", style)
				var pressed_style := style.duplicate()
				pressed_style.bg_color = Color(0.3, 0.6, 0.9, 0.5)
				btn.add_theme_stylebox_override("hover_pressed", pressed_style)
				btn.add_theme_stylebox_override("pressed", pressed_style)
			else:
				btn.remove_theme_stylebox_override("normal")
				btn.remove_theme_stylebox_override("hover_pressed")
				btn.remove_theme_stylebox_override("pressed")


func setup(atlas_image: Image, grid: Vector2i, _source_id: int) -> void:
	_atlas_image = atlas_image
	_grid = grid
	_ground_tile = Vector2i(-1, -1)
	_overlay_tile = Vector2i(-1, -1)
	_rebuild_grid()
	_update_tab_styles()


func _rebuild_grid() -> void:
	for child in _grid_container.get_children():
		child.queue_free()
	_tiles.clear()

	if _atlas_image == null or _grid.x <= 0 or _grid.y <= 0:
		return

	_atlas_tex = ImageTexture.create_from_image(_atlas_image)

	if _active_category == "" and _search_text == "":
		_build_flat_grid()
	else:
		_build_categorized_grid()


func _build_flat_grid() -> void:
	var grid := GridContainer.new()
	grid.columns = mini(_grid.x, 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_container.add_child(grid)

	for row in _grid.y:
		for col in _grid.x:
			var coords := Vector2i(col, row)
			var tile_rect := _create_tile_rect(coords)
			grid.add_child(tile_rect)
			_tiles[coords] = tile_rect

	_apply_all_highlights()


func _build_categorized_grid() -> void:
	var visible_tiles: Dictionary = {}

	if _active_category != "":
		for cat in _categories:
			if str(cat["name"]) == _active_category:
				var row_start: int = int(cat.get("row_start", 0))
				var row_end: int = int(cat.get("row_end", _grid.y - 1))
				for row in range(row_start, mini(row_end + 1, _grid.y)):
					for col in _grid.x:
						var coords := Vector2i(col, row)
						if _matches_search(coords):
							visible_tiles[coords] = true
				break
	else:
		for row in _grid.y:
			for col in _grid.x:
				var coords := Vector2i(col, row)
				if _matches_search(coords):
					visible_tiles[coords] = true

	if visible_tiles.is_empty():
		var lbl := Label.new()
		lbl.text = "No tiles match the filter"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_grid_container.add_child(lbl)
		return

	if _active_category != "":
		_build_category_section(_active_category, visible_tiles)
	else:
		var grid := GridContainer.new()
		grid.columns = mini(_grid.x, 12)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid_container.add_child(grid)

		for coords in visible_tiles:
			var tile_rect := _create_tile_rect(coords)
			grid.add_child(tile_rect)
			_tiles[coords] = tile_rect

	_apply_all_highlights()


func _build_category_section(category_name: String, visible_tiles: Dictionary) -> void:
	var header := Label.new()
	header.text = "  " + category_name
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_grid_container.add_child(header)

	var grid := GridContainer.new()
	grid.columns = mini(_grid.x, 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_container.add_child(grid)

	for coords in visible_tiles:
		var tile_rect := _create_tile_rect(coords)
		grid.add_child(tile_rect)
		_tiles[coords] = tile_rect


func _create_tile_rect(coords: Vector2i) -> TextureRect:
	var region := Rect2(coords.x * TILE_SIZE, coords.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	var atlas_tex := AtlasTexture.new()
	atlas_tex.atlas = _atlas_tex
	atlas_tex.region = region

	var tex_rect := TextureRect.new()
	tex_rect.texture = atlas_tex
	tex_rect.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	tex_rect.gui_input.connect(_on_tile_input.bind(coords))
	tex_rect.tooltip_text = "(%d, %d)" % [coords.x, coords.y]

	return tex_rect


func _matches_search(coords: Vector2i) -> bool:
	if _search_text.is_empty():
		return true
	var search_lower := _search_text.to_lower()
	var coord_text := "(%d, %d)" % [coords.x, coords.y]
	return coord_text.contains(search_lower) or str(coords.x).contains(search_lower) or str(coords.y).contains(search_lower)


func _on_search_changed(text: String) -> void:
	_search_text = text
	_rebuild_grid()


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
