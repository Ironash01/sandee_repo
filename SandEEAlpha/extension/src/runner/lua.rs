use std::{str::FromStr, vec};

use anyhow::Result;
use godot::prelude::*;
use mlua::{IntoLua, Lua, Table, Value, Variadic};
use strum::{AsRefStr, EnumString};

use crate::runner::vector::LuaVector;

// signal enum for Lua and Godot
#[derive(AsRefStr, EnumString)]
pub enum LuaSignal {
    Generic,
    Print,
    Move,
    Attack,
    Interact,
    DropItem,
    // Building — place_item(dx, dy) relative, place_at(x, y) absolute tile.
    PlaceItem,
    PlaceAt,
    SelectBlock,
    Withdraw,
    // Crafting Station automation
    Craft,
    SetRecipe,
    TakeOutput,
    PutInput,
    InputSlot,
    // Robot extras: mine(name, radius) and rename(name).
    Mine,
    Rename,
    // combat_mode(on) — toggle the robot into/out of combat mode.
    CombatMode,
}

fn build_lua_signal(state: &Lua, signal_type: LuaSignal, arg: Value) -> Result<Table> {
    let signal = state.create_table()?;
    signal.set("type", signal_type.as_ref())?;
    signal.set("arg", arg)?;
    Ok(signal)
}

// Lua numbers may arrive as Integer or Number (Luau); coerce either to i32.
// Non-numeric values become 0 so a bad argument degrades gracefully instead of
// panicking the whole program.
fn as_int(v: Value) -> i32 {
    match v {
        Value::Integer(i) => i as i32,
        Value::Number(n) => n as i32,
        _ => 0,
    }
}

fn insert_signal<V: IntoLua>(
    signals: Table,
    state: &Lua,
    signal_type: LuaSignal,
    arg: V,
) -> Result<()> {
    signals.raw_insert(
        1,
        build_lua_signal(state, signal_type, arg.into_lua(state)?)?,
    )?;
    Ok(())
}

// Lua State node for automatica
#[derive(GodotClass)]
#[class(base=Node)]
struct LuaState {
    #[var]
    code: GString,
    #[var]
    held_item: GString,
    #[var]
    held_item_quantity: u32,
    // ── Crafting Station automation ────────────────────────────────
    // Mirror of the station's automation state, published to Lua as globals on
    // every run (the same pattern `held_item` already uses). The station sets
    // these before calling run_code().
    #[var]
    station_recipe: GString,
    #[var]
    station_output_item: GString,
    #[var]
    station_output_count: u32,
    lua: Lua,
    base: Base<Node>,
}

#[godot_api]
impl INode for LuaState {
    fn init(base: Base<Node>) -> Self {
        let mut res = Self {
            code: GString::new(),
            held_item: GString::new(),
            held_item_quantity: 0,
            station_recipe: GString::new(),
            station_output_item: GString::new(),
            station_output_count: 0,
            lua: Lua::new(),
            base,
        };
        res.prepare_lua_state()
            .expect("Preparing Lua state failed.");
        res
    }

    fn physics_process(&mut self, _: f64) {
        let signals: Table = self
            .lua
            .globals()
            .get("GODOT_PROP_signals")
            .expect("Failed to get signals");

        while !signals.is_empty() {
            let signal: Table = signals.pop().expect("Failed to load signal");
            let signal_type: String = signal.get("type").expect("Failed to get signal type");
            match LuaSignal::from_str(signal_type.as_str()).expect("Failed to convert signal type")
            {
                LuaSignal::Print => {
                    let print_string: String =
                        signal.get("arg").expect("Failed to get signal argument");
                    self.signals().signal_print().emit(print_string);
                }
                LuaSignal::Move => {
                    let vector: LuaVector =
                        signal.get("arg").expect("Failed to get signal argument");
                    self.signals()
                        .signal_move()
                        .emit(Vector2::new(vector.x, vector.y));
                }
                LuaSignal::Attack => {
                    self.signals().signal_attack().emit();
                }
                LuaSignal::Interact => {
                    self.signals().signal_interact().emit();
                }
                LuaSignal::DropItem => {
                    let quantity: u32 = signal.get("arg").expect("Failed to get signal argument");
                    let held_item = self.held_item.to_string();
                    self.signals().signal_drop_item().emit(held_item, quantity);

                    self.held_item_quantity = self.held_item_quantity.saturating_sub(quantity);
                    if self.held_item_quantity == 0 {
                        self.held_item = GString::new();
                    }
                }
                LuaSignal::PlaceItem => {
                    // arg is a table {dx, dy} (tile offset from the robot).
                    let arg: Table = signal.get("arg").expect("Failed to get signal argument");
                    let dx: i32 = arg.get("dx").unwrap_or(0);
                    let dy: i32 = arg.get("dy").unwrap_or(0);
                    self.signals().signal_place_item().emit(dx, dy);
                }
                LuaSignal::PlaceAt => {
                    // arg is a table {x, y} (absolute tile coords).
                    let arg: Table = signal.get("arg").expect("Failed to get signal argument");
                    let x: i32 = arg.get("x").unwrap_or(0);
                    let y: i32 = arg.get("y").unwrap_or(0);
                    self.signals().signal_place_at().emit(x, y);
                }
                LuaSignal::SelectBlock => {
                    let index: i32 = signal.get("arg").expect("Failed to get signal argument");
                    self.signals().signal_select_block().emit(index);
                }
                LuaSignal::Withdraw => {
                    // arg is a table {name, quantity}.
                    let arg: Table = signal.get("arg").expect("Failed to get signal argument");
                    let name: String = arg.get("name").unwrap_or_default();
                    let quantity: u32 = arg.get("quantity").unwrap_or(1);
                    self.signals().signal_withdraw().emit(name, quantity);
                }
                LuaSignal::Craft => {
                    let quantity: u32 = signal.get("arg").expect("Failed to get signal argument");
                    self.signals().signal_craft().emit(quantity);
                }
                LuaSignal::SetRecipe => {
                    let name: String = signal.get("arg").expect("Failed to get signal argument");
                    self.signals().signal_set_recipe().emit(name);
                }
                LuaSignal::TakeOutput => {
                    self.signals().signal_take_output().emit();
                }
                LuaSignal::PutInput => {
                    // arg is a table {name, quantity}.
                    let arg: Table = signal.get("arg").expect("Failed to get signal argument");
                    let name: String = arg.get("name").unwrap_or_default();
                    let quantity: u32 = arg.get("quantity").unwrap_or(1);
                    self.signals().signal_put_input().emit(name, quantity);
                }
                LuaSignal::InputSlot => {
                    let quantity: u32 = signal.get("arg").expect("Failed to get signal argument");
                    self.signals().signal_input_slot().emit(quantity);
                }
                LuaSignal::Mine => {
                    // arg is a table {name, radius}.
                    let arg: Table = signal.get("arg").expect("Failed to get signal argument");
                    let name: String = arg.get("name").unwrap_or_default();
                    let radius: i32 = arg.get("radius").unwrap_or(20);
                    self.signals().signal_mine().emit(name, radius);
                }
                LuaSignal::Rename => {
                    let name: String = signal.get("arg").expect("Failed to get signal argument");
                    self.signals().signal_rename().emit(name);
                }
                LuaSignal::CombatMode => {
                    let on: bool = signal.get("arg").unwrap_or(false);
                    self.signals().signal_combat_mode().emit(on);
                }
                _ => (),
            }
        }
    }
}

#[godot_api]
impl LuaState {
    // Godot Signals
    #[signal]
    fn code_executed();
    #[signal]
    fn code_failed(error: String);
    #[signal]
    fn signal_print(string: String);
    #[signal]
    fn signal_move(vector: Vector2);
    #[signal]
    fn signal_attack();
    #[signal]
    fn signal_interact();
    #[signal]
    fn signal_drop_item(held_item: String, quantity: u32);
    // Building: place_item(dx, dy) relative tile offset; place_at(x, y)
    // absolute tile coords; select_block(i) picks the 0-based build-palette
    // slot; withdraw(name, quantity) pulls items from the nearest chest.
    #[signal]
    fn signal_place_item(dx: i32, dy: i32);
    #[signal]
    fn signal_place_at(x: i32, y: i32);
    #[signal]
    fn signal_select_block(index: i32);
    #[signal]
    fn signal_withdraw(name: String, quantity: u32);
    // Crafting Station automation (driven by the craft/set_recipe/take_output
    // Lua globals registered in prepare_lua_state).
    #[signal]
    fn signal_craft(quantity: u32);
    #[signal]
    fn signal_set_recipe(name: String);
    #[signal]
    fn signal_take_output();
    // put_input(name, quantity) — move items into the station's input slot.
    #[signal]
    fn signal_put_input(name: String, quantity: u32);
    // input_slot(quantity) — feed N of the robot's SELECTED build-slot item
    // into the station's input slot (no name needed).
    #[signal]
    fn signal_input_slot(quantity: u32);
    // mine(name, radius) — mine every matching block within radius of the
    // robot, walking to each and storing the drops; rename(name) — set the
    // robot's displayed name.
    #[signal]
    fn signal_mine(name: String, radius: i32);
    #[signal]
    fn signal_rename(name: String);
    // combat_mode(on) — toggle combat mode (follow the player + attack with the
    // tool slot; see lua_npc.gd).
    #[signal]
    fn signal_combat_mode(on: bool);

    // Godot Functions
    #[func]
    fn run_code(&mut self) {
        if let Err(e) = self._run_code(self.code.to_string().as_ref()) {
            self.signals().code_failed().emit(e.to_string());
        } else {
            self.signals().code_executed().emit();
        }
    }

    // Every item display name — lets a GDScript editor offer a name popup.
    #[func]
    fn run_list_items(&mut self) -> PackedStringArray {
        let mut names: Vec<String> = crate::utils::item_names();
        names.sort();
        let mut out = PackedStringArray::new();
        for n in names {
            out.push(&GString::from(n.as_str()));
        }
        out
    }

    fn _run_code(&mut self, code: &str) -> Result<()> {
        // set variables that the user must be able to retrieve
        let globals = self.lua.globals();
        if self.held_item.is_empty() {
            globals.set("held_item", Value::Nil)?;
        } else {
            let held_item = self.lua.create_table()?;
            held_item.set("name", self.held_item.to_string())?;
            held_item.set("quantity", self.held_item_quantity)?;
            globals.set("held_item", held_item)?;
        }
        // Crafting Station state, so a program can read it (station_recipe,
        // station_output_item, station_output_count) — see LuaState's #[var]s.
        globals.set("station_recipe", self.station_recipe.to_string())?;
        globals.set("station_output_item", self.station_output_item.to_string())?;
        globals.set("station_output_count", self.station_output_count)?;
        self.lua.load(code).exec()?;
        Ok(())
    }

    // Internals
    fn prepare_lua_state(&mut self) -> Result<()> {
        let globals = self.lua.globals();
        let signals = self.lua.create_table()?;
        globals.set("GODOT_PROP_signals", signals)?;
        // vector singleton
        globals.set("vector", LuaVector::new(0., 0.))?;

        // signals as functions
        let print_func = self.lua.create_function(|state, args: Variadic<Value>| {
            let signals: Table = state.globals().get("GODOT_PROP_signals")?;
            let print_string: Vec<String> = args
                .iter()
                .map(|x| x.to_string())
                .collect::<Result<_, _>>()?;
            let print_string = print_string.join("\t");
            insert_signal(signals, state, LuaSignal::Print, print_string)?;
            Ok(())
        })?;
        globals.set("print", print_func)?;

        let move_func = self.lua.create_function(|state, (x, y): (Value, Value)| {
            let signals: Table = state.globals().get("GODOT_PROP_signals")?;
            let vector = match (x, y) {
                (Value::Integer(x), Value::Integer(y)) => Ok(LuaVector::new(x as f32, y as f32)),
                (Value::Number(x), Value::Number(y)) => Ok(LuaVector::new(x as f32, y as f32)),
                (Value::UserData(vector), Value::Nil) => {
                    vector.borrow::<LuaVector>().map(|data| *data)
                }
                (_, _) => Err(mlua::Error::RuntimeError(String::from(
                    "arguments not supported.",
                ))),
            }?;
            insert_signal(signals, state, LuaSignal::Move, vector)?;
            Ok(())
        })?;
        globals.set("move", move_func)?;

        let attack_func = self.lua.create_function(|state, ()| {
            let signals: Table = state.globals().get("GODOT_PROP_signals")?;
            insert_signal(signals, state, LuaSignal::Attack, Value::Nil)?;
            Ok(())
        })?;
        globals.set("attack", attack_func)?;

        let interact_func = self.lua.create_function(|state, ()| {
            let signals: Table = state.globals().get("GODOT_PROP_signals")?;
            insert_signal(signals, state, LuaSignal::Interact, Value::Nil)?;
            Ok(())
        })?;
        globals.set("interact", interact_func)?;

        let drop_item_func = self.lua.create_function(|state, quantity: Value| {
            let signals: Table = state.globals().get("GODOT_PROP_signals")?;
            let quantity = match quantity {
                Value::Integer(q) => q as u32,
                Value::Number(q) => q as u32,
                _ => 1,
            };
            insert_signal(signals, state, LuaSignal::DropItem, quantity)?;
            Ok(())
        })?;
        globals.set("drop_item", drop_item_func)?;

        let place_item_func = self.lua.create_function(|state, (dx, dy): (Value, Value)| {
            let signals: Table = state.globals().get("GODOT_PROP_signals")?;
            let dx = as_int(dx);
            let dy = as_int(dy);
            let arg = state.create_table()?;
            arg.set("dx", dx)?;
            arg.set("dy", dy)?;
            insert_signal(signals, state, LuaSignal::PlaceItem, arg)?;
            Ok(())
        })?;
        globals.set("place_item", place_item_func)?;

        // place_at(x, y) — absolute tile coordinates.
        let place_at_func = self.lua.create_function(|state, (x, y): (Value, Value)| {
            let signals: Table = state.globals().get("GODOT_PROP_signals")?;
            let x = as_int(x);
            let y = as_int(y);
            let arg = state.create_table()?;
            arg.set("x", x)?;
            arg.set("y", y)?;
            insert_signal(signals, state, LuaSignal::PlaceAt, arg)?;
            Ok(())
        })?;
        globals.set("place_at", place_at_func)?;

        // select_block(i) — pick the 0-based build-palette slot place_item uses.
        let select_block_func = self.lua.create_function(|state, index: Value| {
            let signals: Table = state.globals().get("GODOT_PROP_signals")?;
            insert_signal(signals, state, LuaSignal::SelectBlock, as_int(index))?;
            Ok(())
        })?;
        globals.set("select_block", select_block_func)?;

        // withdraw(name, quantity) — pull items from the nearest chest into the
        // robot's build palette / inventory.
        let withdraw_func = self.lua.create_function(|state, (name, quantity): (Value, Value)| {
            let signals: Table = state.globals().get("GODOT_PROP_signals")?;
            let name = match name {
                Value::String(s) => s.to_str()?.to_string(),
                _ => String::new(),
            };
            let quantity = match as_int(quantity) {
                q if q > 0 => q as u32,
                _ => 1,
            };
            let arg = state.create_table()?;
            arg.set("name", name)?;
            arg.set("quantity", quantity)?;
            insert_signal(signals, state, LuaSignal::Withdraw, arg)?;
            Ok(())
        })?;
        globals.set("withdraw", withdraw_func)?;

        // ── Crafting Station automation API ──────────────────────
        // craft(n)         → request n crafts of the station's selected recipe
        // set_recipe(name) → select a recipe by result item name
        // take_output()    → move the station's output into the player inventory
        // Station state is exposed as the globals set in _run_code().
        let craft_func = self.lua.create_function(|state, quantity: Value| {
            let signals: Table = state.globals().get("GODOT_PROP_signals")?;
            let quantity = match quantity {
                Value::Integer(q) => q.max(0) as u32,
                Value::Number(q) => q.max(0.0) as u32,
                _ => 1,
            };
            insert_signal(signals, state, LuaSignal::Craft, quantity)?;
            Ok(())
        })?;
        globals.set("craft", craft_func)?;

        let set_recipe_func = self.lua.create_function(|state, name: Value| {
            let signals: Table = state.globals().get("GODOT_PROP_signals")?;
            let name = match name {
                Value::String(s) => s.to_str()?.to_string(),
                _ => String::new(),
            };
            insert_signal(signals, state, LuaSignal::SetRecipe, name)?;
            Ok(())
        })?;
        globals.set("set_recipe", set_recipe_func)?;

        let take_output_func = self.lua.create_function(|state, ()| {
            let signals: Table = state.globals().get("GODOT_PROP_signals")?;
            insert_signal(signals, state, LuaSignal::TakeOutput, Value::Nil)?;
            Ok(())
        })?;
        globals.set("take_output", take_output_func)?;

        // put_input(name, quantity) — move items from the robot's inventory
        // into the nearest station's input slot for automatic crafting.
        let put_input_func = self.lua.create_function(|state, (name, quantity): (Value, Value)| {
            let signals: Table = state.globals().get("GODOT_PROP_signals")?;
            let name = match name {
                Value::String(s) => s.to_str()?.to_string(),
                _ => String::new(),
            };
            let quantity = match as_int(quantity) {
                q if q > 0 => q as u32,
                _ => 1,
            };
            let arg = state.create_table()?;
            arg.set("name", name)?;
            arg.set("quantity", quantity)?;
            insert_signal(signals, state, LuaSignal::PutInput, arg)?;
            Ok(())
        })?;
        globals.set("put_input", put_input_func)?;

        // input_slot(n) — feed n of the robot's selected build-slot item into
        // the nearest station's input slot.
        let input_slot_func = self.lua.create_function(|state, quantity: Value| {
            let signals: Table = state.globals().get("GODOT_PROP_signals")?;
            let quantity = match as_int(quantity) {
                q if q > 0 => q as u32,
                _ => 1,
            };
            insert_signal(signals, state, LuaSignal::InputSlot, quantity)?;
            Ok(())
        })?;
        globals.set("input_slot", input_slot_func)?;

        // mine(name, radius) — mine every block whose item name matches within
        // radius tiles of the robot (walks to each, stores the drops).
        let mine_func = self.lua.create_function(|state, (name, radius): (Value, Value)| {
            let signals: Table = state.globals().get("GODOT_PROP_signals")?;
            let name = match name {
                Value::String(s) => s.to_str()?.to_string(),
                _ => String::new(),
            };
            let radius = match as_int(radius) {
                r if r > 0 => r,
                _ => 20,
            };
            let arg = state.create_table()?;
            arg.set("name", name)?;
            arg.set("radius", radius)?;
            insert_signal(signals, state, LuaSignal::Mine, arg)?;
            Ok(())
        })?;
        globals.set("mine", mine_func)?;

        // rename(name) — set the robot's displayed name.
        let rename_func = self.lua.create_function(|state, name: Value| {
            let signals: Table = state.globals().get("GODOT_PROP_signals")?;
            let name = match name {
                Value::String(s) => s.to_str()?.to_string(),
                _ => String::new(),
            };
            insert_signal(signals, state, LuaSignal::Rename, name)?;
            Ok(())
        })?;
        globals.set("rename", rename_func)?;

        // combat_mode(on) — toggle combat mode (follow the player and attack
        // with the tool slot). See lua_npc.gd.
        let combat_mode_func = self.lua.create_function(|state, on: Value| {
            let signals: Table = state.globals().get("GODOT_PROP_signals")?;
            let on = match on {
                Value::Boolean(b) => b,
                _ => true,
            };
            insert_signal(signals, state, LuaSignal::CombatMode, on)?;
            Ok(())
        })?;
        globals.set("combat_mode", combat_mode_func)?;

        // list_items() — the item display names available in the game, offered
        // as an editor autocomplete popup inside name arguments.
        let list_items_func = self.lua.create_function(|_state, ()| {
            let mut names: Vec<String> = crate::utils::item_names();
            names.sort();
            Ok(names)
        })?;
        globals.set("list_items", list_items_func)?;

        self.restrict_globals()?;

        Ok(())
    }

    // Whitelist the Lua environment: remove every global that is not part of
    // the curated API (see APIReference). This drops os/io/debug/load/require/
    // package and anything else, so calling a disallowed function raises the
    // normal Lua "attempt to call a nil value" instead of running.
    fn restrict_globals(&mut self) -> Result<()> {
        const ALLOWED: &[&str] = &[
            // language built-ins
            "print", "type", "tostring", "tonumber", "pairs", "ipairs", "next",
            "select", "error", "assert", "pcall", "xpcall", "unpack",
            "rawget", "rawset", "rawequal", "rawlen", "setmetatable",
            "getmetatable", "math", "string", "table", "coroutine", "utf8",
            // game globals + custom API
            "vector", "held_item", "station_recipe", "station_output_item",
            "station_output_count", "GODOT_PROP_signals", "move", "attack",
            "interact", "drop_item", "place_item", "place_at", "select_block",
            "withdraw", "craft", "set_recipe", "take_output", "put_input",
            "input_slot", "mine", "rename", "combat_mode", "list_items",
        ];
        let globals = self.lua.globals();
        let mut remove: Vec<String> = Vec::new();
        for pair in globals.clone().pairs::<String, Value>() {
            let (key, _) = pair?;
            if !ALLOWED.contains(&key.as_str()) {
                remove.push(key);
            }
        }
        for key in remove {
            globals.set(key, Value::Nil)?;
        }
        Ok(())
    }
}
