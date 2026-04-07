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
