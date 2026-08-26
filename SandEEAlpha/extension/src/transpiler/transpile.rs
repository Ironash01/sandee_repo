use std::fmt::format;

use anyhow::{Result, anyhow};
use godot::prelude::*;
use ruff_python_ast::{Expr, Number, Operator, Stmt, UnaryOp};
use ruff_python_parser::{Mode, ParseOptions};

enum Symbol {
    // name
    Variable(String),
    // name, has_kwargs, has_vararg, num_args, known_kwargs
    Function(String, bool, bool, usize, Vec<String>),
    // name, has_kwargs, has_vararg, num_args, known_kwargs
    Class(String, bool, bool, usize, Vec<String>),
}

impl PartialEq<String> for Symbol {
    fn eq(&self, other: &String) -> bool {
        match self {
            Symbol::Variable(this) => this == other,
            Symbol::Function(this, _, _, _, _) => this == other,
            Symbol::Class(this, _, _, _, _) => this == other,
        }
    }
}

struct SymbolsStack {
    stack: Vec<Vec<Symbol>>,
}

impl Default for SymbolsStack {
    fn default() -> Self {
        Self {
            stack: vec![Vec::new()],
        }
    }
}

impl SymbolsStack {
    fn add_symbol(&mut self, symbol: Symbol) {
        if let Some(last) = self.stack.last_mut() {
            last.push(symbol);
        }
    }

    fn exists(&self, name: &String) -> bool {
        self.stack
            .iter()
            .any(|frame| frame.iter().any(|sym| sym == name))
    }

    fn find(&self, name: &String) -> Option<&Symbol> {
        for frame in &self.stack {
            let symbol = frame.iter().find(|sym| *sym == name);
            if symbol.is_some() {
                return symbol;
            }
        }
        None
    }

    fn push(&mut self) {
        self.stack.push(Vec::new());
    }

    fn pop(&mut self) {
        self.stack.pop();
    }
}

#[derive(Default)]
struct Transpiler {
    indent_level: usize,
    symbols: SymbolsStack,
}

impl Transpiler {
    fn indent_string(&self) -> String {
        "\t".repeat(self.indent_level)
    }

    fn indent(&mut self) {
        self.indent_level += 1;
        self.symbols.push();
    }

    fn dedent(&mut self) {
        self.indent_level -= 1;
        self.symbols.pop();
    }

    fn transpile_statements(&mut self, statements: &[Stmt]) -> String {
        let mut transpiled = String::new();
        statements
            .iter()
            .for_each(|statement| transpiled.push_str(&self.transpile_statement(statement)));
        transpiled
    }

    fn transpile_statement(&mut self, statement: &Stmt) -> String {
        let transpiled = match statement {
            Stmt::FunctionDef(func) => {
                let mut transpiled = format!("func {}(", func.name.as_str());
                let mut args = Vec::with_capacity(func.parameters.len());
                let mut kwargs = Vec::with_capacity(func.parameters.len());
                let mut final_args = Vec::with_capacity(func.parameters.len());

                func.parameters
                    .posonlyargs
                    .iter()
                    .chain(func.parameters.args.iter())
                    .for_each(|arg| {
                        if let Some(default) = arg.default() {
                            kwargs.push((arg.name().as_str(), default));
                        } else {
                            args.push(arg.name().as_str());
                        }
                    });

                func.parameters.kwonlyargs.iter().for_each(|kwarg| {
                    if let Some(default) = kwarg.default() {
                        kwargs.push((kwarg.name().as_str(), default));
                    }
                });

                if let Some(kwargs_name) = func
                    .parameters
                    .kwarg
                    .as_ref()
                    .and_then(|kwarg| Some(kwarg.name().as_str()))
                {
                    final_args.push(format!("{}: Dictionary[String, Variant]", kwargs_name));
                }

                args.iter().for_each(|arg| final_args.push(arg.to_string()));

                kwargs
                    .iter()
                    .for_each(|(kwarg, _)| final_args.push(format!("{}", kwarg)));

                if let Some(vararg) = func.parameters.vararg.as_ref() {
                    final_args.push(format!("...{}: Array", vararg.name().as_str()));
                }

                transpiled.push_str(&final_args.join(", "));
                transpiled.push_str("):\n");

                self.symbols.add_symbol(Symbol::Function(
                    func.name.to_string(),
                    func.parameters.kwarg.is_some(),
                    func.parameters.vararg.is_some(),
                    final_args.len(),
                    kwargs
                        .iter()
                        .map(|(kwargs, _)| kwargs.to_string())
                        .collect(),
                ));

                self.indent();
                kwargs.iter().for_each(|kwarg| {
                    transpiled.push_str(&format!(
                        "{}{} = {} if {} else {}\n",
                        self.indent_string(),
                        kwarg.0,
                        kwarg.0,
                        kwarg.0,
                        self.transpile_expression(kwarg.1)
                    ));
                });

                transpiled.push_str(&self.transpile_statements(&func.body));
                self.dedent();

                transpiled
            }
            Stmt::Return(ret) => {
                if let Some(value) = ret.value.as_ref() {
                    format!("return {}", self.transpile_expression(value))
                } else {
                    "return".to_string()
                }
            }
            Stmt::Expr(expr) => self.transpile_expression(&expr.value),
            Stmt::Pass(_) => "pass".to_string(),
            Stmt::Break(_) => "break".to_string(),
            Stmt::Continue(_) => "continue".to_string(),
            _ => "# Unhandled statement".to_string(),
        };
        format!("{}{}\n", self.indent_string(), transpiled)
    }

    fn transpile_expression(&mut self, expression: &Expr) -> String {
        match expression {
            Expr::BoolOp(op) => {
                let values: Vec<_> = op
                    .values
                    .iter()
                    .map(|expr| self.transpile_expression(expr))
                    .collect();
                values.join(&format!(" {} ", op.op.as_str()))
            }
            Expr::BinOp(op) => match op.op {
                Operator::MatMult => "# Unsupported operator".to_string(),
                Operator::FloorDiv => format!(
                    "int(floor({} / {}))",
                    self.transpile_expression(&op.left),
                    self.transpile_expression(&op.right)
                ),
                _ => format!(
                    "{} {} {}",
                    self.transpile_expression(&op.left),
                    self.transpile_expression(&op.right),
                    op.op.as_str()
                ),
            },
            Expr::UnaryOp(op) => match op.op {
                UnaryOp::Not => format!("not {}", self.transpile_expression(&op.operand)),
                _ => format!(
                    "{}{}",
                    op.op.as_str(),
                    self.transpile_expression(&op.operand)
                ),
            },
            Expr::Lambda(lambda) => {
                let mut transpiled = "func (".to_string();
                if let Some(parameters) = lambda.parameters.as_ref() {
                    let mut args = Vec::with_capacity(parameters.len());
                    let mut kwargs = Vec::with_capacity(parameters.len());

                    parameters
                        .posonlyargs
                        .iter()
                        .chain(parameters.args.iter())
                        .for_each(|arg| {
                            if let Some(default) = arg.default() {
                                kwargs.push((arg.name().as_str(), default));
                            } else {
                                args.push(arg.name().as_str());
                            }
                        });

                    parameters.kwonlyargs.iter().for_each(|kwarg| {
                        if let Some(default) = kwarg.default() {
                            kwargs.push((kwarg.name().as_str(), default));
                        }
                    });

                    let kwargs_name = parameters
                        .kwarg
                        .as_ref()
                        .and_then(|kwarg| Some(kwarg.name().as_str()))
                        .unwrap_or("kwargs");

                    if !kwargs.is_empty() {
                        transpiled
                            .push_str(&format!("_{}: Dictionary[String, Variant], ", kwargs_name));
                    } else if parameters.kwarg.is_some() {
                        transpiled
                            .push_str(&format!("{}: Dictionary[String, Variant], ", kwargs_name));
                    }

                    transpiled.push_str(&args.join(", "));

                    if let Some(vararg) = parameters.vararg.as_ref() {
                        transpiled.push_str(&format!(", ...{}: Array", vararg.name().as_str()));
                    }

                    transpiled.push_str("):\n");

                    self.indent();
                    if !kwargs.is_empty() {
                        let kwargs: Vec<_> = kwargs
                            .iter()
                            .map(|kwarg| {
                                format!("\"{}\": {}", kwarg.0, self.transpile_expression(kwarg.1))
                            })
                            .collect();
                        transpiled.push_str(&format!(
                            "{}var {} = {{{}}}\n{}{}.assign(_{})\n",
                            self.indent_string(),
                            kwargs_name,
                            kwargs.join(", "),
                            self.indent_string(),
                            kwargs_name,
                            kwargs_name
                        ));
                    }
                }
                transpiled.push_str(&format!(
                    "return {}\n",
                    self.transpile_expression(&lambda.body)
                ));
                self.dedent();

                transpiled
            }
            Expr::Call(call) => {
                let name = self.transpile_expression(&call.func);
                let args = &call.arguments.args;
                let kwargs = &call.arguments.keywords;

                let args: Vec<String> = args
                    .iter()
                    .map(|arg| self.transpile_expression(arg))
                    .collect();

                let kwargs: Vec<(&str, String)> = kwargs
                    .iter()
                    .map(|kw| {
                        let key = match &kw.arg {
                            Some(id) => id.as_str(),
                            None => "# what",
                        };
                        (key, self.transpile_expression(&kw.value))
                    })
                    .collect();

                if let Some(symbol) = self.symbols.find(&name) {
                    match symbol {
                        Symbol::Function(name, has_kwargs, has_varargs, num_args, known_kwargs) => {
                            println!(
                                "Found function: {}, {}, {}, {}, {:?}",
                                name, has_kwargs, has_varargs, num_args, known_kwargs
                            );
                            let mut final_args = Vec::with_capacity(*num_args);
                            let mut num_args = *num_args;
                            if *has_kwargs {
                                num_args -= 1;
                            }
                            if *has_varargs {
                                num_args -= 1;
                            }
                            let num_args = num_args - known_kwargs.len();

                            let entered_kwargs: Vec<_> = known_kwargs
                                .iter()
                                .map(|kwarg| {
                                    if let Some((_, value)) =
                                        kwargs.iter().find(|(key, _)| key == kwarg)
                                    {
                                        value.as_str()
                                    } else {
                                        "null"
                                    }
                                })
                                .collect();

                            if *has_kwargs {
                                let other_kwargs: Vec<_> = kwargs
                                    .iter()
                                    .filter(|(key, _)| !known_kwargs.contains(&key.to_string()))
                                    .map(|(key, value)| format!("\"{}\" : {}", key, value))
                                    .collect();
                                final_args.push(format!("{{{}}}", other_kwargs.join(", ")));
                            }

                            if *has_varargs {
                                args[..num_args.min(args.len())]
                                    .iter()
                                    .for_each(|arg| final_args.push(arg.to_string()));
                            } else {
                                args.iter().for_each(|arg| final_args.push(arg.to_string()));
                            }

                            entered_kwargs
                                .iter()
                                .for_each(|kwarg| final_args.push(kwarg.to_string()));

                            if *has_varargs {
                                if let Some(args) = args.get(num_args..) {
                                    args.iter().for_each(|arg| final_args.push(arg.to_string()));
                                }
                            }

                            format!("{}({})", name, final_args.join(", "))
                        }
                        _ => String::new(),
                    }
                } else {
                    let kwargs: Vec<_> = kwargs.iter().map(|(_, value)| value.as_str()).collect();
                    format!("{}({}, {})", name, args.join(", "), kwargs.join(", "))
                }
            }
            Expr::StringLiteral(string) => format!("\"{}\"", string.value.to_str()),
            Expr::NumberLiteral(number) => match &number.value {
                Number::Int(int) => int.to_string(),
                Number::Float(float) => float.to_string(),
                _ => "# Complex number unhandled".to_string(),
            },
            Expr::BooleanLiteral(bool) => bool.value.to_string(),
            Expr::NoneLiteral(_) => "null".to_string(),
            Expr::Name(name) => name.id.to_string(),
            _ => "# Unhandled expr".to_string(),
        }
    }

    fn transpile(&mut self, code: &str) -> Result<String> {
        let ast = ruff_python_parser::parse(code, ParseOptions::from(Mode::Module))?
            .try_into_module()
            .ok_or(anyhow!("Failed to convert into Python module."))?
            .into_suite();
        Ok(self.transpile_statements(&ast))
    }
}

#[derive(GodotClass)]
#[class(base=Node, init)]
struct PythonTranspiler {
    transpiler: Transpiler,
    base: Base<Node>,
}

#[godot_api]
impl PythonTranspiler {
    #[func]
    fn transpile(&mut self, code: String) -> Array<Variant> {
        let (ok, transpiled) = match self.transpiler.transpile(&code) {
            Ok(transpiled) => (true, transpiled),
            Err(error) => (false, format!("{:?}", error)),
        };
        let mut ret: Array<Variant> = Array::new();
        ret.push(ok);
        ret.push(transpiled);
        ret
    }
}

#[cfg(test)]
mod test {
    use super::*;
    #[test]
    fn test_transpile() -> Result<()> {
        let mut transpiler = Transpiler::default();
        let code = indoc::indoc! {"
            def foo(posarg, arg1, arg2, kwarg1=10, kwarg2=2.0, *vararg, kwonly1=True, kwonly2=None, **keyword):
                arg1 = 10
                pass
            def print(*objects, sep = ' ', end = '', file = None, flush = False):
                GODOT_PROP_signals.append({{'Print': sep.join([str(o) for o in objects]) + end}})
            print(\"Hello\", True, 1, 3.14, None, sep=\" separator \")
            foo(True, 10, 2.0, \"me when\", \"var arg\", me_when=\"unknown kwarg\")
            "};
        let transpiled = transpiler.transpile(code)?;
        println!("\nOriginal:\n{}\nTranspiled:\n{}", code, transpiled);
        Ok(())
    }
}
