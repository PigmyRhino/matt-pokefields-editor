class_name ProblemsPanel
extends PanelContainer
## A live list of validation Problems, errors first. Shared by the data and map shells. Clicking a row
## emits `problem_activated` so the shell can navigate to the offending object/record. The header is a
## toggle that collapses the list (the summary count stays visible when minimized). Built in code
## (no scene) like the rest of the editor's lightweight overlays.

signal problem_activated(problem: Problem)
## Emitted on collapse/expand so an anchored host (the map shell) can also shrink its width.
signal collapsed_changed(collapsed: bool)

const _ERR_COLOR := Color(1.0, 0.5, 0.5)
const _WARN_COLOR := Color(1.0, 0.82, 0.4)
const _OK_COLOR := Color(0.55, 0.85, 0.6)

var _header: Button
var _list: ItemList
var _problems: Array = []
var _collapsed := true  # starts minimized; the summary line stays visible


func _ready() -> void:
	_build()


func _build() -> void:
	if _list != null:
		return
	var vb := VBoxContainer.new()
	add_child(vb)
	_header = Button.new()
	_header.flat = true
	_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header.tooltip_text = "Click to collapse / expand the problems list."
	_header.pressed.connect(_toggle)
	vb.add_child(_header)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 150)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(_on_activated)
	_list.item_selected.connect(_on_activated)
	vb.add_child(_list)
	_apply_collapsed()
	_render()


## errors first, then warnings; both in discovery order.
func set_problems(problems: Array) -> void:
	_build()
	var errs: Array = []
	var warns: Array = []
	for p in problems:
		if (p as Problem).severity == Problem.Severity.ERROR:
			errs.append(p)
		else:
			warns.append(p)
	_problems = errs + warns
	_render()


## Set collapse state explicitly (shells call this to start minimized); emits collapsed_changed.
func set_collapsed(collapsed: bool) -> void:
	_build()
	_collapsed = collapsed
	_apply_collapsed()
	collapsed_changed.emit(_collapsed)
	_render()


func _toggle() -> void:
	set_collapsed(not _collapsed)


## Reflect the collapse state: hide the list and shrink to the header's width (the map shell also
## flips its anchor via collapsed_changed).
func _apply_collapsed() -> void:
	_list.visible = not _collapsed
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if _collapsed else Control.SIZE_EXPAND_FILL


func _render() -> void:
	if _list == null:
		return
	_list.clear()
	var ec := 0
	var wc := 0
	for p in _problems:
		var pr := p as Problem
		var is_err := pr.severity == Problem.Severity.ERROR
		var text := "%s  %s" % ["✕" if is_err else "⚠", pr.message]
		if pr.context != "":
			text += "   ·   %s" % pr.context
		_list.add_item(text)
		_list.set_item_custom_fg_color(_list.item_count - 1, _ERR_COLOR if is_err else _WARN_COLOR)
		_list.set_item_metadata(_list.item_count - 1, pr)
		if is_err:
			ec += 1
		else:
			wc += 1

	var arrow := "▸" if _collapsed else "▾"
	var color := _OK_COLOR
	if _problems.is_empty():
		_header.text = "%s  ✓ no problems" % arrow
	else:
		_header.text = "%s  %d error(s), %d warning(s)" % [arrow, ec, wc]
		color = _ERR_COLOR if ec > 0 else _WARN_COLOR
	_header.add_theme_color_override("font_color", color)
	_header.add_theme_color_override("font_focus_color", color)
	_header.add_theme_color_override("font_hover_color", color)
	_header.add_theme_color_override("font_pressed_color", color)


func _on_activated(index: int) -> void:
	var p: Variant = _list.get_item_metadata(index)
	if p is Problem:
		problem_activated.emit(p)
