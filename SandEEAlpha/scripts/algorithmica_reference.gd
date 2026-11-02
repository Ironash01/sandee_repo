extends VBoxContainer

# ── Algorithmica reference tab ─────────────────────────────────────
# Reusable read-only Programming Encyclopedia used by both Algorithmica
# editors. It mirrors the inventory / Automatica encyclopedia: every accordion
# section from APIReference, with the function sections always fully listed and
# the language sections revealed by dungeon knowledge. No execution logic
# lives here.

var _open: Dictionary = {}

func _ready() -> void:
	_build()

func _build() -> void:
	var s: float = Global.ui_scale
	add_theme_constant_override("separation", int(10 * s))

	var header := Label.new()
	header.text = "PROGRAMMING ENCYCLOPEDIA"
	header.add_theme_font_size_override("font_size", Global.ui_font_size(14))
	header.add_theme_color_override("font_color", Color(0.80, 0.90, 1.00, 1.00))
	add_child(header)

	var hint := Label.new()
	hint.text = "Read-only reference. Switch to CODE to write a program."
	hint.add_theme_font_size_override("font_size", Global.ui_font_size(10))
	hint.add_theme_color_override("font_color", Color(0.55, 0.65, 0.85, 1.00))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	_divider(s)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", int(14 * s))
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for section in APIReference.encyclopedia_sections():
		var sec: Dictionary = section as Dictionary
		var always: bool = EncyclopediaData.section_is_always_available(sec)
		var start_open: bool = bool(sec.get("start_expanded", always))
		var entries: Array = EncyclopediaData.entries_for_section(sec)
		var acc := EncyclopediaSection.new()
		acc.setup(sec, s)
		acc.set_counts(entries.size(), EncyclopediaData.section_total(sec), always)
		if entries.is_empty():
			var none := Label.new()
			none.text = "Nothing discovered yet — clear dungeons to reveal entries here."
			none.add_theme_font_size_override("font_size", Global.ui_font_size(11))
			none.add_theme_color_override("font_color", Color(0.55, 0.65, 0.85, 1.00))
			none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			acc.body().add_child(none)
		else:
			for entry in entries:
				acc.add_entry(entry as Dictionary, s)
		list.add_child(acc)
		acc.set_expanded(bool(_open.get(acc.section_id, start_open)), false)
		acc.expansion_changed.connect(_on_section_expanded)

func _on_section_expanded(id: String, on: bool) -> void:
	_open[id] = on

func _divider(s: float) -> void:
	var line := ColorRect.new()
	line.color = Color(0.20, 0.28, 0.50, 1.00)
	line.custom_minimum_size = Vector2(0, maxi(1, int(round(1 * s))))
	add_child(line)
