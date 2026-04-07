use mlua::{FromLua, Lua, MetaMethod, UserData, UserDataFields, UserDataMethods, Value};

#[derive(Clone, Copy)]
pub struct LuaVector {
    pub x: f32,
    pub y: f32,
}

impl LuaVector {
    pub fn new(x: f32, y: f32) -> Self {
        Self { x, y }
    }
}

impl UserData for LuaVector {
    fn add_fields<F: UserDataFields<Self>>(fields: &mut F) {
        // set x and y
        fields.add_field_method_get("x", |_, this| Ok(this.x));
        fields.add_field_method_get("y", |_, this| Ok(this.y));
        // get x and y
        fields.add_field_method_set("x", |_, this, x| {
            this.x = x;
            Ok(())
        });
        fields.add_field_method_set("y", |_, this, y| {
            this.y = y;
            Ok(())
        });
    }

    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        // vector operations
        methods.add_meta_function(MetaMethod::Add, |_, (this, other): (Self, Self)| {
            Ok(Self::new(this.x + other.x, this.y + other.y))
        });
    }
}

impl FromLua for LuaVector {
    fn from_lua(value: Value, _: &Lua) -> mlua::Result<Self> {
        match value {
            Value::UserData(data) => Ok(*data.borrow::<Self>()?),
            _ => unreachable!(),
        }
    }
}
