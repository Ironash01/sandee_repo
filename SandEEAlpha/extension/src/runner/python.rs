use std::{cell::RefCell, rc::Rc};

use anyhow::{Result, anyhow};
use godot::prelude::*;
use rustpython_vm::{Interpreter, PyPayload, PyResult, Settings};

#[derive(GodotClass)]
#[class(base=Node)]
struct PythonVM {
    interpreter: Interpreter,
    base: Base<Node>,
}

#[godot_api]
impl INode for PythonVM {
    fn init(base: Base<Node>) -> Self {
        Self {
            interpreter: Interpreter::without_stdlib(Settings::default()),
            base,
        }
    }
}

impl PythonVM {
    fn run_code(&self, stdout: Rc<GodotOut>, code: &str) -> Result<()> {
        let result: PyResult<()> = self.interpreter.enter(|vm| {
            let scope = vm.new_scope_with_builtins();
            vm.run_string(scope, code, "<ext>".to_string())?;

            Ok(())
        });
        match result {
            Ok(_) => Ok(()),
            Err(exception) => Err(anyhow!("{:?}", exception)),
        }
    }
}

#[derive(GodotClass)]
#[class(init, base=Resource)]
pub struct InventoryItem {
    #[var]
    pub name: GString,
    #[var]
    pub quantity: u32,
    base: Base<Resource>,
}

#[derive(GodotClass)]
#[class(base=Node)]
struct PythonState {
    #[export]
    vm: Option<Gd<PythonVM>>,
    #[var]
    code: GString,
    #[var]
    inventory: Array<Gd<InventoryItem>>,
    stdout: Rc<GodotOut>,
    base: Base<Node>,
}

#[derive(Default, PyPayload)]
#[rustpython_vm::pyclass(module = "godot_out", name = "GodotOut")]
struct GodotOut {
    buffer: RefCell<String>,
}

#[rustpython_vm::pyclass]
impl GodotOut {
    #[pymethod]
    fn write(&self, s: String) {
        self.buffer.borrow_mut().push_str(s.as_str());
    }

    #[pymethod]
    fn flush(&self) {
        self.buffer.borrow_mut().clear();
    }
}

impl GodotOut {
    fn has_content(&self) -> bool {
        !self.buffer.borrow().is_empty()
    }

    fn clear(&self) {
        self.buffer.borrow_mut().clear();
    }
}

#[godot_api]
impl INode for PythonState {
    fn init(base: Base<Node>) -> Self {
        Self {
            vm: None,
            code: GString::new(),
            inventory: Array::new(),
            stdout: Rc::new(GodotOut::default()),
            base,
        }
    }

    fn physics_process(&mut self, _: f64) {
        if self.stdout.has_content() {
            let string = self.stdout.buffer.borrow().to_string();
            godot_print!("{}", string);
            self.stdout.clear();
        }
    }
}

#[godot_api]
impl PythonState {
    #[signal]
    fn code_executed();
    #[signal]
    fn code_failed(error: String);
    #[signal]
    fn signal_print(string: String);

    #[func]
    pub fn add_item(&mut self, name: GString, quantity: u32) {
        let item = Gd::from_init_fn(|base| InventoryItem {
            name,
            quantity,
            base,
        });
        self.inventory.push(&item);
    }

    #[func]
    pub fn clear_items(&mut self) {
        self.inventory.clear();
    }

    #[func]
    fn run_code(&mut self) {
        if let Err(e) = self._run_code(self.code.to_string().as_ref()) {
            self.signals().code_failed().emit(e.to_string());
        } else {
            self.signals().code_executed().emit();
        }
    }

    pub fn _run_code(&self, code: &str) -> Result<()> {
        match self.vm.clone() {
            None => Err(anyhow!("No VM available.")),
            Some(vm) => vm.bind().run_code(self.stdout.clone(), code),
        }
    }
}
