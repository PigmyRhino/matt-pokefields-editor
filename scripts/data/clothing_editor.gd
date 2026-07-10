extends DatasetEditor
## clothing_data.json — { <slot>: [ { id_start, style, name, description, price, is_starter?, colors[],
## male?, female?, tradable?, sellable? }, ... ] }. One section per slot; colors edited as chips drawn
## from the union of colors already used. Optional bool keys are only shown when present (fidelity).

const _BOOL_TIPS := {
	"is_starter": "Available at character creation.",
	"male": "Offered to male characters.",
	"female": "Offered to female characters.",
	"tradable": "Can be traded between players.",
	"sellable": "Can be sold to shops.",
}

var _raw: Dictionary = {}
var _path := ""
var _colors: Array = []
var _cat: NamedCatalog


func load_data() -> void:
	_path = base_dir + "/clothing_data.json"
	_raw = JsonIO.load_file(_path)
	_colors = _color_entries()
	var hint := Label.new()
	hint.text = "Clothing per slot. Each color becomes a separate item id from id_start; previews come from the bundled icons."
	add_child(hint)
	# Only the array-valued top-level keys are slots (skips _comment etc.). The arrays are the same
	# objects as in _raw, so editing variants persists; slots are fixed, so key editing is disabled.
	var slots: Dictionary = {}
	for slot in _raw:
		if typeof(_raw[slot]) == TYPE_ARRAY:
			slots[str(slot)] = _raw[slot]
	_cat = NamedCatalog.new()
	_cat.editable_keys = false
	add_child(_cat)
	_cat.setup(slots, "", Callable(), _build_slot)


func save_data() -> bool:
	return JsonIO.save_file(_path, _raw)


func current_data() -> Variant:
	return _raw


func reveal(p: Problem) -> void:
	if p.locator is Dictionary and p.locator.has("slot"):
		_cat.reveal(str(p.locator["slot"]))


func _build_slot(slot: String, record: Variant, into: VBoxContainer) -> void:
	var variants: Array = record
	for i in variants.size():
		var v: Dictionary = variants[i]
		var trow := HBoxContainer.new()
		var tl := Label.new()
		tl.text = str(v.get("name", "?"))
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		trow.add_child(tl)
		trow.add_child(_icon_remove_button(func() -> void:
			variants.remove_at(i)
			_cat.refresh_detail()
			dirty.emit()))
		into.add_child(trow)
		var preview := _preview_row(slot, v)
		if preview != null:
			into.add_child(preview)
		into.add_child(_row("id_start", _int_field(v, "id_start", 0, 0, 100000), "Base item id; each color gets id_start + index."))
		into.add_child(_row("style", _str_field(v, "style"), "Internal style id (sprite folder name)."))
		into.add_child(_row("name", _str_field(v, "name"), "Display name."))
		into.add_child(_row("description", _str_field(v, "description"), "Shop/inventory description."))
		into.add_child(_row("price", _int_field(v, "price", 0, 0, 1000000), "Purchase price."))
		for key in ["is_starter", "male", "female", "tradable", "sellable"]:
			if v.has(key):
				into.add_child(_row(key, _bool_field(v, key, false), _BOOL_TIPS.get(key, "")))
		var chips := ChipSelect.new()
		chips.set_entries(_colors)
		chips.set_values((v.get("colors", []) as Array).duplicate())
		chips.changed.connect(func(values: Array) -> void:
			v["colors"] = values
			dirty.emit())
		into.add_child(_row("colors", chips, "Available color variants (one item id per color from id_start)."))
		into.add_child(HSeparator.new())
	var add := Button.new()
	add.text = "+ add %s variant" % slot
	add.pressed.connect(func() -> void:
		variants.append({ "id_start": 0, "style": "", "name": "New", "description": "", "price": 0, "colors": [] })
		_cat.refresh_detail()
		dirty.emit())
	into.add_child(add)


const _ICON_BASE := "res://assets/sprites/clothing/items"

static var _cloth_icons: Dictionary = {}


## A row of color thumbnails for a variant (from clothing/items icons), or null if none resolve.
func _preview_row(slot: String, v: Dictionary) -> HBoxContainer:
	var male := bool(v.get("male", true))
	var gender := "male" if male else "female"
	var prefix := "m" if male else "f"
	var style := str(v.get("style", ""))
	var cols: Array = v.get("colors", [])
	var shown: Array = cols if not cols.is_empty() else [""]
	var hb := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "preview"
	lbl.custom_minimum_size.x = 110
	hb.add_child(lbl)
	var any := false
	for col in shown:
		var fn := "%s_%s.png" % [prefix, style] if col == "" else "%s_%s_%s.png" % [prefix, style, col]
		var tex := _cloth_icon("%s/%s/%s/%s" % [_ICON_BASE, gender, slot, fn])
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.custom_minimum_size = Vector2(40, 40)
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.tooltip_text = str(col) if col != "" else style
			hb.add_child(tr)
			any = true
	return hb if any else null


func _cloth_icon(path: String) -> Texture2D:
	if not _cloth_icons.has(path):
		_cloth_icons[path] = load(path) if ResourceLoader.exists(path) else null
	return _cloth_icons[path]


## Union of color strings used across all slots (chip vocabulary).
func _color_entries() -> Array:
	var seen := {}
	var out: Array = []
	for slot in _raw:
		if typeof(_raw[slot]) != TYPE_ARRAY:
			continue
		for v in _raw[slot]:
			for c in (v as Dictionary).get("colors", []):
				if not seen.has(c):
					seen[c] = true
					out.append({ "value": c, "label": c })
	return out
