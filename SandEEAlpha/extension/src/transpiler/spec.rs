use anyhow::{Result, anyhow};
use ruff_python_ast::Expr;

const STRING_ATTRS: &'static [&'static [&'static str]] = &[
    &["capitalize", "capitalize"],
    &["endswith", "ends_with"],
    &["find", "find"],
    &["format", "format"],
    &["isdecimal", "is_valid_int"],
    &["isidentifier", "is_valid_ascii_identifier"],
    &["join", "join"],
    &["ljust", "rpad"],
    &["lower", "to_lower"],
    &["lstrip", "lstrip"],
    &["replace", "replace"],
    &["rfind", "rfind"],
    &["rjust", "lpad"],
    &["startswith", "begins_with"],
    &["strip", "rstrip", "lstrip"],
];

#[derive(Debug)]
pub struct Arguments {
    pub has_kwargs: bool,
    pub has_vararg: bool,
    pub num_args: usize,
    pub known_kwargs: Vec<String>,
}

impl Arguments {
    pub fn new(
        has_kwargs: bool,
        has_vararg: bool,
        num_args: usize,
        known_kwargs: Vec<String>,
    ) -> Self {
        Self {
            has_kwargs,
            has_vararg,
            num_args,
            known_kwargs,
        }
    }
}

#[derive(Debug, Clone)]
pub enum PythonType {
    None,
    Any,
    Number,
    Bool,
    String,
    Dict,
    List,
    Tuple,
    Class,
    Callable,
}

impl PythonType {
    pub fn from_expr(value: &Expr, symbols: &SymbolsStack) -> Result<Self> {
        match value {
            Expr::Dict(_) | Expr::DictComp(_) => Ok(Self::Dict),
            Expr::List(_) | Expr::ListComp(_) => Ok(Self::List),
            Expr::FString(_) | Expr::TString(_) | Expr::StringLiteral(_) => Ok(Self::String),
            Expr::NumberLiteral(_) => Ok(Self::Number),
            Expr::BooleanLiteral(_) => Ok(Self::Bool),
            Expr::NoneLiteral(_) => Ok(Self::None),
            Expr::Name(name) => symbols
                .find(&name.id)
                .and_then(|symbol| match symbol {
                    Symbol::Variable(_, var) => Some(var.clone()),
                    Symbol::Class(_, _) => Some(Self::Class),
                    Symbol::Function(_, _) => Some(Self::Callable),
                })
                .ok_or(anyhow!("Cannot find type of {:?}", name)),
            Expr::Tuple(_) => Ok(Self::Tuple),
            Expr::Call(_) => Ok(Self::Any),
            _ => Err(anyhow!("Cannot transform {:?} to a type", value)),
        }
    }

    pub fn has_attr<'a>(&self, attr: &'a str) -> Option<Vec<&'a str>> {
        match self {
            Self::None | Self::Number | Self::Bool | Self::Callable => None,
            _ => Some(vec![attr]),
        }
    }
}

#[derive(Debug)]
pub enum Symbol {
    // name
    Variable(String, PythonType),
    // name, has_kwargs, has_vararg, num_args, known_kwargs
    Function(String, Arguments),
    // name, has_kwargs, has_vararg, num_args, known_kwargs
    Class(String, Arguments),
}

impl Symbol {
    pub fn name(&self) -> &str {
        match self {
            Symbol::Variable(this, _) => this.as_str(),
            Symbol::Function(this, _) => this.as_str(),
            Symbol::Class(this, _) => this.as_str(),
        }
    }
}

impl PartialEq<str> for Symbol {
    fn eq(&self, other: &str) -> bool {
        match self {
            Symbol::Variable(this, _) => this.as_str() == other,
            Symbol::Function(this, _) => this.as_str() == other,
            Symbol::Class(this, _) => this.as_str() == other,
        }
    }
}

#[derive(Debug)]
pub struct SymbolsStack {
    stack: Vec<Vec<Symbol>>,
}

impl Default for SymbolsStack {
    fn default() -> Self {
        Self { stack: Vec::new() }
    }
}

impl SymbolsStack {
    pub fn add_symbol(&mut self, symbol: Symbol) {
        if let Some(last) = self.stack.last_mut() {
            match last.iter_mut().find(|sym| *sym == symbol.name()) {
                Some(existing) => *existing = symbol,
                None => last.push(symbol),
            }
        }
    }

    pub fn exists(&self, name: &str) -> bool {
        self.stack
            .iter()
            .any(|frame| frame.iter().any(|sym| sym == name))
    }

    pub fn find(&self, name: &str) -> Option<&Symbol> {
        for frame in &self.stack {
            let symbol = frame.iter().find(|sym| *sym == name);
            if symbol.is_some() {
                return symbol;
            }
        }
        None
    }

    pub fn push(&mut self) {
        self.stack.push(Vec::new());
    }

    pub fn pop(&mut self) {
        self.stack.pop();
    }

    pub fn reset(&mut self) {
        self.stack = vec![vec![
            Symbol::Function(
                "print".to_string(),
                Arguments::new(
                    false,
                    true,
                    3,
                    vec!["sep", "end"].iter().map(|s| s.to_string()).collect(),
                ),
            ),
            Symbol::Function(
                "create".to_string(),
                Arguments::new(false, false, 1, Vec::new()),
            ),
            Symbol::Function(
                "len".to_string(),
                Arguments::new(false, false, 1, Vec::new()),
            ),
            Symbol::Function(
                "range".to_string(),
                Arguments::new(
                    false,
                    false,
                    3,
                    vec!["end", "step"].iter().map(|s| s.to_string()).collect(),
                ),
            ),
            Symbol::Function(
                "int".to_string(),
                Arguments::new(false, false, 1, Vec::new()),
            ),
            Symbol::Function(
                "float".to_string(),
                Arguments::new(false, false, 1, Vec::new()),
            ),
            Symbol::Function(
                "bool".to_string(),
                Arguments::new(false, false, 1, Vec::new()),
            ),
            Symbol::Function(
                "abs".to_string(),
                Arguments::new(false, false, 1, Vec::new()),
            ),
            Symbol::Function(
                "min".to_string(),
                Arguments::new(false, true, 3, Vec::new()),
            ),
            Symbol::Function(
                "max".to_string(),
                Arguments::new(false, true, 3, Vec::new()),
            ),
            Symbol::Function(
                "pow".to_string(),
                Arguments::new(false, false, 2, Vec::new()),
            ),
        ]]
    }
}
