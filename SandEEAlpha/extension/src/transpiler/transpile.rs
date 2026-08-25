use anyhow::{Result, anyhow};
use godot::prelude::*;
use ruff_python_ast::{Expr, Number, Operator, Stmt, UnaryOp};
use ruff_python_parser::{Mode, ParseOptions};

enum Symbol {
    Variable(String),
    Function(String, bool),
    Class(String),
}

impl PartialEq<String> for Symbol {
    fn eq(&self, other: &String) -> bool {
        match self {
            Symbol::Variable(this) => this == other,
            Symbol::Function(this, _) => this == other,
            Symbol::Class(this) => this == other,
        }
    }
}

#[derive(Default)]
struct SymbolsStack {
    stack: Vec<Vec<Symbol>>,
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
}

impl Transpiler {
    fn indent(&self) -> String {
        "\t".repeat(self.indent_level)
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
                let mut transpiled = format!("func {}(", func.name.to_string());
                let mut args = Vec::with_capacity(func.parameters.len());
                let mut kwargs = Vec::with_capacity(func.parameters.len());

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

                let kwargs_name = func
                    .parameters
                    .kwarg
                    .as_ref()
                    .and_then(|kwarg| Some(kwarg.name().as_str()))
                    .unwrap_or("kwargs");

                if !kwargs.is_empty() {
                    transpiled
                        .push_str(&format!("_{}: Dictionary[String, Variant], ", kwargs_name));
                } else if func.parameters.kwarg.is_some() {
                    transpiled.push_str(&format!("{}: Dictionary[String, Variant], ", kwargs_name));
                }

                transpiled.push_str(&args.join(", "));

                if let Some(vararg) = func.parameters.vararg.as_ref() {
                    transpiled.push_str(&format!(", ...{}: Array", vararg.name().as_str()));
                }

                transpiled.push_str("):\n");

                self.indent_level += 1;
                if !kwargs.is_empty() {
                    let kwargs: Vec<_> = kwargs
                        .iter()
                        .map(|kwarg| {
                            format!("\"{}\": {}", kwarg.0, self.transpile_expression(kwarg.1))
                        })
                        .collect();
                    transpiled.push_str(&format!(
                        "{}var {} = {{{}}}\n{}{}.merge(_{}, true)\n",
                        self.indent(),
                        kwargs_name,
                        kwargs.join(", "),
                        self.indent(),
                        kwargs_name,
                        kwargs_name
                    ));
                }
                transpiled.push_str(&self.transpile_statements(&func.body));
                self.indent_level -= 1;

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
        format!("{}{}\n", self.indent(), transpiled)
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

                    self.indent_level += 1;
                    if !kwargs.is_empty() {
                        let kwargs: Vec<_> = kwargs
                            .iter()
                            .map(|kwarg| {
                                format!("\"{}\": {}", kwarg.0, self.transpile_expression(kwarg.1))
                            })
                            .collect();
                        transpiled.push_str(&format!(
                            "{}var {} = {{{}}}\n{}{}.assign(_{})\n",
                            self.indent(),
                            kwargs_name,
                            kwargs.join(", "),
                            self.indent(),
                            kwargs_name,
                            kwargs_name
                        ));
                    }
                }
                transpiled.push_str(&format!(
                    "return {}\n",
                    self.transpile_expression(&lambda.body)
                ));
                self.indent_level -= 1;

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
                let args = args.join(", ");

                let kwargs: Vec<String> = kwargs
                    .iter()
                    .map(|kw| {
                        let key = match &kw.arg {
                            Some(id) => id.as_str(),
                            None => "# what",
                        };
                        format!("\"{}\": {}", key, self.transpile_expression(&kw.value))
                    })
                    .collect();
                let kwargs = format!("{{{}}}", kwargs.join(", "));

                format!("{}({}, {})", name, kwargs, args)
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
            "};
        let transpiled = transpiler.transpile(code)?;
        println!("\nOriginal:\n{}\nTranspiled:\n{}", code, transpiled);
        Ok(())
    }
}
