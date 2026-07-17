class_name ValCheck
## Shared, pure helpers for the validators: building lookup sets from Catalog entry arrays, and the
## set of every known item id (Catalog snapshot ∪ the working-copy items.json, so freshly-authored
## custom ids resolve before the DB is regenerated). No UI, no model dependencies.

## The wire protocol prefixes every String field with a single byte (crates/protocol `write_string`),
## so a field's UTF-8 form must fit in 255 bytes. A longer string makes the game-server's `frame()`
## encoder panic on `StringTooLong` the instant it sends the packet carrying it — the game crashes.
## Validators flag anything past this as an ERROR so Save is blocked before the data reaches the server.
const MAX_WIRE_STRING_BYTES := 255


## UTF-8 byte length — what the wire's length prefix actually counts. NOT String.length() (which counts
## characters): one accented letter or emoji is several bytes, so a name that "looks" short can still
## overflow the prefix and crash the game.
static func utf8_len(s: String) -> int:
	return s.to_utf8_buffer().size()


## {value: true} from a Catalog entries array ([{value, label}]).
static func value_set(entries: Array) -> Dictionary:
	var s := {}
	for e in entries:
		s[str(e["value"])] = true
	return s


## {int item_id: true} for every item the server would know: the Catalog snapshot (PokeAPI + custom
## already in the DB) plus any items.json ids in the designer's working copy not yet regenerated.
static func item_id_set(content_dir: String) -> Dictionary:
	var s := {}
	for e in Catalog.items:
		s[int(str(e["value"]))] = true
	var custom: Variant = JsonIO.load_file(content_dir + "/items.json")
	if typeof(custom) == TYPE_ARRAY:
		for it in custom:
			if typeof(it) == TYPE_DICTIONARY and it.has("item_id"):
				s[int(it["item_id"])] = true
	return s


## {item slug: true} known to the server: Catalog item slugs ∪ slugified items.json names.
static func item_slug_set(content_dir: String) -> Dictionary:
	var s := value_set(Catalog.item_slugs)
	var custom: Variant = JsonIO.load_file(content_dir + "/items.json")
	if typeof(custom) == TYPE_ARRAY:
		for it in custom:
			if typeof(it) == TYPE_DICTIONARY and it.has("name"):
				s[GameData.slugify(str(it["name"]))] = true
	return s


## Loot-table names defined in the working copy (for ref checks from defs / encounters).
static func loot_table_names(content_dir: String) -> Dictionary:
	var s := {}
	var lt: Variant = JsonIO.load_file(content_dir + "/loot_tables.json")
	if typeof(lt) == TYPE_DICTIONARY and lt.has("tables"):
		for name in lt["tables"]:
			s[str(name)] = true
	return s
