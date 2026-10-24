extends Control

# Minecraft-style furnace smelting menu — input slot + fuel slot + progress
# arrow + output slot + Smelt button, plus the player's INVENTORY GRID along
# the bottom. Items can be dragged from the inventory grid OR the hotbar into
# the input/fuel slots (or loaded via the hotbar by clicking a slot). The
# output is PREVIEWED (ghosted) in the right slot as soon as a valid input is
# placed, BEFORE Smelt is clicked. Recipes come from SmeltingRecipe resources
# in RECIPE_DIR (input_item -> output_item, smelt_time seconds,
# fuel_level_required). Smelting needs FUEL: load a fuel item
# (ItemData.is_fuel) into the fuel slot; its fuel_level must be >= the
# recipe's fuel_level_required, and one fuel is consumed per smelt.
#
# Opens as a standalone UI owned by the placed furnace (like the crafting
# station) via open_as_station()/show_menu()/hide_menu() — it does NOT live
# in the player's inventory panel.

const RECIPE_DIR: String = "res://resources/recipes/"
const SLOT_SCENE  := preload("res://scenes/ui/InventorySlot.tscn")

const C_PANEL   := Color(0.08, 0.10, 0.20, 0.97)
const C_BORDER  := Color(0.45, 0.30, 0.18, 1.00)
const C_TITLE   := Color(1.00, 0.85, 0.60, 1.00)
const C_MUTED   := Color(0.75, 0.65, 0.45, 1.00)
const C_OVERLAY := Color(0.00, 0.00, 0.00, 0.60)
const C_SLOT    := Color(0.10, 0.09, 0.08, 1.00)
const C_ARROW   := Color(0.35, 0.28, 0.18, 1.00)
const C_FIRE    := Color(1.00, 0.55, 0.15, 1.00)
const C_SMELT   := Color(0.30, 0.18, 0.08, 1.00)
const C_SMELT_OK := Color(0.18, 0.45, 0.20, 1.00)

var _recipes: Array = []  # SmeltingRecipe

var _input_item:   ItemData = null
var _fuel_item:    ItemData = null
var _output_item:  ItemData = null
var _input_qty:    int      = 0
var _fuel_qty:     int      = 0
var _output_qty:   int      = 0
var _output_ready: bool     = false
var _smelting:     bool     = false
var _smelt_elapsed: float   = 0.0
var _smelt_total:   float   = 1.0

var _input_slot:   SmeltSlot = null
var _fuel_slot:    SmeltSlot = null
var _output_slot:  SmeltSlot = null
var _arrow_fill:   ColorRect = null
var _timer_label:  Label     = null
var _smelt_btn:    Button    = null
var _hint_label:   Label     = null
var _inv_slots:    Array    = []  # InventorySlot instances for the bottom grid

# The furnace object that owns the real smelting state + the programming host.
# Set by object_item.gd before the menu enters the tree. The menu is a VIEW:
# its _input_item/_fuel_item/_output_item are a cache synced from the object.
var furnace: Node = null
var _panel:  Control = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if furnace == null:
		# Fallback: the menu is a child of a CanvasLayer, child of the furnace.
		var p := get_parent()
		if p != null:
			p = p.get_parent()
			if p != null and p.has_method("smelt_request"):
				furnace = p
	_load_recipes()
	_build_ui()
	_build_programming_panel()
	if furnace != null and not furnace.is_connected("furnace_state_changed", _refresh_slots):
		furnace.connect("furnace_state_changed", _refresh_slots)
	Global.request_close_all_ui.connect(_close)
	Global.Inventory_updated.connect(_refresh_inv_grid)
	Global.Hotbar_updated.connect(_refresh_inv_grid)
	visible = false

# Poll the furnace's cook timer while the menu is open so the arrow fills and
# the countdown ticks (the cook itself lives on the furnace object, so it keeps
# running with the menu closed).
func _process(_delta: float) -> void:
	if not visible or furnace == null:
		return
	if bool(furnace.call("is_cooking")):
		if _arrow_fill != null:
			_arrow_fill.anchor_right = float(furnace.call("cook_progress"))
		if _timer_label != null:
			_timer_label.text = "Cooking... %.1fs" % float(furnace.call("cook_remaining"))

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("escape"):
		get_viewport().set_input_as_handled()
		if not Global.request_ui_back(event) and not Global.is_ui_back_event_consumed(event):
			dismiss_back()
	elif event.is_action_pressed("inventory") and not Global.is_text_input_focused():
		get_viewport().set_input_as_handled()
		hide_menu()

# ── Public: station-style open / close (mirrors crafting_menu) ─────
func open_as_station() -> void:
	show_menu()

func show_menu() -> void:
	visible = true
	Global.open_ui()
	Global.register_ui_back(self, Callable(self, "dismiss_back"))

# Escape/Back leaves Algorithmica first, then closes the furnace itself.
func dismiss_back() -> void:
	if _panel != null and _panel.visible:
		_panel.call("close")
	else:
		hide_menu()

func hide_menu() -> void:
	if not visible:
		return
	# A hidden parent must not leave the programming overlay's pause/back entry
	# behind (it is a child panel with its own open_ui()).
	if _panel != null and _panel.visible:
		_panel.call("close")
	visible = false
	Global.unregister_ui_back(self)
	Global.close_ui()

# ── Recipe loading ─────────────────────────────────────────────────
func _load_recipes() -> void:
	# ResourceLoader.list_directory (not DirAccess) so this survives export —
	# see Global._load_resource_dir for why DirAccess misses .tres there.
	for fname in ResourceLoader.list_directory(RECIPE_DIR):
		if fname.ends_with(".tres"):
			var r: Resource = load(RECIPE_DIR + fname)
			if r is SmeltingRecipe:
				_recipes.append(r)

func _recipe_for(item: ItemData) -> SmeltingRecipe:
	if item == null:
		return null
	for r in _recipes:
		var rec: SmeltingRecipe = r as SmeltingRecipe
		if rec.input_item == item or rec.input_item.resource_path == item.resource_path:
			return rec
	return null

func _fuel_ok(rec: SmeltingRecipe) -> bool:
	return rec != null and _fuel_item != null \
		and _fuel_item.is_fuel and _fuel_item.fuel_level >= rec.fuel_level_required

# ── UI ─────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var s: float = Global.ui_scale
	var arrow_px: int = int(60 * s)

	var overlay := ColorRect.new()
	overlay.color = C_OVERLAY
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(int(680 * s), int(420 * s))
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL; ps.border_color = C_BORDER
	ps.set_border_width_all(2); ps.set_corner_radius_all(8)
	ps.content_margin_left = int(24 * s); ps.content_margin_right = int(24 * s)
	ps.content_margin_top  = int(18 * s); ps.content_margin_bottom = int(18 * s)
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(12 * s))
	panel.add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", int(8 * s))
	vbox.add_child(header)
	var title := Label.new()
	title.text = "🔥  Furnace"
	title.add_theme_font_size_override("font_size", int(18 * s))
	title.add_theme_color_override("font_color", C_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var prog_btn := Button.new()
	prog_btn.text = "🐍 ALGORITHMICA"
	prog_btn.tooltip_text = "Algorithmica — write Python that automates this furnace and imbues regular items with automation."
	prog_btn.add_theme_font_size_override("font_size", int(12 * s))
	prog_btn.add_theme_color_override("font_color", C_TITLE)
	var pbs := StyleBoxFlat.new(); pbs.bg_color = C_SMELT; pbs.border_color = C_BORDER
	pbs.set_border_width_all(1); pbs.set_corner_radius_all(4)
	prog_btn.add_theme_stylebox_override("normal", pbs)
	prog_btn.add_theme_stylebox_override("hover", pbs)
	prog_btn.pressed.connect(_open_programming)
	header.add_child(prog_btn)

	var close_btn := Button.new()
	close_btn.text = "✕"; close_btn.flat = true
	close_btn.tooltip_text = "Close the furnace."
	close_btn.add_theme_color_override("font_color", C_MUTED)
	close_btn.add_theme_font_size_override("font_size", int(13 * s))
	close_btn.pressed.connect(hide_menu)
	header.add_child(close_btn)

	_divider(vbox, s)

	# Body: inventory grid on the LEFT, furnace controls on the RIGHT — the
	# grid gets room to breathe so every slot is clickable.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", int(20 * s))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	# ── Left: the player's inventory grid ──
	var inv_col := VBoxContainer.new()
	inv_col.add_theme_constant_override("separation", int(8 * s))
	inv_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(inv_col)

	var inv_lbl := Label.new()
	inv_lbl.text = "INVENTORY — drag items into the furnace slots"
	inv_lbl.add_theme_font_size_override("font_size", int(11 * s))
	inv_lbl.add_theme_color_override("font_color", C_MUTED)
	inv_col.add_child(inv_lbl)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", int(8 * s))
	grid.add_theme_constant_override("v_separation", int(8 * s))
	inv_col.add_child(grid)
	for idx in range(Global.INVENTORY_SIZE):
		var slot = SLOT_SCENE.instantiate()
		slot.slot_index = idx
		slot.slot_clicked.connect(func(i: int) -> void: _on_inv_slot_clicked(i))
		grid.add_child(slot)
		_inv_slots.append(slot)

	# ── Right: the furnace controls ──
	var fpanel := PanelContainer.new()
	fpanel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	fpanel.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
	var fps := StyleBoxFlat.new()
	fps.bg_color = C_SLOT; fps.border_color = C_BORDER
	fps.set_border_width_all(1); fps.set_corner_radius_all(6)
	fps.content_margin_left = int(14 * s); fps.content_margin_right = int(14 * s)
	fps.content_margin_top  = int(14 * s); fps.content_margin_bottom = int(14 * s)
	fpanel.add_theme_stylebox_override("panel", fps)
	body.add_child(fpanel)

	var fvbox := VBoxContainer.new()
	fvbox.add_theme_constant_override("separation", int(10 * s))
	fpanel.add_child(fvbox)

	# Furnace row: [input + fuel] | arrow | output
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(14 * s))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fvbox.add_child(row)

	# Left column: input slot on top, fuel slot below (Minecraft furnace layout).
	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", int(6 * s))
	row.add_child(left_col)

	_input_slot = SmeltSlot.new()
	_input_slot.accept_drops = true
	_input_slot.item_dropped.connect(_on_input_dropped)
	_input_slot.item_clicked.connect(_on_input_slot_clicked)
	left_col.add_child(_input_slot)

	_fuel_slot = SmeltSlot.new()
	_fuel_slot.accept_drops = true
	_fuel_slot.item_dropped.connect(_on_fuel_dropped)
	_fuel_slot.item_clicked.connect(_on_fuel_slot_clicked)
	left_col.add_child(_fuel_slot)

	# Arrow / progress
	var arrow := Control.new()
	arrow.custom_minimum_size = Vector2(arrow_px, int(56 * s))
	row.add_child(arrow)
	var arrow_bg := ColorRect.new()
	arrow_bg.color = C_ARROW
	arrow_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	arrow.add_child(arrow_bg)
	_arrow_fill = ColorRect.new()
	_arrow_fill.color = C_FIRE
	_arrow_fill.anchor_top = 0.0; _arrow_fill.anchor_bottom = 1.0
	_arrow_fill.anchor_left = 0.0; _arrow_fill.anchor_right = 0.0
	arrow.add_child(_arrow_fill)
	var arrow_lbl := Label.new()
	arrow_lbl.text = "→"
	arrow_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	arrow_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow_lbl.add_theme_font_size_override("font_size", int(18 * s))
	arrow_lbl.add_theme_color_override("font_color", C_TITLE)
	arrow_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.add_child(arrow_lbl)

	_output_slot = SmeltSlot.new()
	_output_slot.accept_drops = false
	_output_slot.item_clicked.connect(_on_output_slot_clicked)
	row.add_child(_output_slot)

	_timer_label = Label.new()
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", int(11 * s))
	_timer_label.add_theme_color_override("font_color", C_MUTED)
	fvbox.add_child(_timer_label)

	_smelt_btn = Button.new()
	_smelt_btn.text = "SMELT"
	_smelt_btn.custom_minimum_size = Vector2(int(140 * s), int(36 * s))
	_smelt_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_smelt_btn.add_theme_font_size_override("font_size", int(13 * s))
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_SMELT; sb.border_color = C_BORDER
	sb.set_border_width_all(1); sb.set_corner_radius_all(4)
	_smelt_btn.add_theme_stylebox_override("normal",  sb)
	_smelt_btn.add_theme_stylebox_override("hover",   sb)
	_smelt_btn.add_theme_stylebox_override("pressed", sb)
	_smelt_btn.add_theme_color_override("font_color", C_TITLE)
	_smelt_btn.pressed.connect(_on_smelt_pressed)
	fvbox.add_child(_smelt_btn)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", int(10 * s))
	_hint_label.add_theme_color_override("font_color", C_MUTED)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(int(200 * s), 0)
	fvbox.add_child(_hint_label)

	_hint("Drag ore into the top slot and fuel (wood/charcoal) into the bottom one.")
	_refresh_inv_grid()
	_refresh_slots()

# ── Drag-drop from inventory / hotbar ──────────────────────────────
# Both InventorySlot and hotbar slots emit the same drag payload shape:
#   {"item": <inventory dict>, "source": "inventory"|"hotbar", "from_index": int}
# Remove `count` of the dragged item from its source slot, leaving the rest of
# the stack intact (the furnace may only accept part of a big stack).
func _remove_from_source(data: Dictionary, count: int) -> bool:
	var source: String = str(data.get("source", ""))
	var from_idx: int = int(data.get("from_index", -1))
	var arr: Array = Global.Hotbar if source == "hotbar" else Global.Inventory
	if from_idx < 0 or from_idx >= arr.size() or arr[from_idx] == null or count <= 0:
		return false
	var remaining: int = int(arr[from_idx]["quantity"]) - count
	if remaining <= 0:
		arr[from_idx] = null
	else:
		arr[from_idx]["quantity"] = remaining
	if source == "hotbar":
		Global.Hotbar_updated.emit()
	else:
		Global.Inventory_updated.emit()
	return true

func _on_input_dropped(data: Dictionary) -> void:
	_load_slot_from(data, false)

func _on_fuel_dropped(data: Dictionary) -> void:
	_load_slot_from(data, true)

# Load the WHOLE dragged stack from a drag payload into the input
# (as_fuel=false) or fuel (as_fuel=true) slot, through the furnace's own
# validated API. Only what the furnace actually accepts is removed from the
# source slot, so a partial accept (or a full slot) never destroys items. The
# previous slot contents are returned to the inventory first so nothing is lost.
func _load_slot_from(data: Dictionary, as_fuel: bool) -> void:
	if furnace == null:
		return
	var item: Variant = data.get("item")
	if not (item is Dictionary):
		return
	var item_data: ItemData = (item as Dictionary)["data"] as ItemData
	if item_data == null:
		return
	if as_fuel:
		if not item_data.is_fuel:
			_hint("That's not fuel.")
			return
	elif _recipe_for(item_data) == null:
		_hint("That can't be smelted.")
		return
	# A DIFFERENT item already in the slot goes back to the inventory first.
	var cur: Dictionary = furnace.call("get_fuel_stack" if as_fuel else "get_input_stack")
	if not cur.is_empty() and (cur["data"] as ItemData) != item_data:
		_return_slot(as_fuel)
	var want: int = int((item as Dictionary).get("quantity", 1))
	var accepted: int = int(furnace.call("put_fuel" if as_fuel else "put_input", item_data, want))
	if accepted <= 0:
		_hint("The slot is full or holds a different item.")
		_refresh_slots()
		return
	# Remove ONLY what the furnace accepted; the rest stays in the inventory.
	_remove_from_source(data, accepted)
	_hint("Loaded %d × %s." % [accepted, item_data.item_name])
	_refresh_slots()

# Return a whole slot (input or fuel) to the player's inventory.
func _return_slot(as_fuel: bool) -> void:
	if furnace == null:
		return
	var stack: Dictionary = furnace.call("get_fuel_stack" if as_fuel else "get_input_stack")
	if stack.is_empty():
		return
	var d: ItemData = stack["data"]
	var removed: int = int(furnace.call("take_fuel" if as_fuel else "take_input", d, int(stack["quantity"])))
	if removed > 0:
		Global.add_item({"data": d, "quantity": removed})

# ── Interaction ────────────────────────────────────────────────────
func _on_input_slot_clicked() -> void:
	_slot_clicked(false)

func _on_fuel_slot_clicked() -> void:
	_slot_clicked(true)

# Click a slot: return its contents if full, else load one from the held item.
func _slot_clicked(as_fuel: bool) -> void:
	if furnace == null:
		return
	var stack: Dictionary = furnace.call("get_fuel_stack" if as_fuel else "get_input_stack")
	if not stack.is_empty():
		_return_slot(as_fuel)
		_hint("Removed.")
		_refresh_slots()
		return
	var held: Variant = Global.get_hotbar_item()
	if held == null:
		_hint("Nothing in your hand.")
		return
	var data: ItemData = (held as Dictionary)["data"] as ItemData
	if data == null:
		return
	if as_fuel:
		if not data.is_fuel:
			_hint("That's not fuel.")
			return
	elif _recipe_for(data) == null:
		_hint("That can't be smelted.")
		return
	if int(furnace.call("put_fuel" if as_fuel else "put_input", data, 1)) <= 0:
		_hint("The slot already holds a different item.")
		return
	Global.remove_item(data)
	_refresh_slots()

func _on_output_slot_clicked() -> void:
	if furnace == null:
		return
	if int(furnace.call("take_output")) > 0:
		_hint("Took the smelted item.")
		_refresh_slots()

func _on_inv_slot_clicked(idx: int) -> void:
	if idx < 0 or idx >= Global.Inventory.size():
		return
	var item: Variant = Global.Inventory[idx]
	if item == null:
		return
	var data: ItemData = (item as Dictionary)["data"] as ItemData
	if data != null:
		_hint("%s ×%d — drag it into a furnace slot, or click the furnace slot while holding it." % [data.item_name, item["quantity"]])

func _on_smelt_pressed() -> void:
	if furnace == null:
		return
	if not bool(furnace.call("begin_cook")):
		_hint("Cannot smelt — check input, fuel and output space.")
	_refresh_slots()

# ── Refresh ────────────────────────────────────────────────────────
func _refresh_slots() -> void:
	_sync_from_furnace()
	var cooking: bool = furnace != null and bool(furnace.call("is_cooking"))
	if _input_slot != null:
		_input_slot.set_icon(_input_item.icon if _input_item != null else null, 1.0, _input_item, _input_qty)
	if _fuel_slot != null:
		_fuel_slot.set_icon(_fuel_item.icon if _fuel_item != null else null, 1.0, _fuel_item, _fuel_qty)
	if _output_slot != null:
		if _output_item != null:
			_output_slot.set_icon(_output_item.icon, 1.0, _output_item, _output_qty)
		elif cooking:
			# Ghost-preview the item currently being cooked.
			var crec: SmeltingRecipe = _recipe_for(_input_item)
			var out: ItemData = crec.output_item if crec != null else null
			_output_slot.set_icon(out.icon if out != null else null, 0.4, out, 0)
		else:
			_output_slot.set_icon(null)
	if _smelt_btn != null:
		var rec: SmeltingRecipe = _recipe_for(_input_item)
		var can_smelt: bool = _input_item != null and _fuel_ok(rec) and not cooking
		_smelt_btn.disabled = not can_smelt
		_smelt_btn.text = "COOKING..." if cooking else "SMELT"
		var style := StyleBoxFlat.new()
		style.bg_color = C_SMELT_OK if can_smelt else C_SMELT
		style.border_color = C_BORDER
		style.set_border_width_all(1); style.set_corner_radius_all(4)
		_smelt_btn.add_theme_stylebox_override("normal",  style)
		_smelt_btn.add_theme_stylebox_override("hover",   style)
		_smelt_btn.add_theme_stylebox_override("pressed", style)
		_smelt_btn.add_theme_color_override("font_color",
			Color(0.8, 1.0, 0.8, 1.0) if can_smelt else C_TITLE)
	_update_arrow()
	_refresh_inv_grid()

# The menu is a VIEW — pull the real slot state from the furnace object, which
# owns it (so a program's loads/smelts show up here too).
func _sync_from_furnace() -> void:
	if furnace == null:
		return
	var i: Dictionary = furnace.call("get_input_stack")
	_input_item = i["data"] if not i.is_empty() else null
	_input_qty  = int(i["quantity"]) if not i.is_empty() else 0
	var f: Dictionary = furnace.call("get_fuel_stack")
	_fuel_item = f["data"] if not f.is_empty() else null
	_fuel_qty  = int(f["quantity"]) if not f.is_empty() else 0
	var o: Dictionary = furnace.call("get_output_stack")
	_output_item = o["data"] if not o.is_empty() else null
	_output_qty  = int(o["quantity"]) if not o.is_empty() else 0
	_output_ready = not o.is_empty()

func _refresh_inv_grid() -> void:
	for i in range(_inv_slots.size()):
		var slot: Control = _inv_slots[i]
		var item: Variant = Global.Inventory[i] if i < Global.Inventory.size() else null
		if item != null:
			slot.call("set_item", item)
		else:
			slot.call("set_empty")

func _update_arrow() -> void:
	var cooking: bool = furnace != null and bool(furnace.call("is_cooking"))
	# While cooking, _process drives the arrow fill + countdown instead.
	if _arrow_fill != null and not cooking:
		_arrow_fill.anchor_right = 1.0 if _output_ready else 0.0
	if _timer_label == null or cooking:
		return
	if _output_ready:
		_timer_label.text = "Ready"
	elif _input_item != null:
		var rec: SmeltingRecipe = _recipe_for(_input_item)
		var need: int = rec.fuel_level_required if rec != null else 1
		_timer_label.text = "Smeltable" if _fuel_ok(rec) else ("Needs fuel LV %d" % need)
	else:
		_timer_label.text = ""

func _hint(text: String) -> void:
	if _hint_label != null:
		_hint_label.text = text

func _build_programming_panel() -> void:
	if _panel != null:
		_panel.queue_free()
	_panel = load("res://scripts/furnace_programming_panel.gd").new() as Control
	add_child(_panel)

func _open_programming() -> void:
	if _panel != null:
		_panel.call("open", furnace)

func _close() -> void:
	hide_menu()

func _divider(parent: Node, s: float) -> void:
	var d := ColorRect.new()
	d.color = Color(0.45, 0.30, 0.18, 1.0)
	d.custom_minimum_size = Vector2(0, int(1 * s))
	parent.add_child(d)
