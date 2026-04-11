use std::{str::FromStr, vec};

use anyhow::Result;
use godot::prelude::*;
use mlua::{IntoLua, Lua, Table, Value};
use strum::{AsRefStr, EnumString};

use crate::runner::vector::LuaVector;

// signal enum for Lua and Godot
#[derive(AsRefStr, EnumString)]
pub enum LuaSignal {
    Generic,
    Print,
    Move,
}

fn build_lua_signal(state: &Lua, signal_type: LuaSignal, arg: Value) -> Result<Table> {
    let signal = state.create_table()?;
    signal.set("type", signal_type.as_ref())?;
    signal.set("arg", arg)?;
    Ok(signal)
}

// Lua State node for automatica
#[derive(GodotClass)]
#[class(base=Node)]
struct LuaState {
    #[var]
    code: GString,
    lua: Lua,
    base: Base<Node>,
}

#[godot_api]
impl INode for LuaState {
    fn init(base: Base<Node>) -> Self {
        let mut res = Self {
            code: GString::new(),
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
        self.lua.load(code).exec()?;
        Ok(())
    }

    // Internals
    pub fn prepare_lua_state(&mut self) -> Result<()> {
        let globals = self.lua.globals();
        let signals = self.lua.create_table()?;
        globals.set("signals", signals)?;
        // vector singleton
        globals.set("vector", LuaVector::new(0., 0.))?;

        // signals as functions
        let print = self.lua.create_function(|state, string: String| {
            let signals: Table = state.globals().get("signals")?;
            signals.raw_insert(
                1,
                build_lua_signal(state, LuaSignal::Print, string.into_lua(state)?)?,
            )?;
            Ok(())
        })?;
        globals.set("print", print)?;

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
            signals.raw_insert(
                1,
                build_lua_signal(state, LuaSignal::Move, vector.into_lua(state)?)?,
            )?;
            Ok(())
        })?;
        globals.set("move", move_func)?;

        Ok(())
    }
}
