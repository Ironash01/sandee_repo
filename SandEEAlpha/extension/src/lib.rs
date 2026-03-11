mod runner;
mod utils;
use godot::prelude::*;
use runner::prelude::*;

struct InterpreterExtension;

#[gdextension]
unsafe impl ExtensionLibrary for InterpreterExtension {
    fn on_stage_init(stage: InitStage) {
        godot_print!("[Rust] Loaded extension at stage: {:?}", stage);
    }
}
