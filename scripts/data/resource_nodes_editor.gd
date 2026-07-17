extends DatasetEditor
## resource_nodes.json — { "groups": { <name>: <group> } }. One group at a time via NamedCatalog
## (New / Rename / Delete). Two shapes share the detail pane:
##  - def-backed skill groups: variants carry { id, ref→resource_defs, sprite, weight? }
##  - inline obstacle groups: have activation/script/respawn_ms; variants carry { id, sprite }
## Only keys present on a group/variant are shown, so unmodeled keys round-trip untouched. Variant
## `id` (the wire token + catalog primary key) is auto-assigned — never hand-typed.

const SPRITES_DIR := "res://assets/sprites/resource_nodes"

var _raw: Dictionary = {}
var _path := ""
var _defs: Array = []
var _sprites: Array = []
var _enc_groups: Array = []   ## live content/encounter_data.json groups (not the stale Catalog snapshot)
var _cat: NamedCatalog


func load_data() -> void:
	_path = base_dir + "/resource_nodes.json"
	_raw = JsonIO.load_file(_path)
	if not _raw.has("groups"):
		_raw["groups"] = {}
	_defs = _def_entries()
	_sprites = _sprite_entries(SPRITES_DIR)
	_enc_groups = ContentScan.encounter_groups()
	var hint := Label.new()
	hint.text = "Where resources surface. Def-backed groups carry `ref`; obstacle groups carry script/activation."
	add_child(hint)
	_cat = NamedCatalog.new()
	add_child(_cat)
	_cat.setup(_raw["groups"], "new_group", _make_group, _build_group)
	_cat.dirty.connect(func() -> void: dirty.emit())


func save_data() -> bool:
	return JsonIO.save_file(_path, _raw)


func current_data() -> Variant:
	return _raw.get("groups", {})


func reveal(p: Problem) -> void:
	_cat.reveal(p.context)


func _make_group() -> Variant:
	return { "anim": "Mining", "swing_duration_ms": 1000, "variants": [] }


func _build_group(_name: String, record: Variant, into: VBoxContainer) -> void:
	var g: Dictionary = record
	if g.has("anim"):
		into.add_child(_row("anim", _str_field(g, "anim"), "Player tool animation key (Axe, Mining, Harvest…)."))
	if g.has("script"):
		into.add_child(_row("script", _str_field(g, "script"), "Server script for obstacle groups (HmGate, Strength…)."))
	if g.has("break_sound"):
		into.add_child(_row("break_sound", _str_field(g, "break_sound"), "SFX played when the node breaks."))
	if g.has("swing_duration_ms"):
		into.add_child(_row("swing_duration_ms", _int_field(g, "swing_duration_ms", 1000, 0, 100000), "Swing animation length (ms)."))
	if g.has("respawn_ms"):
		into.add_child(_row("respawn_ms", _int_field(g, "respawn_ms", 60000, 0, 100000000), "Group-level respawn delay (obstacles)."))
	if g.has("area_pool"):
		into.add_child(_row("area_pool", _bool_field(g, "area_pool", false), "Bound by a Resource zone's MAX_ACTIVE cap."))
	if g.has("presence_based"):
		into.add_child(_row("presence_based", _bool_field(g, "presence_based", false), "Harvestable (no HP depletion)."))
	if g.has("default_encounter_group"):
		into.add_child(_row("encounter", _picker_field(_enc_groups, g, "default_encounter_group", false), "Encounter group triggered on activation (e.g. Rock Smash)."))
	if g.has("activation") and typeof(g["activation"]) == TYPE_DICTIONARY:
		into.add_child(_row("activation move_id", _int_field(g["activation"], "move_id", 0, 0, 100000), "Field-move id required to activate (Cut=15, Strength=70, Rock Smash=249)."))

	into.add_child(_section("variants"))
	var variants: Array = g.get("variants", [])
	var def_backed := not variants.is_empty() and (variants[0] as Dictionary).has("ref")
	for i in variants.size():
		var v: Dictionary = variants[i]
		var row := HBoxContainer.new()
		var sprite_icon := TextureRect.new()
		sprite_icon.custom_minimum_size = Vector2(24, 24)
		sprite_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite_icon.texture = _node_sprite(str(v.get("sprite", "")))
		row.add_child(sprite_icon)
		row.add_child(_mini("id", _readonly_int(int(v.get("id", 0)))))
		if v.has("ref"):
			var refp := _picker_field(_defs, v, "ref", false)
			refp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			refp.tooltip_text = "Resource def supplying this variant's economy."
			row.add_child(refp)
		var sp := _picker_field(_sprites, v, "sprite", false, SPRITES_DIR)
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.tooltip_text = "Node sprite (from assets/sprites/resource_nodes)."
		sp.value_changed.connect(func(val: String) -> void: sprite_icon.texture = _node_sprite(val))
		row.add_child(sp)
		if v.has("weight"):
			row.add_child(_mini("w", _int_field(v, "weight", 0, 0, 1000)))
		row.add_child(_icon_remove_button(func() -> void:
			variants.remove_at(i)
			_cat.refresh_detail()
			dirty.emit()))
		into.add_child(row)
	var add := Button.new()
	add.text = "+ add variant"
	add.pressed.connect(func() -> void:
		var nid := _next_variant_id()
		variants.append({ "id": nid, "ref": "", "sprite": "", "weight": 1 } if def_backed else { "id": nid, "sprite": "" })
		_cat.refresh_detail()
		dirty.emit())
	into.add_child(add)


## A read-only display of the auto-assigned variant id (it's a wire/catalog key, never hand-edited).
func _readonly_int(value: int) -> LineEdit:
	var le := LineEdit.new()
	le.text = str(value)
	le.editable = false
	le.custom_minimum_size.x = 56
	le.tooltip_text = "Auto-assigned variant id (wire token + catalog primary key)."
	return le


func _node_sprite(stem: String) -> Texture2D:
	if stem == "":
		return null
	var p := "%s/%s.png" % [SPRITES_DIR, stem]
	return load(p) if ResourceLoader.exists(p) else null


## Next free variant id across the whole catalog. The id is the wire token + catalog primary key, so
## it must be globally unique; max-in-file + 1 (floored at 6000) guarantees that without designer input.
func _next_variant_id() -> int:
	var maxid := 5999
	for gname in _raw["groups"]:
		for v in (_raw["groups"][gname] as Dictionary).get("variants", []):
			maxid = maxi(maxid, int((v as Dictionary).get("id", 0)))
	return maxid + 1


func _def_entries() -> Array:
	var rd: Variant = JsonIO.load_file(base_dir + "/resource_defs.json")
	var out: Array = []
	if typeof(rd) == TYPE_DICTIONARY and rd.has("defs"):
		for n in rd["defs"]:
			out.append({ "value": n, "label": n })
	return out
