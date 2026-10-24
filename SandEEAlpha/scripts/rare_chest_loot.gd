class_name RareChestLoot

# ── Rare dungeon chest loot ──────────────────────────────────────────
# A small weighted table shared by dungeon bonus rooms and rare cave caches.
# Every chest gets at least one Automatica-related material and one food, so
# the reward is a deliberate mix rather than another generic ore pile.
# All entries are existing ItemData resources; no placeholder ids are used.

const AUTOMATION_POOL: Array = [
	{"item": preload("res://resources/items/wire.tres"), "min": 2, "max": 4, "weight": 4},
	{"item": preload("res://resources/items/wireframe.tres"), "min": 1, "max": 2, "weight": 2},
	{"item": preload("res://resources/items/copper.tres"), "min": 2, "max": 4, "weight": 3},
	{"item": preload("res://resources/items/ironbar.tres"), "min": 1, "max": 2, "weight": 2},
	{"item": preload("res://resources/items/lua_core.tres"), "min": 1, "max": 1, "weight": 1},
]

const FOOD_POOL: Array = [
	{"item": preload("res://resources/items/bread.tres"), "min": 1, "max": 2, "weight": 3},
	{"item": preload("res://resources/items/cooked_allan.tres"), "min": 1, "max": 1, "weight": 2},
	{"item": preload("res://resources/items/cooked_charlie.tres"), "min": 1, "max": 1, "weight": 2},
	{"item": preload("res://resources/items/cooked_glep_glorp.tres"), "min": 1, "max": 1, "weight": 2},
	{"item": preload("res://resources/items/cooked_pimpim.tres"), "min": 1, "max": 1, "weight": 2},
	{"item": preload("res://resources/items/cooked_dog_meat.tres"), "min": 1, "max": 1, "weight": 1},
]

# Returns canonical inventory slots ({"data", "quantity"}) for a fresh chest.
# The optional third roll keeps contents varied without turning the cache into
# a full inventory; duplicate items are merged instead of taking extra slots.
static func roll(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	_add_pick(out, _pick(AUTOMATION_POOL, rng), rng)
	_add_pick(out, _pick(FOOD_POOL, rng), rng)
	if rng.randf() < 0.35:
		var pool: Array = AUTOMATION_POOL if rng.randf() < 0.5 else FOOD_POOL
		_add_pick(out, _pick(pool, rng), rng)
	return out

# Fills the existing ChestBlock slot array; rewards are only granted when the
# player later takes them through the ordinary chest UI.
static func fill(chest: Node, rng: RandomNumberGenerator) -> void:
	if chest == null or not is_instance_valid(chest):
		return
	var slots_ref: Variant = chest.get("slots")
	if not (slots_ref is Array):
		return
	var slots: Array = slots_ref as Array
	for i in range(slots.size()):
		slots[i] = null
	var rolled: Array = roll(rng)
	for i in range(mini(rolled.size(), slots.size())):
		slots[i] = rolled[i]
	if chest.has_method("notify_contents_changed"):
		chest.call("notify_contents_changed")

static func _add_pick(out: Array, entry: Dictionary, rng: RandomNumberGenerator) -> void:
	if entry.is_empty():
		return
	var data: ItemData = entry["item"] as ItemData
	if data == null:
		return
	var qty: int = rng.randi_range(int(entry.get("min", 1)), int(entry.get("max", 1)))
	for slot in out:
		if (slot as Dictionary).get("data") == data:
			(slot as Dictionary)["quantity"] = int((slot as Dictionary)["quantity"]) + qty
			return
	out.append({"data": data, "quantity": maxi(1, qty)})

static func _pick(pool: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total: int = 0
	for entry in pool:
		total += maxi(0, int((entry as Dictionary).get("weight", 0)))
	if total <= 0:
		return {}
	var roll: int = rng.randi_range(1, total)
	for entry in pool:
		roll -= maxi(0, int((entry as Dictionary).get("weight", 0)))
		if roll <= 0:
			return entry as Dictionary
	return pool[pool.size() - 1] as Dictionary
