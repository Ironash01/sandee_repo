use anyhow::Result;
use godot::prelude::*;
use mlua::Lua;
use std::{
    sync::mpsc::{Receiver, Sender, TryRecvError, channel},
    thread::{self, JoinHandle},
};

pub enum LuaSignal {
    Move(f64, f64),
}

pub enum LuaRequest {
    Initialize,
    RunLua(String),
}

pub enum LuaResponse {
    Initialized,
    CodeResult(Result<()>),
}

pub enum LuaEvent {
    Request(LuaRequest),
    Respond(LuaResponse),
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
        let task: JoinHandle<()> = thread::spawn(move || {
            let mut lua = Self::new(scoped_lua_sender, node_sender);

            loop {
                let next = match lua_receiver.recv() {
                    Err(_) => continue,
                    Ok(e) => e,
                };

                match next {
                    LuaEvent::Request(req) => lua.handle_request(req),
                    LuaEvent::Respond(res) => lua.handle_response(res),
                }
            }
        });

        return (task, lua_sender);
    }

    fn new(lua_sender: LuaSender, node_sender: LuaSender) -> Self {
        let lua = Lua::new();
        Self {
            lua_sender,
            node_sender,
            lua,
        }
    }

    pub fn handle_request(&mut self, request: LuaRequest) {
        match request {
            LuaRequest::Initialize => todo!(),
            LuaRequest::RunLua(_) => todo!(),
        }
    }
    pub fn handle_response(&mut self, response: LuaResponse) {
        match response {
            LuaResponse::Initialized => todo!(),
            LuaResponse::CodeResult(_) => todo!(),
        }
    }
}

#[derive(GodotClass)]
#[class(base=Node)]
pub struct LuaRunner {
    lua_task: JoinHandle<()>,
    lua_sender: LuaSender,
    node_sender: LuaSender,
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
            node_sender,
            node_receiver,
            base,
        }
    }

    fn ready(&mut self) {
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

        match event {
            LuaEvent::Request(_) => todo!(),
            LuaEvent::Respond(_) => todo!(),
        }
    }
}

impl LuaRunner {}
