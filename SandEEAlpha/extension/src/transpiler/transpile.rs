use crate::transpiler::spec::{Arguments, PythonType, Symbol, SymbolsStack};
use anyhow::{Result, anyhow};
use godot::prelude::*;
use ruff_python_ast::{CmpOp, Expr, ExprContext, Number, Operator, Stmt, UnaryOp};
use ruff_python_parser::{Mode, ParseOptions};

// Python comparison operators -> their GDScript equivalents. `is` / `is not`
// are identity checks against None in the curriculum, and None -> null, so
// they map onto equality.
fn cmp_op_str(op: &CmpOp) -> &'static str {
    match op {
        CmpOp::Eq => "==",
        CmpOp::NotEq => "!=",
        CmpOp::Lt => "<",
        CmpOp::LtE => "<=",
        CmpOp::Gt => ">",
        CmpOp::GtE => ">=",
        CmpOp::In => "in",
        CmpOp::NotIn => "not in",
        CmpOp::Is => "==",
        CmpOp::IsNot => "!=",
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
                // GDScript has no nested `func`, so a function defined inside
                // another — which is exactly what wrapping the player's code in
                // main() produces — becomes a Callable lambda assignment. It is
                // registered as a Callable variable so calls become .call(...).
                let nested = self.indent_level > 0;
                let mut transpiled = if nested {
                    format!("var {} = func(", func.name.as_str())
                } else {
                    format!("func {}(", func.name.as_str())
                };
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
                    Arguments::new(
                        func.parameters.kwarg.is_some(),
                        func.parameters.vararg.is_some(),
                        final_args.len(),
                        kwargs
                            .iter()
                            .map(|(kwargs, _)| kwargs.to_string())
                            .collect(),
                    ),
                ));
                if nested {
                    // Shadow the function symbol: a lambda is a value, not a
                    // method, so the name resolves to a Callable (see the Call
                    // expression handler).
                    self.symbols.add_symbol(Symbol::Variable(
                        func.name.to_string(),
                        PythonType::Callable,
                    ));
                }

                self.indent();
                if let Some(kwargs_name) = func.parameters.kwarg.as_ref() {
                    self.symbols.add_symbol(Symbol::Variable(
                        kwargs_name.name().to_string(),
                        PythonType::Dict,
                    ));
                }

                args.iter().for_each(|arg| {
                    self.symbols
                        .add_symbol(Symbol::Variable(arg.to_string(), PythonType::Any))
                });

                for (key, value) in kwargs {
                    self.symbols.add_symbol(Symbol::Variable(
                        key.to_string(),
                        PythonType::from_expr(value, &self.symbols)?,
                    ));
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
                    self.symbols.add_symbol(Symbol::Variable(
                        vararg.name().to_string(),
                        PythonType::List,
                    ));
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
            Stmt::Assign(assign) => {
                let mut transpiled = Vec::new();
                let value = self.transpile_expression(&assign.value)?;
                let value_len = match &*assign.value {
                    Expr::Tuple(tuple) => Some(tuple.len()),
                    Expr::List(list) => Some(list.len()),
                    _ => None,
                };
                for target in &assign.targets {
                    let target_str = self.transpile_expression(&target)?;
                    match target {
                        Expr::Tuple(target) => match value_len {
                            Some(value_len) => {
                                if value_len < target.len() {
                                    return Err(anyhow!(
                                        "Not enough values to unpack for target {} (expected {}, got {})",
                                        target_str,
                                        target.len(),
                                        value_len
                                    ));
                                } else if value_len > target.len() {
                                    return Err(anyhow!(
                                        "Too many values to unpack for target {} (expected {}, got {})",
                                        target_str,
                                        target.len(),
                                        value_len
                                    ));
                                }
                                let values = match &*assign.value {
                                    Expr::Tuple(tuple) => &tuple.elts,
                                    Expr::List(list) => &list.elts,
                                    _ => unreachable!(),
                                };
                                for (i, target) in target.elts.iter().enumerate() {
                                    let target = self.transpile_expression(target)?;
                                    if self.symbols.exists(&target) {
                                        transpiled.push(format!("{} = {}[{}]", target, value, i));
                                    } else {
                                        transpiled
                                            .push(format!("var {} = {}[{}]", target, value, i));
                                        self.symbols.add_symbol(Symbol::Variable(
                                            target,
                                            PythonType::from_expr(&values[i], &self.symbols)?,
                                        ));
                                    }
                                }
                            }
                            None => {
                                return Err(anyhow!(
                                    "Cannot unpack non-iterable value {} for target {}",
                                    value,
                                    target_str
                                ));
                            }
                        },
                        Expr::List(target) => match value_len {
                            Some(value_len) => {
                                if value_len < target.len() {
                                    return Err(anyhow!(
                                        "Not enough values to unpack for target {} (expected {}, got {})",
                                        target_str,
                                        target.len(),
                                        value_len
                                    ));
                                } else if value_len > target.len() {
                                    return Err(anyhow!(
                                        "Too many values to unpack for target {} (expected {}, got {})",
                                        target_str,
                                        target.len(),
                                        value_len
                                    ));
                                }
                                let values = match &*assign.value {
                                    Expr::Tuple(tuple) => &tuple.elts,
                                    Expr::List(list) => &list.elts,
                                    _ => unreachable!(),
                                };
                                for (i, target) in target.elts.iter().enumerate() {
                                    let target = self.transpile_expression(target)?;
                                    if self.symbols.exists(&target) {
                                        transpiled.push(format!("{} = {}[{}]", target, value, i));
                                    } else {
                                        transpiled
                                            .push(format!("var {} = {}[{}]", target, value, i));
                                        self.symbols.add_symbol(Symbol::Variable(
                                            target,
                                            PythonType::from_expr(&values[i], &self.symbols)?,
                                        ));
                                    }
                                }
                            }
                            None => {
                                return Err(anyhow!(
                                    "Cannot unpack non-iterable value {} for target {}",
                                    value,
                                    target_str
                                ));
                            }
                        },
                        _ => {
                            if self.symbols.exists(&target_str) {
                                transpiled.push(format!("{} = {}", target_str, value));
                            } else {
                                transpiled.push(format!("var {} = {}", target_str, value));
                                self.symbols.add_symbol(Symbol::Variable(
                                    target_str,
                                    PythonType::from_expr(&assign.value, &self.symbols)?,
                                ));
                            }
                        }
                    }
                }
                Ok(transpiled.join("\n"))
            }
            Stmt::AugAssign(aug_assign) => {
                let target = self.transpile_expression(&aug_assign.target)?;
                if self.symbols.exists(&target) {
                    match aug_assign.op {
                        Operator::MatMult => {
                            Err(anyhow!("Matrix multiplication operator @ is unsupported"))
                        }
                        Operator::FloorDiv => Ok(format!(
                            "{} = int(floor({} / {}))",
                            target,
                            target,
                            self.transpile_expression(&aug_assign.value)?
                        )),
                        _ => Ok(format!(
                            "{} {}= {}",
                            target,
                            aug_assign.op.as_str(),
                            self.transpile_expression(&aug_assign.value)?
                        )),
                    }
                } else {
                    Err(anyhow!("No variable {} found", target))
                }
            }
            Stmt::For(stmt_for) => {
                let target = self.transpile_expression(&stmt_for.target)?;
                if stmt_for.target.is_name_expr() {
                    let iter = self.transpile_expression(&stmt_for.iter)?;
                    let iter_type = PythonType::from_expr(&stmt_for.iter, &self.symbols)?;

                    self.indent();
                    match iter_type {
                        PythonType::String => self
                            .symbols
                            .add_symbol(Symbol::Variable(target.clone(), PythonType::String)),
                        _ => self
                            .symbols
                            .add_symbol(Symbol::Variable(target.clone(), PythonType::Any)),
                    }
                    let body = self.transpile_statements(&stmt_for.body)?;
                    self.dedent();

                    Ok(format!("for {} in {}:\n{}", target, iter, body))
                } else {
                    Err(anyhow!("{} target for for loops is unsupported.", target))
                }
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
                            Ok(format!("{}elif {}:\n{}", self.indent_string(), test, body))
                        } else {
                            self.indent();
                            let body = self.transpile_statements(&elif_else.body)?;
                            self.dedent();
                            Ok(format!("{}else:\n{}", self.indent_string(), body))
                        }
                    })
                    .collect();

                Ok(format!(
                    "if {}:\n{}{}",
                    test,
                    body,
                    elif_elses?.join("")
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
                Operator::MatMult => {
                    Err(anyhow!("Matrix multiplication operator @ is unsupported"))
                }
                Operator::FloorDiv => Ok(format!(
                    "int(floor({} / {}))",
                    self.transpile_expression(&op.left)?,
                    self.transpile_expression(&op.right)?
                )),
                _ => {
                    // Python order is `left OP right`, so the operands must be
                    // emitted in that order (this arm previously produced
                    // `left right OP`, i.e. `x 1 +`, which is not valid).
                    let left = self.transpile_expression(&op.left)?;
                    let right = self.transpile_expression(&op.right)?;
                    Ok(format!("{} {} {}", left, op.op.as_str(), right))
                }
            },
            Expr::Compare(compare) => {
                // Comparison operators (==, !=, <, <=, >, >=, in, not in, is,
                // is not). Python's chained form (a < b < c) means
                // `a < b and b < c`, so join the links with `and` rather than
                // emitting a GDScript chain (which would compare a bool).
                let mut parts: Vec<String> = Vec::new();
                let mut left = self.transpile_expression(&compare.left)?;
                for (op, comparator) in compare.ops.iter().zip(compare.comparators.iter()) {
                    let right = self.transpile_expression(comparator)?;
                    parts.push(format!("{} {} {}", left, cmp_op_str(op), right));
                    left = right;
                }
                Ok(parts.join(" and "))
            }
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
            Expr::Call(call) => match &*call.func {
                Expr::Name(name) => {
                    let name = name.id().as_str();
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

                    if let Some(symbol) = self.symbols.find(name) {
                        match symbol {
                            Symbol::Function(name, func_args) => {
                                let name = if name == "print" { "godot_print" } else { name };
                                println!("Found function: {}, {:?}", name, func_args);
                                let mut final_args = Vec::with_capacity(func_args.num_args);
                                let mut num_args = func_args.num_args;
                                if func_args.has_kwargs {
                                    num_args -= 1;
                                }
                                if func_args.has_vararg {
                                    num_args -= 1;
                                }
                                let num_args = num_args - func_args.known_kwargs.len();

                                if args.len() < num_args {
                                    return Err(anyhow!(
                                        "Function {} expected {} positional arguments, received {}.",
                                        name,
                                        num_args,
                                        args.len()
                                    ));
                                }

                                let entered_kwargs: Vec<_> = func_args
                                    .known_kwargs
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

                                if func_args.has_kwargs {
                                    let other_kwargs: Vec<_> = kwargs
                                        .iter()
                                        .filter(|(key, _)| {
                                            !func_args.known_kwargs.contains(&key.to_string())
                                        })
                                        .map(|(key, value)| format!("\"{}\" : {}", key, value))
                                        .collect();
                                    final_args.push(format!("{{{}}}", other_kwargs.join(", ")));
                                }

                                if func_args.has_vararg {
                                    args[..num_args.min(args.len())]
                                        .iter()
                                        .for_each(|arg| final_args.push(arg.to_string()));
                                } else {
                                    args.iter().for_each(|arg| final_args.push(arg.to_string()));
                                }

                                entered_kwargs
                                    .iter()
                                    .for_each(|kwarg| final_args.push(kwarg.to_string()));

                                if func_args.has_vararg {
                                    if let Some(args) = args.get(num_args..) {
                                        args.iter()
                                            .for_each(|arg| final_args.push(arg.to_string()));
                                    }
                                }

                                Ok(format!("{}({})", name, final_args.join(", ")))
                            }
                            Symbol::Variable(name, pytype) => match pytype {
                                // A function value (e.g. a nested def turned
                                // into a lambda) is a Callable: `name(...)`
                                // would be resolved as a method on self and
                                // fail to compile, so invoke it with .call().
                                PythonType::Callable => {
                                    let mut all_args: Vec<String> = args.clone();
                                    all_args
                                        .extend(kwargs.iter().map(|(_, value)| value.to_string()));
                                    Ok(format!("{}.call({})", name, all_args.join(", ")))
                                }
                                _ => Err(anyhow!("Variable {} is not callable", name)),
                            },
                            _ => Err(anyhow!("TO IMPLEMENT")),
                        }
                    } else {
                        Err(anyhow!("No callable {} found", name))
                    }
                }
                Expr::Attribute(attr) => {
                    let pytype = PythonType::from_expr(&attr.value, &self.symbols)?;
                    let accessed_attr = attr.attr.as_str();
                    if let Some(godot_attr) = pytype.has_attr(accessed_attr) {
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

                        let kwargs: Vec<_> =
                            kwargs.iter().map(|(_, value)| value.to_string()).collect();

                        let final_args: Vec<_> =
                            args.into_iter().chain(kwargs.into_iter()).collect();
                        Ok(godot_attr
                            .iter()
                            .fold(self.transpile_expression(&attr.value)?, |res, attr| {
                                format!("{}.{}({})", res, attr, final_args.join(", "))
                            }))
                    } else {
                        Err(anyhow!(
                            "{} does not have the attribute {}.",
                            self.transpile_expression(&attr.value)?,
                            accessed_attr
                        ))
                    }
                }
                _ => Err(anyhow!(
                    "Expression {} is not callable",
                    self.transpile_expression(&call.func)?
                )),
            },
            Expr::StringLiteral(string) => Ok(format!("\"{}\"", string.value.to_str())),
            Expr::NumberLiteral(number) => match &number.value {
                Number::Int(int) => Ok(int.to_string()),
                Number::Float(float) => Ok(float.to_string()),
                _ => Err(anyhow!("Complex numbers are unsupported.")),
            },
            Expr::BooleanLiteral(bool) => Ok(bool.value.to_string()),
            Expr::NoneLiteral(_) => Ok("null".to_string()),
            Expr::Attribute(attr) => Ok(format!(
                "{}.{}",
                self.transpile_expression(&attr.value)?,
                attr.attr.as_str()
            )),
            Expr::Subscript(subscript) => {
                let value = self.transpile_expression(&subscript.value)?;
                match &*subscript.slice {
                    Expr::Tuple(_) => Err(anyhow!("Tuple subscripts are unsupported")),
                    Expr::Slice(_) => Ok(format!(
                        "{}.slice({})",
                        value,
                        self.transpile_expression(&subscript.slice)?
                    )),
                    _ => Ok(format!(
                        "{}[{}]",
                        value,
                        self.transpile_expression(&subscript.slice)?
                    )),
                }
            }
            Expr::Name(name) => match name.ctx {
                ExprContext::Load | ExprContext::Del => self
                    .symbols
                    .exists(&name.id())
                    .then_some(name.id().to_string())
                    .ok_or(anyhow!("No symbol {} found", name.id())),
                _ => Ok(name.id().to_string()),
            },
            Expr::List(list) => {
                let elts: Result<Vec<_>> = list
                    .elts
                    .iter()
                    .map(|elt| self.transpile_expression(elt))
                    .collect();
                Ok(format!("[{}]", elts?.join(", ")))
            }
            Expr::Tuple(tuple) => {
                let elts: Result<Vec<_>> = tuple
                    .elts
                    .iter()
                    .map(|elt| self.transpile_expression(elt))
                    .collect();
                Ok(format!("[{}]", elts?.join(", ")))
            }
            Expr::Slice(slice) => {
                let lower = slice
                    .lower
                    .as_ref()
                    .map_or(Ok("0".to_string()), |l| self.transpile_expression(&l))?;
                let upper = slice
                    .upper
                    .as_ref()
                    .map_or(Ok(i32::MAX.to_string()), |l| self.transpile_expression(&l))?;
                let step = slice
                    .step
                    .as_ref()
                    .map_or(Ok("1".to_string()), |l| self.transpile_expression(&l))?;

                Ok(format!("{}, {}, {}", lower, upper, step))
            }
            _ => Ok("# Unhandled expr".to_string()),
        }
    }

    fn transpile(&mut self, code: &str) -> Result<String> {
        self.symbols.reset();
        // A failed transpile can return early (via `?`) with indents/symbols
        // still pushed, so reset the indentation here too. Without this, the
        // NEXT transpile on the same PythonTranspiler instance starts already
        // indented and the generated GDScript fails with
        // "Expected statement, found Indent instead".
        self.indent_level = 0;
        let ast = ruff_python_parser::parse(code, ParseOptions::from(Mode::Module))?
            .try_into_module()
            .ok_or(anyhow!("Failed to convert into Python module."))?
            .into_suite();
        let transpiled = self.transpile_statements(ast.as_slice())?;
        if self.symbols.exists("main") {
            Ok(transpiled)
        } else {
            Err(anyhow!("No main function found"))
        }
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
    fn test_binop_operand_order() -> Result<()> {
        let mut transpiler = Transpiler::default();
        let out = transpiler.transpile("def main():\n    x = 1 + 2\n")?;
        assert!(out.contains("1 + 2"), "operator/operand order wrong: {out}");
        Ok(())
    }

    #[test]
    fn test_compare_and_if_else_indent() -> Result<()> {
        let mut transpiler = Transpiler::default();
        let out = transpiler.transpile(
            "def main():\n    x = 1\n    if x > 2:\n        print(1)\n    else:\n        print(2)\n",
        )?;
        assert!(out.contains("if x > 2:"), "comparison not transpiled: {out}");
        assert!(out.contains("\telse:"), "else must be indented to the if level: {out}");
        assert!(!out.contains("\nelse:"), "else must not sit at column 0: {out}");
        Ok(())
    }

    #[test]
    fn test_indent_reset_after_failed_transpile() -> Result<()> {
        let mut transpiler = Transpiler::default();
        // MatMult is rejected, so this returns Err with the indent still pushed.
        assert!(transpiler.transpile("def main():\n    x = a @ b\n").is_err());
        // The next transpile on the same instance must start at column 0 again,
        // otherwise GDScript fails with `Expected statement, found "Indent"`.
        let out = transpiler.transpile("def main():\n    print(1)\n")?;
        assert!(out.starts_with("func main():"), "indent leaked between runs: {out}");
        Ok(())
    }

    #[test]
    fn test_nested_def_becomes_lambda() -> Result<()> {
        let mut transpiler = Transpiler::default();
        let out = transpiler.transpile(
            "def main():\n    def greet(name):\n        return \"Hi \" + name\n    print(greet(\"x\"))\n",
        )?;
        assert!(
            out.contains("var greet = func(name):"),
            "nested def should become a Callable: {out}"
        );
        assert!(
            out.contains("greet.call("),
            "calling a lambda must use .call(): {out}"
        );
        Ok(())
    }

    #[test]
    fn test_transpile() -> Result<()> {
        let mut transpiler = Transpiler::default();
        let code = indoc::indoc! {"
            def baz(arg1, arg2, /, *args):
                pass
            def main():
                foo = ['1', '2', '3']
                bar = '   test   '.upper()
                for i in range(3):
                    print(i)
            "};
        let transpiled = transpiler.transpile(code)?;
        println!(
            "\nOriginal:\n{}\nTranspiled:\n{}\nGlobals: {:?}",
            code, transpiled, transpiler.symbols
        );
        Ok(())
    }
}
