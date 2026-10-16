use anyhow::Result;
use godot::global::godot_error;
#[macro_export]
macro_rules! from_usize_enum {
    ($(#[$meta:meta])* $vis:vis enum $name:ident {
        $first_variant:ident = $first_index:expr,
        $($variant:ident $(= $index:expr)?,)*
    }) => {
        $(#[$meta])*
        $vis enum $name {
            $first_variant = $first_index,
            $($variant $(= $index)?,)*
        }

        impl From<usize> for $name {
            fn from(value: usize) -> Self {
                match value {
                    $(_ if value == $name::$variant as usize => $name::$variant,)*
                    _ => $name::$first_variant
                }
            }
        }
    };
}

pub fn print_as_godot_error<T>(result: Result<T>) -> Option<T> {
    match result {
        Ok(r) => Some(r),
        Err(e) => {
            godot_error!("{:?}", e);
            None
        }
    }
}

// Every item display name in the game, read from the ItemData .tres files under
// res://resources/items/. Used by the editors' list_items() helper so a name
// argument can offer a completion popup. Parses the `item_name = "..."` line of
// each file (cheap — items are simple text resources).
pub fn item_names() -> Vec<String> {
    let mut names: Vec<String> = Vec::new();
    let dir_path = "res://resources/items/";
    let mut dir = match godot::classes::DirAccess::open(dir_path) {
        Some(d) => d,
        None => return names,
    };
    let files = dir.get_files();
    for i in 0..files.len() {
        let fname = match files.get(i) {
            Some(f) => f.to_string(),
            None => continue,
        };
        // Only .tres (skip .tres.remap stubs when exported).
        if !fname.ends_with(".tres") {
            continue;
        }
        if fname.ends_with(".remap") {
            continue;
        }
        let path = format!("{}{}", dir_path, fname);
        let mut f = match godot::classes::FileAccess::open(&path, godot::classes::file_access::ModeFlags::READ) {
            Some(f) => f,
            None => continue,
        };
        let text = f.get_as_text().to_string();
        for line in text.lines() {
            let line = line.trim();
            if let Some(rest) = line.strip_prefix("item_name") {
                if let Some(val) = rest.split('"').nth(1) {
                    if !val.is_empty() && !names.contains(&val.to_string()) {
                        names.push(val.to_string());
                    }
                }
                break;
            }
        }
    }
    names
}

#[cfg(test)]
pub mod test {
    #[test]
    pub fn test_macros() {
        from_usize_enum! {
            #[derive(Debug)]
            enum TestEnum {
                A = 1,
                B,
            }
        }
        match 2.try_into() {
            Ok(TestEnum::A) => println!("a"),
            Ok(TestEnum::B) => println!("b"),
            Err(_) => println!("oh"),
        }
    }
}
