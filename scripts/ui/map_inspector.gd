class_name MapInspector
extends PanelContainer
## Shown on the right when nothing on the map is selected: general, map-level properties (the overlay's
## `properties` block) plus read-only context. Mutates the bound MapDoc directly — no Save until the
## map editor's Save button, like every other inspector.

@onready var _title: Label = %MTitle
@onready var _info: Label = %MInfo
@onready var _dark: CheckButton = %MDark

var _doc: MapDoc = null
var _loading := false


func _ready() -> void:
	_dark.toggled.connect(_on_dark)
	visible = false


## Bind the map currently being edited. `map_id`/`info` are read-only context (id + dimensions).
func bind(doc: MapDoc, map_id := "", info := "") -> void:
	_doc = doc
	visible = doc != null
	if doc == null:
		return
	_loading = true
	_title.text = "Map — %s" % map_id
	_info.text = info
	_dark.set_pressed_no_signal(doc.is_dark)
	_loading = false


## is_dark is overlay-only (no ROM source), so this toggle is its only source.
func _on_dark(on: bool) -> void:
	if _loading or _doc == null:
		return
	_doc.is_dark = on
