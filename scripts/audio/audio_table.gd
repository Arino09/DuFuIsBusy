extends RefCounted
## One TSV maps semantic keys to Wwise names: a blank cell falls back to the parent key, "-" silences.

const SILENT := "-"

## key -> Wwise name; "" means "use the parent key".
var entries: Dictionary = {}
var errors: PackedStringArray = []
var _cache: Dictionary = {}

static func from_file(path: String) -> RefCounted:
	var table: RefCounted = new()
	if not FileAccess.file_exists(path):
		table.errors.append("%s: file not found (check the export include_filter)" % path)
		return table
	table.parse_bytes(FileAccess.get_file_as_bytes(path), path.get_file())
	return table

func parse_bytes(bytes: PackedByteArray, source: String) -> void:
	var text: Variant = decode(bytes)
	if text is String: parse(text, source)
	else: errors.append("%s: %s" % [source, text.error])

## Accepts UTF-8 (with or without BOM) and UTF-16LE (Excel "Unicode Text").
static func decode(bytes: PackedByteArray) -> Variant:
	if bytes.size() >= 2 and bytes[0] == 0xFF and bytes[1] == 0xFE:
		return bytes.slice(2).get_string_from_utf16()
	if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
		bytes = bytes.slice(3)
	# Validate first: Godot prints an engine error for malformed UTF-8 (e.g. GBK from Excel).
	if not _is_utf8(bytes): return {"error": "not UTF-8; re-save as \"UTF-8\" or \"Unicode Text\""}
	return bytes.get_string_from_utf8()

static func _is_utf8(bytes: PackedByteArray) -> bool:
	var i := 0
	while i < bytes.size():
		var b := bytes[i]
		var extra := 0 if b < 0x80 else 1 if b >> 5 == 0x06 else 2 if b >> 4 == 0x0E else 3 if b >> 3 == 0x1E else -1
		if extra < 0 or i + extra >= bytes.size(): return false
		for j in range(1, extra + 1):
			if bytes[i + j] >> 6 != 0x02: return false
		i += extra + 1
	return true

func parse(text: String, source: String = "audio_events.tsv") -> void:
	entries.clear()
	_cache.clear()
	var key_column := -1
	var event_column := -1
	var lines := text.split("\n")
	for index in lines.size():
		var line := lines[index].trim_suffix("\r")
		if line.strip_edges().is_empty() or line.strip_edges().begins_with("#"): continue
		var cells := line.split("\t")
		for c in cells.size(): cells[c] = _unquote(cells[c].strip_edges())
		if key_column < 0:
			key_column = _column(cells, "key")
			event_column = _column(cells, "event")
			if key_column < 0 or event_column < 0:
				errors.append("%s:%d header needs \"key\" and \"event\" columns" % [source, index + 1])
				return
			continue
		var key := _cell(cells, key_column)
		if key.is_empty(): continue
		if key.contains(" ") or key.begins_with(".") or key.ends_with("."):
			errors.append("%s:%d [key] invalid key \"%s\"" % [source, index + 1, key])
		elif entries.has(key):
			errors.append("%s:%d [key] duplicate key \"%s\"" % [source, index + 1, key])
		else:
			entries[key] = _cell(cells, event_column)

## Returns null when no row exists along the fallback chain, "" when silenced or unfilled.
func lookup(key: String) -> Variant:
	if _cache.has(key): return _cache[key]
	var result: Variant = null
	var current := key
	while true:
		if entries.has(current):
			var value: String = entries[current]
			if value == SILENT:
				result = ""
				break
			if not value.is_empty():
				result = value
				break
			result = ""
		var dot := current.rfind(".")
		if dot < 0: break
		current = current.left(dot)
	_cache[key] = result
	return result

static func _column(header: PackedStringArray, name: String) -> int:
	for i in header.size():
		if header[i].to_lower() == name: return i
	return -1

static func _cell(cells: PackedStringArray, column: int) -> String:
	return cells[column] if column < cells.size() else ""

static func _unquote(cell: String) -> String:
	if cell.length() >= 2 and cell.begins_with("\"") and cell.ends_with("\""):
		return cell.substr(1, cell.length() - 2).replace("\"\"", "\"")
	return cell
