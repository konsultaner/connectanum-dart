//! Checked access to the pinned schema. Byte vectors retain their Bytes owner.
use super::{flatbuffers_schema as schema, ParseError};
use bytes::Bytes;
use std::{collections::BTreeMap, collections::HashMap, sync::Arc};

pub(super) const MAX_BYTES: usize = 64 * 1024 * 1024;
const MAX_INTEGER: u64 = 9_007_199_254_740_992;

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum Kind {
    Scalar,
    String,
    Table,
    ScalarVector,
    StringVector,
    TableVector,
    Union,
}
pub(super) struct FieldSpec {
    pub name: &'static str,
    pub kind: Kind,
    pub width: usize,
    pub required: bool,
    pub reference: usize,
    pub values: &'static [i64],
    pub wamp_integer: bool,
    pub default: u64,
}
pub(super) struct TableSpec {
    pub name: &'static str,
    pub fields: &'static [FieldSpec],
}
pub(super) type Fields = BTreeMap<&'static str, Value>;
#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) enum Value {
    Null,
    Integer(u64),
    Text(Arc<str>),
    Bytes(Bytes),
    Table(Arc<Fields>),
    Vector(Vec<Value>),
}

pub(super) fn invalid(reason: &'static str) -> ParseError {
    ParseError::Deserialize(format!("Invalid FlatBuffers frame: {reason}"))
}

pub(super) fn read(bytes: Bytes) -> Result<Arc<Fields>, ParseError> {
    if bytes.len() > MAX_BYTES {
        return Err(invalid("byte limit"));
    }
    let mut reader = Reader {
        bytes,
        tables: HashMap::new(),
        strings: HashMap::new(),
        string_bytes: 0,
        elements: 0,
    };
    let root = reader.target(0)?;
    Ok(reader.table(root, schema::ROOT, 1)?.1)
}

struct Reader {
    bytes: Bytes,
    tables: HashMap<(usize, usize), (usize, Option<Arc<Fields>>)>,
    strings: HashMap<usize, Arc<str>>,
    string_bytes: usize,
    elements: usize,
}
impl Reader {
    fn range(&self, offset: usize, length: usize, alignment: usize) -> Result<&[u8], ParseError> {
        let end = offset.checked_add(length).ok_or_else(|| invalid("range"))?;
        if offset % alignment != 0 {
            return Err(invalid("alignment"));
        }
        self.bytes.get(offset..end).ok_or_else(|| invalid("range"))
    }
    fn uint(&self, offset: usize, width: usize) -> Result<u64, ParseError> {
        let data = self.range(offset, width, width)?;
        Ok(match width {
            1 => data[0] as u64,
            2 => u16::from_le_bytes(data.try_into().unwrap()) as u64,
            4 => u32::from_le_bytes(data.try_into().unwrap()) as u64,
            8 => u64::from_le_bytes(data.try_into().unwrap()),
            _ => return Err(invalid("scalar width")),
        })
    }
    fn target(&self, offset: usize) -> Result<usize, ParseError> {
        let relative = self.uint(offset, 4)? as usize;
        if relative < 4 {
            return Err(invalid("non-forward offset"));
        }
        let target = offset
            .checked_add(relative)
            .ok_or_else(|| invalid("offset"))?;
        self.range(target, 4, 4)?;
        Ok(target)
    }
    fn scalar(&self, position: usize, field: &FieldSpec) -> Result<u64, ParseError> {
        let value = self.uint(position, field.width)?;
        if field.wamp_integer && value > MAX_INTEGER {
            return Err(invalid("WAMP integer"));
        }
        if !field.values.is_empty() && !field.values.contains(&(value as i64)) {
            return Err(invalid("enum value"));
        }
        Ok(value)
    }
    fn table(
        &mut self,
        offset: usize,
        reference: usize,
        depth: usize,
    ) -> Result<(usize, Arc<Fields>), ParseError> {
        if depth > 64 {
            return Err(invalid("depth limit"));
        }
        if let Some((height, fields)) = self.tables.get(&(offset, reference)) {
            if *height == 0 {
                return Err(invalid("cyclic table"));
            }
            if depth + height - 1 > 64 {
                return Err(invalid("depth limit"));
            }
            return Ok((*height, fields.as_ref().unwrap().clone()));
        }
        if self.tables.len() >= 10000 {
            return Err(invalid("table limit"));
        }
        self.tables.insert((offset, reference), (0, None));
        let signed = i32::from_le_bytes(self.range(offset, 4, 4)?.try_into().unwrap()) as i64;
        let vtable = usize::try_from(offset as i64 - signed).map_err(|_| invalid("vtable"))?;
        let vtable_size = self.uint(vtable, 2)? as usize;
        let object_size = self.uint(vtable + 2, 2)? as usize;
        if vtable_size < 4 || vtable_size % 2 != 0 || object_size < 4 {
            return Err(invalid("table header"));
        }
        self.range(vtable, vtable_size, 2)?;
        self.range(offset, object_size, 4)?;
        let spec = schema::TABLES
            .get(reference)
            .ok_or_else(|| invalid("table type"))?;
        let mut fields = Fields::new();
        let mut height = 1;
        let mut union_tag = 0;
        for (slot, field) in spec.fields.iter().enumerate() {
            let entry = 4 + slot * 2;
            let relative = if entry < vtable_size {
                self.uint(vtable + entry, 2)? as usize
            } else {
                0
            };
            let value = if relative == 0 {
                if field.required || (field.kind == Kind::Union && union_tag != 0) {
                    return Err(invalid("missing required field"));
                }
                union_tag = 0;
                if field.kind == Kind::Scalar {
                    Value::Integer(field.default)
                } else {
                    Value::Null
                }
            } else {
                let width = if field.kind == Kind::Scalar {
                    field.width
                } else {
                    4
                };
                if relative < 4
                    || relative
                        .checked_add(width)
                        .is_none_or(|end| end > object_size)
                {
                    return Err(invalid("field outside table"));
                }
                let position = offset + relative;
                match field.kind {
                    Kind::Scalar => {
                        let scalar = self.scalar(position, field)?;
                        union_tag = if field.width == 1 { scalar as usize } else { 0 };
                        Value::Integer(scalar)
                    }
                    Kind::String => self.string(self.target(position)?)?,
                    Kind::Table | Kind::Union => {
                        let child_ref = if field.kind == Kind::Union {
                            if union_tag == 0 {
                                return Err(invalid("union discriminator"));
                            }
                            let target = *field
                                .values
                                .get(union_tag)
                                .ok_or_else(|| invalid("union discriminator"))?;
                            usize::try_from(target).map_err(|_| invalid("union discriminator"))?
                        } else {
                            field.reference
                        };
                        let (child_height, child) =
                            self.table(self.target(position)?, child_ref, depth + 1)?;
                        height = height.max(child_height + 1);
                        union_tag = 0;
                        Value::Table(child)
                    }
                    _ => {
                        let (child_height, vector) =
                            self.vector(self.target(position)?, field, depth)?;
                        height = height.max(child_height + 1);
                        vector
                    }
                }
            };
            fields.insert(field.name, value);
        }
        let fields = Arc::new(fields);
        self.tables
            .insert((offset, reference), (height, Some(fields.clone())));
        Ok((height, fields))
    }
    fn string(&mut self, offset: usize) -> Result<Value, ParseError> {
        let length = self.uint(offset, 4)? as usize;
        self.string_bytes = self
            .string_bytes
            .checked_add(length)
            .ok_or_else(|| invalid("string budget"))?;
        if self.string_bytes > 1024 * 1024 {
            return Err(invalid("string budget"));
        }
        if let Some(value) = self.strings.get(&offset) {
            return Ok(Value::Text(value.clone()));
        }
        let start = offset + 4;
        let bytes = self.range(start, length + 1, 1)?;
        if bytes[length] != 0 {
            return Err(invalid("string terminator"));
        }
        let text = std::str::from_utf8(&bytes[..length]).map_err(|_| invalid("UTF-8"))?;
        let text: Arc<str> = Arc::from(text);
        self.strings.insert(offset, text.clone());
        Ok(Value::Text(text))
    }
    fn vector(
        &mut self,
        offset: usize,
        field: &FieldSpec,
        depth: usize,
    ) -> Result<(usize, Value), ParseError> {
        let length = self.uint(offset, 4)? as usize;
        let start = offset + 4;
        let width = if field.kind == Kind::ScalarVector {
            field.width
        } else {
            4
        };
        let bytes = length
            .checked_mul(width)
            .ok_or_else(|| invalid("vector length"))?;
        self.range(start, bytes, width)?;
        if field.kind == Kind::ScalarVector && width == 1 && field.values.is_empty() {
            return Ok((0, Value::Bytes(self.bytes.slice(start..start + bytes))));
        }
        self.elements = self
            .elements
            .checked_add(length)
            .ok_or_else(|| invalid("element budget"))?;
        if self.elements > 1000000 {
            return Err(invalid("element budget"));
        }
        let mut output = Vec::with_capacity(length);
        let mut height = 0;
        for index in 0..length {
            let position = start + index * width;
            output.push(match field.kind {
                Kind::ScalarVector => Value::Integer(self.scalar(position, field)?),
                Kind::StringVector => self.string(self.target(position)?)?,
                Kind::TableVector => {
                    let (child_height, child) =
                        self.table(self.target(position)?, field.reference, depth + 1)?;
                    height = height.max(child_height);
                    Value::Table(child)
                }
                _ => return Err(invalid("vector type")),
            });
        }
        Ok((height, Value::Vector(output)))
    }
}
