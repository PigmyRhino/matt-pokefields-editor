class_name CollisionOverlay
extends Node2D
## Optional reference overlay: tints tiles by collision category (wall / water / ledge / grass) so the
## designer can see what they've painted, and outlines edited tiles. Draws only the camera's visible
## tile range (the stitched region is huge), redrawing each frame while enabled.

const BLOCKED := 0x07              # COLLISION | SWIM | OCEAN
const COLLISION := 1 << 0          # wall
const WATER := (1 << 1) | (1 << 2) # SWIM | OCEAN
const LEDGES := (1 << 10) | (1 << 11) | (1 << 12) | (1 << 13)
const GRASSES := (1 << 3) | (1 << 4)

const LEDGE_DOWN := 1 << 10
const LEDGE_LEFT := 1 << 11
const LEDGE_RIGHT := 1 << 12
const LEDGE_UP := 1 << 13

@onready var _tile: int = EditorConfig.TILE_SIZE

var _reader: GbaMapReader
var _size := Vector2i.ZERO
var _camera: Camera2D
var _enabled := false
var _overrides: Dictionary = {}  ## { Vector2i tile: flags } — authored collision overrides
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_process(false)


func setup(reader: GbaMapReader, size: Vector2i, camera: Camera2D) -> void:
	_reader = reader
	_size = size
	_camera = camera
	queue_redraw()


## The authored collision overrides ({ tile: flags }); the overlay tints effective (merged) collision
## and outlines edited tiles so the designer sees their changes.
func set_overrides(overrides: Dictionary) -> void:
	_overrides = overrides
	queue_redraw()


func set_enabled(on: bool) -> void:
	_enabled = on
	set_process(on)
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not _enabled or _reader == null or _camera == null:
		return
	var view := get_viewport_rect().size / _camera.zoom
	var top_left := _camera.position - view * 0.5
	var x0 := maxi(0, int(floor(top_left.x / _tile)))
	var y0 := maxi(0, int(floor(top_left.y / _tile)))
	var x1 := mini(_size.x, int(ceil((top_left.x + view.x) / _tile)) + 1)
	var y1 := mini(_size.y, int(ceil((top_left.y + view.y) / _tile)) + 1)
	var edited := Color(0.3, 0.9, 1.0, 0.9)
	for ty in range(y0, y1):
		for tx in range(x0, x1):
			var t := Vector2i(tx, ty)
			var flags: int = _overrides.get(t, _reader.stitched_tile_flags(tx, ty))  # effective collision
			var r := Rect2(tx * _tile, ty * _tile, _tile, _tile)
			var fill := _category_color(flags)
			if fill.a > 0.0:
				draw_rect(r, fill)
			var arrow := _ledge_arrow(flags)  # show ledge direction so the designer sees which way it jumps
			if arrow != "" and _font != null:
				draw_string(_font, Vector2(tx * _tile + 3, (ty + 1) * _tile - 3), arrow,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.1, 0.05, 0.0))
			if _overrides.has(t):  # outline designer-edited tiles
				draw_rect(r, edited, false, 1.0)


## Tint a tile by its dominant collision category (transparent = nothing to show). Ledges are checked
## before walls — a ledge carries COLLISION too, but should read as a ledge, not a plain wall.
func _category_color(flags: int) -> Color:
	if flags & LEDGES != 0:
		return Color(1.0, 0.8, 0.2, 0.35)   # ledge — amber
	if flags & COLLISION != 0:
		return Color(1.0, 0.2, 0.2, 0.35)   # wall — red
	if flags & WATER != 0:
		return Color(0.25, 0.5, 1.0, 0.35)  # surf/ocean — blue
	if flags & GRASSES != 0:
		return Color(0.3, 0.9, 0.4, 0.30)   # grass — green
	return Color(0, 0, 0, 0)


## The arrow glyph for a ledge tile's jump direction, or "" if it isn't a ledge.
func _ledge_arrow(flags: int) -> String:
	if flags & LEDGE_DOWN != 0:
		return "↓"
	if flags & LEDGE_LEFT != 0:
		return "←"
	if flags & LEDGE_RIGHT != 0:
		return "→"
	if flags & LEDGE_UP != 0:
		return "↑"
	return ""
