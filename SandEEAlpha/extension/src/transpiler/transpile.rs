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

    fn transpile_statements(&mut self, statements: &[Stmt]) -> Result<String> {
        let mut transpiled = String::new();
        for statement in statements {
            transpiled.push_str(&self.transpile_statement(statement)?);
        }
        Ok(transpiled)
    }

    fn transpile_statement(&mut self, statement: &Stmt) -> Result<String> {
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

                if let Some(kwargs_name) = func.parameters.kwarg.as_ref() {
                    final_args.push(format!(
                        "{}: Dictionary[String, Variant]",
                        kwargs_name.name().as_str()
                    ));
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
                if let Some(kwargs_name) = func.parameters.kwarg.as_ref() {
                    self.symbols
                        .add_symbol(Symbol::Variable(kwargs_name.name().to_string()));
                }

                args.iter()
                    .for_each(|arg| self.symbols.add_symbol(Symbol::Variable(arg.to_string())));

                for (key, value) in kwargs {
                    self.symbols.add_symbol(Symbol::Variable(key.to_string()));
                    transpiled.push_str(&format!(
                        "{}{} = {} if {} else {}\n",
                        self.indent_string(),
                        key,
                        key,
                        key,
                        self.transpile_expression(value)?
                    ));
                }

                if let Some(vararg) = func.parameters.vararg.as_ref() {
                    self.symbols
                        .add_symbol(Symbol::Variable(vararg.name().to_string()));
                }

                transpiled.push_str(&self.transpile_statements(&func.body)?);
                self.dedent();

                Ok(transpiled)
            }
            Stmt::Return(ret) => Ok(if let Some(value) = ret.value.as_ref() {
                format!("return {}", self.transpile_expression(value)?)
            } else {
                "return".to_string()
            }),
            Stmt::For(stmt_for) => {
                let target = self.transpile_expression(&stmt_for.target)?;
                let iter = self.transpile_expression(&stmt_for.iter)?;

                self.indent();
                let body = self.transpile_statements(&stmt_for.body)?;
                self.dedent();

                Ok(format!("for {} in {}:\n{}", target, iter, body))
            }
            Stmt::While(stmt_while) => {
                let test = self.transpile_expression(&stmt_while.test)?;

                self.indent();
                let body = self.transpile_statements(&stmt_while.body)?;
                self.dedent();

                Ok(format!("while {}:\n{}", test, body))
            }
            Stmt::If(stmt_if) => {
                let test = self.transpile_expression(&stmt_if.test)?;

                self.indent();
                let body = self.transpile_statements(&stmt_if.body)?;
                self.dedent();

                let elif_elses: Result<Vec<_>> = stmt_if
                    .elif_else_clauses
                    .iter()
                    .map(|elif_else| {
                        if let Some(test) = elif_else.test.as_ref() {
                            let test = self.transpile_expression(test)?;

                            self.indent();
                            let body = self.transpile_statements(&elif_else.body)?;
                            self.dedent();
                            Ok(format!("elif {}:\n{}", test, body))
                        } else {
                            self.indent();
                            let body = self.transpile_statements(&elif_else.body)?;
                            self.dedent();
                            Ok(format!("else:\n{}", body))
                        }
                    })
                    .collect();

                Ok(format!(
                    "if {}:\n{}\n{}",
                    test,
                    body,
                    elif_elses?.join("\n")
                ))
            }
            Stmt::Expr(expr) => self.transpile_expression(&expr.value),
            Stmt::Pass(_) => Ok("pass".to_string()),
            Stmt::Break(_) => Ok("break".to_string()),
            Stmt::Continue(_) => Ok("continue".to_string()),
            _ => Ok("# Unhandled statement".to_string()),
        };
        Ok(format!("{}{}\n", self.indent_string(), transpiled?))
    }

    fn transpile_expression(&mut self, expression: &Expr) -> Result<String> {
        match expression {
            Expr::BoolOp(op) => {
                let values: Result<Vec<_>> = op
                    .values
                    .iter()
                    .map(|expr| self.transpile_expression(expr))
                    .collect();
                let values = values?;
                Ok(values.join(&format!(" {} ", op.op.as_str())))
            }
            Expr::BinOp(op) => match op.op {
                Operator::MatMult => Err(anyhow!("Unsupported operator: @")),
                Operator::FloorDiv => Ok(format!(
                    "int(floor({} / {}))",
                    self.transpile_expression(&op.left)?,
                    self.transpile_expression(&op.right)?
                )),
                _ => Ok(format!(
                    "{} {} {}",
                    self.transpile_expression(&op.left)?,
                    self.transpile_expression(&op.right)?,
                    op.op.as_str()
                )),
            },
            Expr::UnaryOp(op) => match op.op {
                UnaryOp::Not => Ok(format!("not {}", self.transpile_expression(&op.operand)?)),
                _ => Ok(format!(
                    "{}{}",
                    op.op.as_str(),
                    self.transpile_expression(&op.operand)?
                )),
            },
            Expr::If(expr_if) => {
                let test = self.transpile_expression(&expr_if.test)?;
                let body = self.transpile_expression(&expr_if.body)?;
                let or_else = self.transpile_expression(&expr_if.orelse)?;

                Ok(format!("{} if {} else {}", body, test, or_else))
            }
            Expr::Dict(dict) => {
                let items: Result<Vec<_>> = dict
                    .items
                    .iter()
                    .map(|item| {
                        let key = if let Some(key) = item.key.as_ref() {
                            self.transpile_expression(key)
                        } else {
                            Err(anyhow!(
                                "Unpacking operator for dictionaries is not supported"
                            ))
                        }?;
                        let value = self.transpile_expression(&item.value)?;

                        Ok(format!("{} : {}", key, value))
                    })
                    .collect();
                Ok(format!("{{{}}}", items?.join(", ")))
            }
            Expr::Call(call) => {
                let name = self.transpile_expression(&call.func)?;
                let args = &call.arguments.args;
                let kwargs = &call.arguments.keywords;

                let args: Result<Vec<_>> = args
                    .iter()
                    .map(|arg| self.transpile_expression(arg))
                    .collect();
                let args = args?;

                let kwargs: Result<Vec<(&str, String)>> = kwargs
                    .iter()
                    .map(|kw| {
                        let key = if let Some(arg) = &kw.arg {
                            Ok(arg.as_str())
                        } else {
                            Err(anyhow!(
                                "Unpacking operator for dictionaries is not supported."
                            ))
                        }?;
                        Ok((key, self.transpile_expression(&kw.value)?))
                    })
                    .collect();
                let kwargs = kwargs?;

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

                            if args.len() < num_args {
                                return Err(anyhow!(
                                    "Function {} expected {} positional arguments, received {}.",
                                    name,
                                    num_args,
                                    args.len()
                                ));
                            }

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

                            Ok(format!("{}({})", name, final_args.join(", ")))
                        }
                        Symbol::Variable(name) => {
                            let kwargs: Vec<_> =
                                kwargs.iter().map(|(_, value)| value.as_str()).collect();
                            Ok(format!(
                                "{}({}, {})",
                                name,
                                args.join(", "),
                                kwargs.join(", ")
                            ))
                        }
                        _ => Err(anyhow!("TO IMPLEMENT")),
                    }
                } else {
                    Err(anyhow!("No variable {} found", name))
                }
            }
            Expr::StringLiteral(string) => Ok(format!("\"{}\"", string.value.to_str())),
            Expr::NumberLiteral(number) => match &number.value {
                Number::Int(int) => Ok(int.to_string()),
                Number::Float(float) => Ok(float.to_string()),
                _ => Err(anyhow!("Complex numbers are unsupported.")),
            },
            Expr::BooleanLiteral(bool) => Ok(bool.value.to_string()),
            Expr::NoneLiteral(_) => Ok("null".to_string()),
            Expr::Name(name) => Ok(name.id.to_string()),
            _ => Ok("# Unhandled expr".to_string()),
        }
    }

    fn transpile(&mut self, code: &str) -> Result<String> {
        let ast = ruff_python_parser::parse(code, ParseOptions::from(Mode::Module))?
            .try_into_module()
            .ok_or(anyhow!("Failed to convert into Python module."))?
            .into_suite();
        self.transpile_statements(&ast)
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
                # arg1 = 10
                pass
            def print(*objects, sep = ' ', end = '', file = None, flush = False):
                # GODOT_PROP_signals.append({{'Print': sep.join([str(o) for o in objects]) + end}})
                pass
            print(\"Hello\", True, 1, 3.14, None, sep=\" separator \")
            foo(True, 10, 2.0, \"me when\", \"var arg\", me_when=\"unknown kwarg\")
            "};
        let transpiled = transpiler.transpile(code)?;
        println!("\nOriginal:\n{}\nTranspiled:\n{}", code, transpiled);
        Ok(())
    }
}
