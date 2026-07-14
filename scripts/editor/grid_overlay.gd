class_name GridOverlay
extends Node2D
## Simple 16×16 tile-grid overlay toggled with F5. Draws only the camera's visible tile range for
## performance, like CollisionOverlay.

@onready var _tile: int = EditorConfig.TILE_SIZE

var _size := Vector2i.ZERO
var _camera: Camera2D
var _enabled := false


func setup(size: Vector2i, camera: Camera2D) -> void:
	_size = size
	_camera = camera
	queue_redraw()


func set_enabled(on: bool) -> void:
	_enabled = on
	queue_redraw()


func toggle() -> void:
	set_enabled(not _enabled)


func notify_camera_changed() -> void:
	if _enabled:
		queue_redraw()


func _draw() -> void:
	if not _enabled or _camera == null or _size == Vector2i.ZERO:
		return
	var view := get_viewport_rect().size / _camera.zoom
	var top_left := _camera.position - view * 0.5
	var x0 := maxi(0, int(floor(top_left.x / _tile)))
	var y0 := maxi(0, int(floor(top_left.y / _tile)))
	var x1 := mini(_size.x, int(ceil((top_left.x + view.x) / _tile)) + 1)
	var y1 := mini(_size.y, int(ceil((top_left.y + view.y) / _tile)) + 1)
	var color := Color(1.0, 1.0, 1.0, 0.15)
	for ty in range(y0, y1):
		for tx in range(x0, x1):
			var r := Rect2(tx * _tile, ty * _tile, _tile, _tile)
			draw_rect(r, color, false, 1.0)
