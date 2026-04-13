use std::{str::FromStr, vec};

use anyhow::Result;
use godot::prelude::*;
use mlua::{IntoLua, Lua, Scope, Table, Value, Variadic};
use strum::{AsRefStr, EnumString};

use crate::runner::vector::LuaVector;

// signal enum for Lua and Godot
#[derive(AsRefStr, EnumString)]
pub enum LuaSignal {
    Generic,
    Print,
    Move,
    PickUp,
    DropItem,
    PlaceItem,
}

fn build_lua_signal(state: &Lua, signal_type: LuaSignal, arg: Value) -> Result<Table> {
    let signal = state.create_table()?;
    signal.set("type", signal_type.as_ref())?;
    signal.set("arg", arg)?;
    Ok(signal)
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
            .get("signals")
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
                LuaSignal::PickUp => {
                    self.signals().signal_pick_up().emit();
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
                    let held_item = self.held_item.to_string();
                    self.signals().signal_place_item().emit(held_item);

                    self.held_item_quantity = self.held_item_quantity.saturating_sub(1);
                    if self.held_item_quantity == 0 {
                        self.held_item = GString::new();
                    }
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
    fn signal_pick_up();
    #[signal]
    fn signal_drop_item(held_item: String, quantity: u32);
    #[signal]
    fn signal_place_item(held_item: String);
    // Godot Functions
    #[func]
    fn run_code(&mut self) {
        if let Err(e) = self._run_code(self.code.to_string().as_ref()) {
            self.signals().code_failed().emit(e.to_string());
        } else {
            self.signals().code_executed().emit();
        }
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
        self.lua.load(code).exec()?;
        Ok(())
    }

    // Internals
    fn prepare_lua_state(&mut self) -> Result<()> {
        let globals = self.lua.globals();
        let signals = self.lua.create_table()?;
        globals.set("signals", signals)?;
        // vector singleton
        globals.set("vector", LuaVector::new(0., 0.))?;

        // signals as functions
        let print_func = self.lua.create_function(|state, args: Variadic<Value>| {
            let signals: Table = state.globals().get("signals")?;
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
            let signals: Table = state.globals().get("signals")?;
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

        let pick_up_func = self.lua.create_function(|state, ()| {
            let signals: Table = state.globals().get("signals")?;
            insert_signal(signals, state, LuaSignal::PickUp, Value::Nil)?;
            Ok(())
        })?;
        globals.set("pick_up", pick_up_func)?;

        let drop_item_func = self.lua.create_function(|state, quantity: Value| {
            let signals: Table = state.globals().get("signals")?;
            let quantity = match quantity {
                Value::Integer(q) => q as u32,
                Value::Number(q) => q as u32,
                _ => 1,
            };
            insert_signal(signals, state, LuaSignal::DropItem, quantity)?;
            Ok(())
        })?;
        globals.set("drop_item", drop_item_func)?;

        let place_item_func = self.lua.create_function(|state, ()| {
            let signals: Table = state.globals().get("signals")?;
            insert_signal(signals, state, LuaSignal::PlaceItem, Value::Nil)?;
            Ok(())
        })?;
        globals.set("place_item", place_item_func)?;

        Ok(())
    }
}
