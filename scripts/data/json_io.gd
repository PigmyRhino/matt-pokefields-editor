class_name JsonIO
## Round-trip-faithful JSON(C) load/save for the content working copy. Editors mutate the parsed
## structure in place, so `_comment` fields and any keys the editor doesn't model are preserved.
##
## Some files (shops) are JSONC: a leading block of `//` comment lines before the JSON. Strict JSON
## parsers reject those, so we strip full-line `//` comments before parsing (matching the server's
## tolerant loader) and remember the leading comment block per path to re-emit it on save.
##
## stringify emits whole-number floats as ints (Godot's JSON parser widens ints to float on load) and
## uses 2-space indent + stable key order, so the owner's manual diff against main stays clean.

const INDENT := "  "

static var _prefixes: Dictionary = {}  # path -> leading comment block (preserved across save)


static func load_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("JsonIO: missing %s" % path)
		return null
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var prefix: Array[String] = []
	var i := 0
	while i < lines.size():  # capture the leading comment/blank block verbatim
		var t := lines[i].strip_edges()
		if t == "" or t.begins_with("//"):
			prefix.append(lines[i])
			i += 1
		else:
			break
	_prefixes[path] = "\n".join(prefix) + "\n" if not prefix.is_empty() else ""
	var body: Array[String] = []
	while i < lines.size():  # drop any further full-line // comments before parsing
		if not lines[i].strip_edges().begins_with("//"):
			body.append(lines[i])
		i += 1
	var parsed: Variant = JSON.parse_string("\n".join(body))
	if parsed == null:
		push_error("JsonIO: parse failed %s" % path)
	return parsed


static func save_file(path: String, value: Variant) -> bool:
	var target := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		push_error("JsonIO: cannot write %s (%d)" % [target, FileAccess.get_open_error()])
		return false
	f.store_string(str(_prefixes.get(path, "")) + stringify(value, "") + "\n")
	f.close()
	return true


static func stringify(value: Variant, indent: String) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var d: Dictionary = value
			if d.is_empty():
				return "{}"
			var inner := indent + INDENT
			var parts: Array[String] = []
			for k in d:
				parts.append("%s%s: %s" % [inner, _quote(str(k)), stringify(d[k], inner)])
			return "{\n" + ",\n".join(parts) + "\n" + indent + "}"
		TYPE_ARRAY:
			var a: Array = value
			if a.is_empty():
				return "[]"
			var inner := indent + INDENT
			var parts: Array[String] = []
			for e in a:
				parts.append(inner + stringify(e, inner))
			return "[\n" + ",\n".join(parts) + "\n" + indent + "]"
		TYPE_STRING:
			return _quote(value)
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_NIL:
			return "null"
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			var fv: float = value
			if fv == floor(fv) and absf(fv) < 1e15:
				return str(int(fv))
			return str(fv)
		_:
			return _quote(str(value))


static func _quote(s: String) -> String:
	return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") \
		.replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t") + "\""
