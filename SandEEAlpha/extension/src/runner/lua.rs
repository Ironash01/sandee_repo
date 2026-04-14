use std::str::FromStr;

use anyhow::Result;
use godot::prelude::*;
use mlua::{IntoLua, Lua, Table, Value, Variadic};
use strum::{AsRefStr, EnumString};

use crate::runner::vector::LuaVector;

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

#[derive(GodotClass)]
#[class(base=Node)]
struct LuaState {
    #[var]
    code: GString,
    lua: Lua,
    /// Blocks Move signals until GDScript calls notify_move_done()
    waiting_for_move: bool,
    base: Base<Node>,
}

#[godot_api]
impl INode for LuaState {
    fn init(base: Base<Node>) -> Self {
        let mut res = Self {
            code: GString::new(),
            lua: Lua::new(),
            waiting_for_move: false,
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

        // Walk the queue from the end (index = length down to 1).
        // Print signals are emitted and removed immediately.
        // The first Move signal found is emitted only if we are not already
        // waiting for a previous move to complete; then we stop scanning.
        let len = signals.len().unwrap_or(0) as i64;
        let mut i = len;
        while i >= 1 {
            let signal: Table = match signals.get(i) {
                Ok(v) => v,
                Err(_) => { i -= 1; continue; }
            };
            let signal_type: String = match signal.get("type") {
                Ok(v) => v,
                Err(_) => { i -= 1; continue; }
            };

            match LuaSignal::from_str(&signal_type) {
                Ok(LuaSignal::Print) => {
                    // Remove by overwriting with the last element then popping
                    let last: Value = signals.get(len).unwrap_or(Value::Nil);
                    let _ = signals.set(i, last);
                    let _ = signals.pop::<Value>();
                    let text: String = signal.get("arg").unwrap_or_default();
                    self.signals().signal_print().emit(text);
                }
                Ok(LuaSignal::Move) => {
                    if !self.waiting_for_move {
                        let last: Value = signals.get(len).unwrap_or(Value::Nil);
                        let _ = signals.set(i, last);
                        let _ = signals.pop::<Value>();
                        let vector: LuaVector = signal.get("arg")
                            .expect("Failed to get move arg");
                        self.waiting_for_move = true;
                        self.signals()
                            .signal_move()
                            .emit(Vector2::new(vector.x, vector.y));
                    }
                    // Always stop after the first Move — one in-flight at a time
                    break;
                }
                _ => {}
            }
            i -= 1;
        }
    }
}

#[godot_api]
impl LuaState {
    #[signal]
    fn code_executed();
    #[signal]
    fn code_failed(error: String);
    #[signal]
    fn signal_print(string: String);
    #[signal]
    fn signal_move(vector: Vector2);

    /// Called by GDScript when the NPC finishes walking to its destination.
    /// Clears the gate so the next Move signal can be emitted.
    #[func]
    fn notify_move_done(&mut self) {
        self.waiting_for_move = false;
    }

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

    pub fn prepare_lua_state(&mut self) -> Result<()> {
        let globals = self.lua.globals();
        let signals = self.lua.create_table()?;
        globals.set("signals", signals)?;
        globals.set("vector", LuaVector::new(0., 0.))?;

        let print = self.lua.create_function(|state, args: Variadic<Value>| {
            let signals: Table = state.globals().get("signals")?;
            let parts: Vec<String> = args.iter().map(|x| x.to_string()).collect::<Result<_, _>>()?;
            signals.raw_insert(
                1,
                build_lua_signal(state, LuaSignal::Print, parts.join("\t").into_lua(state)?)?,
            )?;
            Ok(())
        })?;
        globals.set("print", print)?;

        let move_func = self.lua.create_function(|state, (x, y): (Value, Value)| {
            let signals: Table = state.globals().get("signals")?;
            let vector = match (x, y) {
                (Value::Integer(x), Value::Integer(y)) => Ok(LuaVector::new(x as f32, y as f32)),
                (Value::Number(x), Value::Number(y)) => Ok(LuaVector::new(x as f32, y as f32)),
                (Value::UserData(v), Value::Nil) => v.borrow::<LuaVector>().map(|d| *d),
                _ => Err(mlua::Error::RuntimeError("arguments not supported.".into())),
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
