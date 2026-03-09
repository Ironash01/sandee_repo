use godot::prelude::*;
use std::thread::JoinHandle;

#[derive(GodotClass)]
#[class(base=Node)]
pub struct LuaRunner {
    runner_thread: Option<JoinHandle<()>>,
    base: Base<Node>,
}

#[godot_api]
impl INode for LuaRunner {
    fn init(base: Base<Node>) -> Self {
        Self {
            runner_thread: None,
            base,
        }
    }
}
