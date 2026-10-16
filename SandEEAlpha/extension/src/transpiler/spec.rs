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
    &["upper", "to_upper"],
];

const SEQ_ATTRS: &'static [&'static [&'static str]] = &[&["count", "count"], &["index", "get"]];

const LIST_ATTRS: &'static [&'static [&'static str]] = &[
    &["append", "append"],
    &["clear", "clear"],
    &["copy", "duplicate"],
    &["extend", "append_array"],
    &["insert", "insert"],
    &["pop", "pop_back"],
    &["remove", "erase"],
    &["reverse", "reverse"],
];

const DICT_ATTRS: &'static [&'static [&'static str]] = &[
    &["clear", "clear"],
    &["copy", "duplicate"],
    &["get", "get"],
    &["keys", "keys"],
    &["setdefault", "get_or_add"],
    &["update", "merge"],
    &["values", "values"],
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
            // Anything else (BinOp, Compare, ...) only feeds attribute lookups,
            // so fall back to Any rather than failing the whole transpile —
            // `total = a + b` is valid Python and must not error here.
            _ => Ok(Self::Any),
        }
    }

    pub fn has_attr<'a>(&self, attr: &'a str) -> Option<Vec<&'a str>> {
        match self {
            Self::None | Self::Number | Self::Bool | Self::Callable => None,
            Self::String => {
                if let Some(found_attr) = STRING_ATTRS.iter().find(|a| a[0] == attr) {
                    Some(found_attr[1..].to_vec())
                } else {
                    None
                }
            }
            Self::Dict => {
                if let Some(found_attr) = DICT_ATTRS.iter().find(|a| a[0] == attr) {
                    Some(found_attr[1..].to_vec())
                } else {
                    None
                }
            }
            Self::Tuple => {
                if let Some(found_attr) = SEQ_ATTRS.iter().find(|a| a[0] == attr) {
                    Some(found_attr[1..].to_vec())
                } else {
                    None
                }
            }
            Self::List => {
                if let Some(found_attr) = SEQ_ATTRS
                    .iter()
                    .chain(LIST_ATTRS.iter())
                    .find(|a| a[0] == attr)
                {
                    Some(found_attr[1..].to_vec())
                } else {
                    None
                }
            }
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
                Arguments::new(false, true, 1, Vec::new()),
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
            // ── Crafting Station automation API ──────────────────────
            // Implemented by resources/godot_station_base.gd (the base used by
            // a Crafting Station's Python host). Seeding them here lets the
            // transpiler accept the calls; a program that uses them outside a
            // station host compiles against that host's base and reports a
            // normal "function not found" error instead.
            Symbol::Function(
                "craft".to_string(),
                Arguments::new(false, false, 1, Vec::new()),
            ),
            Symbol::Function(
                "get_recipe".to_string(),
                Arguments::new(false, false, 0, Vec::new()),
            ),
            Symbol::Function(
                "set_recipe".to_string(),
                Arguments::new(false, false, 1, Vec::new()),
            ),
            Symbol::Function(
                "output_item".to_string(),
                Arguments::new(false, false, 0, Vec::new()),
            ),
            Symbol::Function(
                "output_count".to_string(),
                Arguments::new(false, false, 0, Vec::new()),
            ),
            Symbol::Function(
                "take_output".to_string(),
                Arguments::new(false, false, 0, Vec::new()),
            ),
            // ── Furnace automation API ───────────────────────────────
            // Implemented by resources/godot_furnace_base.gd (the base used by
            // a Furnace's Python host). output_count / take_output above are
            // shared with the station.
            Symbol::Function(
                "feed".to_string(),
                Arguments::new(false, false, 2, Vec::new()),
            ),
            Symbol::Function(
                "fuel".to_string(),
                Arguments::new(false, false, 2, Vec::new()),
            ),
            Symbol::Function(
                "smelt".to_string(),
                Arguments::new(false, false, 1, Vec::new()),
            ),
            Symbol::Function(
                "input_name".to_string(),
                Arguments::new(false, false, 0, Vec::new()),
            ),
            Symbol::Function(
                "input_count".to_string(),
                Arguments::new(false, false, 0, Vec::new()),
            ),
            Symbol::Function(
                "fuel_name".to_string(),
                Arguments::new(false, false, 0, Vec::new()),
            ),
            Symbol::Function(
                "fuel_count".to_string(),
                Arguments::new(false, false, 0, Vec::new()),
            ),
            Symbol::Function(
                "output_name".to_string(),
                Arguments::new(false, false, 0, Vec::new()),
            ),
        ]]
    }
}
