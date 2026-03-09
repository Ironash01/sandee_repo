mod lua;

use std::sync::mpsc;
use std::thread::JoinHandle;

use godot::prelude::*;

trait InterpreterRunner {
    fn get_interpreter_thread() -> JoinHandle<()>;
}
