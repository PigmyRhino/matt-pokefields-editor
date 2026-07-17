class_name FlagBrowser
extends DatasetEditor
## Read-only Data-mode view of every string flag authored across maps, and where each is set, read, and
## used to gate. Derives the registry from FlagRegistry.scan() (saved overlays). It never dirties, so the
## shell's Save stays disabled and DataValidator has no "Flags" rules to run. Each usage row jumps to the
## offending object: it switches to Map mode, opens that map, and selects the interactable / zone.

var _registry: Dictionary = {}
var _filter := ""
var _expanded: Dictionary = {}     ## flag_key -> bool (open state, preserved across filter rebuilds)
var _list: VBoxContainer


func load_data() -> void:
	_registry = FlagRegistry.scan()
	for c in get_children():
		c.queue_free()

	var note := Label.new()
	note.text = "Flags are discovered from saved map overlays — set / cleared / read in scripted graphs, or gating a Gate zone. Re-save a map to refresh."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)

	var filter := LineEdit.new()
	filter.placeholder_text = "filter flags…"
	filter.text = _filter
	filter.text_changed.connect(func(t: String) -> void:
		_filter = t
		_rebuild_list())
	add_child(filter)

	_list = VBoxContainer.new()
	add_child(_list)
	_rebuild_list()


func _rebuild_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	var q := _filter.to_lower()
	var keys: Array = _registry.keys()
	keys.sort()
	var shown := 0
	for key in keys:
		if q != "" and not str(key).to_lower().contains(q):
			continue
		shown += 1
		_add_flag_row(str(key))
	if shown == 0:
		var empty := Label.new()
		empty.text = "(no flags authored yet)" if _registry.is_empty() else "(no flags match '%s')" % _filter
		_list.add_child(empty)


func _add_flag_row(key: String) -> void:
	var data: Dictionary = _registry[key]
	var writes: Array = data["writes"]
	var reads: Array = data["reads"]
	var gates: Array = data["gates"]
	var summary := "%s    (set %d · read %d · gate %d)" % [key, writes.size(), reads.size(), gates.size()]
	var expanded := bool(_expanded.get(key, false))
	var col := _collapsible(summary, expanded, func() -> void:
		_expanded[key] = not bool(_expanded.get(key, false))
		_rebuild_list())
	_list.add_child(col["header"])
	if expanded:
		var body: VBoxContainer = col["body"]
		_add_usage_section(body, "Set / cleared by", writes)
		_add_usage_section(body, "Read by", reads)
		_add_usage_section(body, "Gates", gates)
		_list.add_child(col["indent"])


func _add_usage_section(body: VBoxContainer, title: String, usages: Array) -> void:
	if usages.is_empty():
		return
	body.add_child(_section(title))
	for u in usages:
		body.add_child(_usage_row(u))


func _usage_row(u: Dictionary) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "%s · %s  (%s)" % [u["map_id"], u["object_id"], u["kind"]]
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(lbl)
	var jump := Button.new()
	jump.text = "Jump"
	jump.pressed.connect(func() -> void: _jump(u))
	hb.add_child(jump)
	return hb


## Hand off to Main (the mode shell), which swaps to the Map editor and selects the object.
func _jump(u: Dictionary) -> void:
	var main := get_tree().current_scene
	if main != null and main.has_method("open_map_object"):
		main.open_map_object(str(u["map_id"]), str(u["object_id"]), str(u["object_kind"]))
