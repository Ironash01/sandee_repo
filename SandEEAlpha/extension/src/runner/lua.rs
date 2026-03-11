use crate::{from_usize_enum, utils::print_as_godot_error};
use anyhow::Result;
use godot::prelude::*;
use mlua::{FromLua, IntoLua, Lua, MetaMethod, Table, UserData, Value};
use std::{
    ops::Add,
    sync::mpsc::{Receiver, Sender, TryRecvError, channel},
    thread::{self, JoinHandle},
};
use strum::AsRefStr;

from_usize_enum! {
    pub enum LuaSignal {
        Unknown = 0,
        Print,
        Move,
    }
}

pub enum LuaRequest {
    RunLuaCode(String),
}

#[derive(AsRefStr)]
pub enum LuaResponse {
    #[strum(serialize = "codeRan")]
    CodeResult(Result<Table>),
}

#[derive(Clone, Copy)]
struct Vector2 {
    x: i32,
    y: i32,
}

impl Add for Vector2 {
    type Output = Self;

    #[inline]
    fn add(self, rhs: Self) -> Self::Output {
        Self {
            x: self.x + rhs.x,
            y: self.y + rhs.y,
        }
    }
}

impl FromLua for Vector2 {
    fn from_lua(value: Value, _: &Lua) -> mlua::Result<Self> {
        match value {
            Value::UserData(ud) => Ok(*ud.borrow()?),
            _ => unreachable!(),
        }
    }
}

impl UserData for Vector2 {
    fn add_methods<M: mlua::UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method("magnitude", |_, vec, ()| {
            Ok(((vec.x * vec.x + vec.y * vec.y) as f32).sqrt())
        });

        methods.add_meta_function(MetaMethod::Add, |_, (this, other): (Vector2, Vector2)| {
            Ok(this + other)
        });
    }
}

pub enum LuaEvent {
    Request(LuaRequest),
    Response(LuaResponse),
}

pub struct LuaTask {
    lua: Lua,
    lua_sender: LuaSender,
    node_sender: LuaSender,
}

pub type LuaSender = Sender<LuaEvent>;

impl LuaTask {
    pub fn launch_thread(node_sender: LuaSender) -> (JoinHandle<()>, LuaSender) {
        let (lua_sender, lua_receiver) = channel();

        let scoped_lua_sender = lua_sender.clone();
        let task = thread::spawn(move || {
            let mut lua = Self::new(scoped_lua_sender, node_sender);

            loop {
                let next = match lua_receiver.try_recv() {
                    Err(_) => continue,
                    Ok(e) => e,
                };

                match next {
                    LuaEvent::Request(req) => lua.handle_request(req),
                    LuaEvent::Response(res) => lua.handle_response(res),
                }
            }
        });

        return (task, lua_sender);
    }

    fn new(lua_sender: LuaSender, node_sender: LuaSender) -> Self {
        let mut s = Self {
            lua: Lua::new(),
            lua_sender,
            node_sender,
        };
        s.setup_lua_state().expect("fuck u");
        s
    }

    fn setup_lua_state(&mut self) -> Result<()> {
        let globals = self.lua.globals();
        let signals = self.lua.create_table()?;
        globals.set("signals", signals)?;

        let print = self.lua.create_function(|l, string: String| {
            let signals: Table = l.globals().get("signals")?;
            let print_signal = l.create_table()?;
            print_signal.set(LuaSignal::Print as usize, string)?;
            signals.push(print_signal)?;
            Ok(())
        })?;
        globals.set("print", print)?;

        let lua_move = self.lua.create_function(|l, point: Vector2| {
            let signals: Table = l.globals().get("signals")?;
            let print_signal = l.create_table()?;
            print_signal.set(LuaSignal::Move as usize, point)?;
            signals.push(print_signal)?;
            Ok(())
        })?;
        globals.set("move", lua_move)?;

        Ok(())
    }

    pub fn handle_request(&mut self, request: LuaRequest) {
        match request {
            LuaRequest::RunLuaCode(code) => {
                self.handle_response(LuaResponse::CodeResult(match self.lua.load(code).exec() {
                    Ok(_) => Ok(self.lua.globals()),
                    Err(e) => Err(e.into()),
                }));
            }
        }
    }
    pub fn handle_response(&mut self, response: LuaResponse) {
        match response {
            LuaResponse::CodeResult(_) => self
                .node_sender
                .send(LuaEvent::Response(response))
                .expect("fuck u"),
        }
    }
}

#[derive(GodotClass)]
#[class(base=Node)]
pub struct LuaRunner {
    lua_task: JoinHandle<()>,
    lua_sender: LuaSender,
    node_receiver: Receiver<LuaEvent>,
    base: Base<Node>,
}

#[godot_api]
impl INode for LuaRunner {
    fn init(base: Base<Node>) -> Self {
        let (node_sender, node_receiver) = channel();

        let (lua_task, lua_sender) = LuaTask::launch_thread(node_sender.clone());

        Self {
            lua_task,
            lua_sender,
            node_receiver,
            base,
        }
    }

    fn ready(&mut self) {
        match self.send_lua_request(LuaRequest::RunLuaCode(String::from(
            "print(\"[LuaRunner] Test Print\")",
        ))) {
            Err(err) => godot_error!("{:?}", err),
            Ok(_) => (),
        }
        godot_print!("[LuaRunner] Ready");
    }

    fn process(&mut self, _: f64) {
        let event = match self.node_receiver.try_recv() {
            Err(e) => {
                match e {
                    TryRecvError::Disconnected => {
                        godot_warn!("[LuaRunner] Sender is disconnected.")
                    }
                    _ => (),
                }
                return;
            }
            Ok(event) => event,
        };

        let response = match event {
            LuaEvent::Response(res) => res,
            _ => return,
        };

        self.signals()
            .on_receive_lua_response()
            .emit(response.as_ref());

        match response {
            LuaResponse::CodeResult(globals) => match globals {
                Ok(g) => self.interpret_signals(g),
                Err(e) => godot_error!("{:?}", e),
            },
        }
    }
}

#[godot_api]
impl LuaRunner {
    #[signal]
    pub fn on_receive_lua_response(response_type: GString);

    #[signal]
    pub fn on_move_signal(x: i32, y: i32);

    #[func]
    fn run_lua_code(&self, code: GString) {
        print_as_godot_error(self.send_lua_request(LuaRequest::RunLuaCode(code.to_string())));
    }

    pub fn send_lua_request(&self, req: LuaRequest) -> Result<()> {
        self.lua_sender.send(LuaEvent::Request(req))?;
        Ok(())
    }

    fn interpret_signals(&mut self, globals: Table) {
        let signals: Table =
            print_as_godot_error(globals.get("signals").map_err(|e| e.into())).unwrap();

        print_as_godot_error(
            signals
                .for_each(|_: Value, signal: Table| {
                    signal.for_each(|signal_type: usize, content: Value| {
                        match signal_type.into() {
                            LuaSignal::Print => {
                                godot_print!("{}", content.to_string()?);
                                Ok(())
                            }
                            LuaSignal::Move => {
                                let vec = content.as_table().unwrap();
                                self.signals()
                                    .on_move_signal()
                                    .emit(vec.get::<i32>("x")?, vec.get::<i32>("y")?);
                                Ok(())
                            }
                            _ => Ok(()),
                        }
                    })?;
                    Ok(())
                })
                .map_err(|e| e.into()),
        );
        print_as_godot_error(signals.clear().map_err(|e| e.into()));
    }
}
