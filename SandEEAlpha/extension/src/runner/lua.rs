use std::str::FromStr;

use anyhow::Result;
use godot::prelude::*;
use mlua::{IntoLua, Lua, Table, Value};
use strum::{AsRefStr, EnumString};

#[derive(AsRefStr, EnumString)]
pub enum LuaSignal {
    Generic,
    Print,
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
    lua: Lua,
    base: Base<Node>,
}

#[godot_api]
impl INode for LuaState {
    fn init(base: Base<Node>) -> Self {
        let mut res = Self {
            lua: Lua::new(),
            base,
        };
        res.prepare_lua_state()
            .expect("Preparing Lua state failed.");
        res
    }

    fn process(&mut self, _: f64) {
        let signals: Table = self
            .lua
            .globals()
            .get("signals")
            .expect("Failed to get signals");

        for signal in signals.sequence_values::<Table>() {
            let signal = signal.expect("Failed to load signal");
            let signal_type: String = signal.get("type").expect("Failed to get signal type");
            match LuaSignal::from_str(signal_type.as_str()).expect("Failed to convert signal type")
            {
                LuaSignal::Print => {
                    let print_string: String =
                        signal.get("arg").expect("Failed to get signal argument");
                    self.signals().print().emit(print_string);
                }
                _ => (),
            }
        }
        signals.clear().expect("Failed to clear signals");
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
    fn print(string: String);
    // Godot Functions
    #[func]
    fn run_code(&mut self, code: String) {
        if let Err(e) = self._run_code(code) {
            self.signals().code_failed().emit(e.to_string());
        } else {
            self.signals().code_executed().emit();
        }
    }

    fn _run_code(&mut self, code: String) -> Result<()> {
        self.lua.load(&code).exec()?;
        Ok(())
    }

    // Internals
    fn prepare_lua_state(&mut self) -> Result<()> {
        let globals = self.lua.globals();
        let signals = self.lua.create_table()?;
        globals.set("signals", signals)?;

        let print = self.lua.create_function(|state, string: String| {
            let signals: Table = state.globals().get("signals")?;
            signals.push(build_lua_signal(
                state,
                LuaSignal::Print,
                string.into_lua(state)?,
            )?)?;
            Ok(())
        })?;
        globals.set("print", print)?;

        Ok(())
    }
}
