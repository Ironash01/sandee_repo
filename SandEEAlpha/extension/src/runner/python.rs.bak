use std::{collections::VecDeque, str::FromStr};

use anyhow::{Result, anyhow};
use godot::prelude::*;
use indoc::formatdoc;
use rustpython_vm::{
    Interpreter, Settings,
    builtins::{PyDictRef, PyIntRef, PyListRef, PyStr, PyStrRef, PyTupleRef},
};
use strum::{AsRefStr, EnumString};

#[derive(AsRefStr, EnumString)]
pub enum PythonSignal {
    Generic,
    Print(String),
    Create(String, u32),
}

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
    fn run_code(
        &self,
        inventory: &Array<Gd<InventoryItem>>,
        code: &str,
    ) -> Result<VecDeque<PythonSignal>> {
        self.interpreter.enter(|vm| {
            let scope = vm.new_scope_with_builtins();

            let code = formatdoc!(
                r#"
                GODOT_PROP_signals = []

                def print(*objects, sep = ' ', end = '', file = None, flush = False):
                    GODOT_PROP_signals.append({{'Print': sep.join([str(o) for o in objects]) + end}})

                def create(object, quantity):
                    GODOT_PROP_signals.append({{'Create': (object, quantity)}})

                {}"#,
                code
            );
            vm.run_string(scope.clone(), code.as_str(), "<ext>").map_err(|err| anyhow!("{:?}", err))?;

            let py_signals: PyListRef = scope
                .globals
                .get_item("GODOT_PROP_signals", &vm).map_err(|err| anyhow!("{:?}", err))?
                .downcast().map_err(|_| anyhow!("Could not convert signals to list"))?;

            let signals: Result<Vec<Vec<PythonSignal>>> = py_signals.borrow_vec().into_iter().map(|py_signal| {
                let py_signal: PyDictRef = py_signal.clone().downcast().map_err(|_| anyhow!("Could not convert signal to dict"))?;
                let signal: Result<Vec<PythonSignal>> = py_signal.items_vec().into_iter().map(|(key, value)| {
                    let signal: PythonSignal = PythonSignal::from_str(
                        key
                            .downcast::<PyStr>()
                            .map_err(|_| anyhow!("Could not convert signal (downcast error)"))?
                            .to_str().unwrap_or("Generic")
                    ).map_err(|_| anyhow!("Could not convert signal (enum variant)"))?;

                    let signal = match signal {
                        PythonSignal::Print(_) => {
                            PythonSignal::Print(value
                                .downcast::<PyStr>()
                                .map_err(|_| anyhow!("Could not convert print signal (downcast error)"))?.to_string())
                            },
                        PythonSignal::Create(_, _) => {
                           let value: PyTupleRef = value.downcast().map_err(|_| anyhow!("Could not convert create signal (downcast error"))?;
                           let object: PyStrRef = value
                               .first().ok_or(anyhow!("Could not convert create signal (tuple access error)"))?
                               .clone().downcast().map_err(|_| anyhow!("Could not convert create signal (object downcast error)"))?;
                           let quantity: PyIntRef = value
                               .last().ok_or(anyhow!("Could not convert create signal (tuple access error)"))?
                               .clone().downcast().map_err(|_| anyhow!("Could not convert create signal (quantity downcast error)"))?;
                           PythonSignal::Create(object.to_string(), quantity.as_u32_mask())
                        },
                        PythonSignal::Generic => PythonSignal::Generic,
                    };

                    Ok(signal)
                }).collect();
                signal
            }).collect();

            Ok(signals?.into_iter().flatten().collect())
        })
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
    signals: VecDeque<PythonSignal>,
    base: Base<Node>,
}

#[godot_api]
impl INode for PythonState {
    fn init(base: Base<Node>) -> Self {
        Self {
            vm: None,
            code: GString::new(),
            inventory: Array::new(),
            signals: VecDeque::new(),
            base,
        }
    }

    fn physics_process(&mut self, _: f64) {
        while !self.signals.is_empty() {
            let signal = self.signals.pop_front().expect("Failed to read signal");

            match signal {
                PythonSignal::Print(string) => self.signals().signal_print().emit(string),
                PythonSignal::Create(object, quantity) => {
                    self.signals().signal_create().emit(object, quantity)
                }
                PythonSignal::Generic => (),
            }
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
    #[signal]
    fn signal_create(object: String, quantity: u32);

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
        match self._run_code(self.code.to_string().as_ref()) {
            Ok(signals) => {
                self.signals = signals;
                self.signals().code_executed().emit();
            }
            Err(e) => self.signals().code_failed().emit(e.to_string()),
        }
    }

    pub fn _run_code(&self, code: &str) -> Result<VecDeque<PythonSignal>> {
        match self.vm.clone() {
            None => Err(anyhow!("No VM available.")),
            Some(vm) => vm.bind().run_code(&self.inventory, code),
        }
    }
}

#[cfg(test)]
mod test {
    use anyhow::{Result, anyhow};
    use indoc::indoc;
    use rustpython_vm::{Interpreter, PyResult, Settings};

    #[test]
    fn test_python() -> Result<()> {
        let builder = Interpreter::builder(Settings::default());
        let interp = builder.build();

        let res: PyResult<()> = interp.enter(|vm| {
            let scope = vm.new_scope_with_builtins();

            let code = indoc! {"

                "};
            println!("{}", code);
            let out = vm.run_string(scope.clone(), code, "<ext>")?;
            println!("{:?}", scope.globals.get_item("test", &vm)?);
            Ok(())
        });

        res.map_err(|err| {
            anyhow!(
                "{:?}\n{:?}\n{:?}\n{:?}",
                err,
                err.__cause__(),
                err.__context__(),
                err.__traceback__()
            )
        })
    }
}
