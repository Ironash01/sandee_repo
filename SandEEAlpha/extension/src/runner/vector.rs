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
        // vector construction (method)
        methods.add_method("new", |_, _, (x, y): (f32, f32)| Ok(Self::new(x, y)));
        methods.add_method("from_angle", |_, _, angle: f32| {
            let (s, c) = angle.sin_cos();
            Ok(Self::new(c, s))
        });
        methods.add_method("with_mag", |_, this, mag: f32| {
            let this_mag = (this.x * this.x + this.y * this.y).sqrt();
            Ok(Self::new(mag * this.x / this_mag, mag * this.y / this_mag))
        });
        // vector operations (method)
        methods.add_method("mag", |_, this, ()| {
            Ok((this.x * this.x + this.y * this.y).sqrt())
        });
        methods.add_method(
            "mag_sq",
            |_, this, ()| Ok(this.x * this.x + this.y * this.y),
        );
        methods.add_method("dot", |_, this, other: Self| {
            Ok(this.x * other.x + this.y * other.y)
        });
        methods.add_method("normalized", |_, this, ()| {
            let mag = (this.x * this.x + this.y * this.y).sqrt();
            Ok(Self::new(this.x / mag, this.y / mag))
        });
        methods.add_method_mut("normalize", |_, this, ()| {
            let mag = (this.x * this.x + this.y * this.y).sqrt();
            this.x /= mag;
            this.y /= mag;
            Ok(())
        });
        methods.add_method("cross", |_, this, other: Self| {
            Ok(this.x * other.y - this.y * other.x)
        });
        // vector operations (metamethod)
        // add
        methods.add_meta_function(
            MetaMethod::Add,
            |_, (this, other): (Self, Value)| match other {
                Value::Integer(o) => Ok(Self::new(this.x + o as f32, this.y + o as f32)),
                Value::Number(o) => Ok(Self::new(this.x + o as f32, this.y + o as f32)),
                Value::UserData(o) => {
                    let o: Self = *o.borrow()?;
                    Ok(Self::new(this.x + o.x, this.y + o.y))
                }
                _ => Err(mlua::Error::RuntimeError(String::from(
                    "only number and vector types are supported for this operation.",
                ))),
            },
        );
        // subtract
        methods.add_meta_function(
            MetaMethod::Sub,
            |_, (this, other): (Self, Value)| match other {
                Value::Integer(o) => Ok(Self::new(this.x - o as f32, this.y - o as f32)),
                Value::Number(o) => Ok(Self::new(this.x - o as f32, this.y - o as f32)),
                Value::UserData(o) => {
                    let o: Self = *o.borrow()?;
                    Ok(Self::new(this.x - o.x, this.y - o.y))
                }
                _ => Err(mlua::Error::RuntimeError(String::from(
                    "only number and vector types are supported for this operation.",
                ))),
            },
        );
        // negate
        methods.add_meta_function(MetaMethod::Unm, |_, this: Self| {
            Ok(Self::new(-this.x, -this.y))
        });
        // multiply
        methods.add_meta_function(MetaMethod::Mul, |_, (this, other): (Self, f32)| {
            Ok(Self::new(this.x * other, this.y * other))
        });
        // divide
        methods.add_meta_function(MetaMethod::Div, |_, (this, other): (Self, f32)| {
            Ok(Self::new(this.x / other, this.y / other))
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
