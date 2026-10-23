//! Checked access to the pinned schema. Byte vectors retain their Bytes owner.
use super::{flatbuffers_schema as schema, ParseError};
use bytes::Bytes;
use std::{collections::HashMap, sync::Arc};

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
// Keys come only from the pinned schema. A sorted contiguous table avoids
// allocating B-tree nodes for each small root/message dictionary. Application
// dictionaries keep their existing maps and are not stored here.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(super) struct Fields(Vec<(&'static str, Value)>);
impl Fields {
    pub(super) fn new() -> Self {
        Self::default()
    }
    pub(super) fn with_capacity(capacity: usize) -> Self {
        Self(Vec::with_capacity(capacity))
    }
    pub(super) fn get(&self, key: &str) -> Option<&Value> {
        self.0
            .binary_search_by_key(&key, |(name, _)| *name)
            .ok()
            .map(|index| &self.0[index].1)
    }
    pub(super) fn get_mut(&mut self, key: &str) -> Option<&mut Value> {
        let index = self.0.binary_search_by_key(&key, |(name, _)| *name).ok()?;
        Some(&mut self.0[index].1)
    }
    pub(super) fn remove(&mut self, key: &str) -> Option<Value> {
        let index = self.0.binary_search_by_key(&key, |(name, _)| *name).ok()?;
        Some(self.0.remove(index).1)
    }
    pub(super) fn insert(&mut self, key: &'static str, value: Value) -> Option<Value> {
        match self.0.binary_search_by_key(&key, |(name, _)| *name) {
            Ok(index) => Some(std::mem::replace(&mut self.0[index].1, value)),
            Err(index) => {
                self.0.insert(index, (key, value));
                None
            }
        }
    }
    pub(super) fn keys(&self) -> impl Iterator<Item = &&'static str> {
        self.0.iter().map(|(name, _)| name)
    }
}
impl IntoIterator for Fields {
    type Item = (&'static str, Value);
    type IntoIter = std::vec::IntoIter<Self::Item>;
    fn into_iter(self) -> Self::IntoIter {
        self.0.into_iter()
    }
}
impl Extend<(&'static str, Value)> for Fields {
    fn extend<T: IntoIterator<Item = (&'static str, Value)>>(&mut self, values: T) {
        for (key, value) in values {
            self.insert(key, value);
        }
    }
}
impl<const N: usize> From<[(&'static str, Value); N]> for Fields {
    fn from(values: [(&'static str, Value); N]) -> Self {
        let mut fields = Self::with_capacity(N);
        fields.extend(values);
        fields
    }
}
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
        tables: TableCache::default(),
        strings: StringCache::default(),
        string_bytes: 0,
        elements: 0,
    };
    let root = reader.target(0)?;
    Ok(reader.table(root, schema::ROOT, 1)?.1)
}

type CachedTable = (usize, Option<Arc<Fields>>);

// The common root/message pair fits here. Larger graphs retain randomized
// HashMap lookup instead of paying an unbounded linear search cost.
#[derive(Default)]
struct TableCache {
    inline: [Option<((usize, usize), CachedTable)>; 4],
    used: usize,
    overflow: Option<HashMap<(usize, usize), CachedTable>>,
}
impl TableCache {
    fn get(&self, key: &(usize, usize)) -> Option<&CachedTable> {
        for (candidate, value) in self.inline[..self.used].iter().flatten() {
            if candidate == key {
                return Some(value);
            }
        }
        self.overflow.as_ref()?.get(key)
    }
    fn insert(&mut self, key: (usize, usize), value: CachedTable) {
        for (candidate, existing) in self.inline[..self.used].iter_mut().flatten() {
            if *candidate == key {
                *existing = value;
                return;
            }
        }
        if self.used < self.inline.len() {
            self.inline[self.used] = Some((key, value));
            self.used += 1;
        } else {
            self.overflow
                .get_or_insert_with(HashMap::new)
                .insert(key, value);
        }
    }
    fn len(&self) -> usize {
        self.used + self.overflow.as_ref().map_or(0, HashMap::len)
    }
}

// Common messages have only a few wire strings. Keep their offsets inline;
// larger graphs retain randomized lookup rather than an unbounded linear scan.
#[derive(Default)]
struct StringCache {
    inline: Option<[Option<(usize, Arc<str>)>; 4]>,
    used: usize,
    overflow: Option<HashMap<usize, Arc<str>>>,
}
impl StringCache {
    fn get(&self, key: &usize) -> Option<&Arc<str>> {
        let inline = self.inline.as_ref()?;
        for (candidate, value) in inline[..self.used].iter().flatten() {
            if candidate == key {
                return Some(value);
            }
        }
        self.overflow.as_ref()?.get(key)
    }
    fn insert(&mut self, key: usize, value: Arc<str>) {
        let inline = self.inline.get_or_insert_with(Default::default);
        for (candidate, existing) in inline[..self.used].iter_mut().flatten() {
            if *candidate == key {
                *existing = value;
                return;
            }
        }
        if self.used < inline.len() {
            inline[self.used] = Some((key, value));
            self.used += 1;
        } else {
            self.overflow
                .get_or_insert_with(HashMap::new)
                .insert(key, value);
        }
    }
}

struct Reader {
    bytes: Bytes,
    tables: TableCache,
    strings: StringCache,
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
        // All vtable bytes are bounded/aligned above. Scalars retain declared
        // defaults; absent optional references need no temporary Fields entry.
        let capacity = if spec.fields.len() <= 4 {
            spec.fields.len()
        } else {
            spec.fields
                .iter()
                .enumerate()
                .try_fold(0usize, |count, (slot, field)| {
                    let entry = 4 + slot * 2;
                    let present = field.kind == Kind::Scalar
                        || (entry < vtable_size && self.uint(vtable + entry, 2)? != 0);
                    Ok::<_, ParseError>(count + usize::from(present))
                })?
        };
        let mut fields = Fields::with_capacity(capacity);
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
            // Value decoding/validation above is unconditional for every field.
            if !matches!(&value, Value::Null) {
                fields.insert(field.name, value);
            }
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
        let text: Arc<str> = super::codec_copy_metrics::copy_text_arc(text);
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

#[cfg(test)]
mod copy_tests {
    use super::*;

    #[test]
    fn schema_fields_preserve_sorted_map_lookup_replacement_and_extension() {
        use std::collections::BTreeMap;
        for spec in schema::TABLES {
            for reverse in [false, true] {
                let mut fields = Fields::with_capacity(spec.fields.len());
                let mut expected = BTreeMap::new();
                let mut entries: Vec<_> = spec.fields.iter().enumerate().collect();
                if reverse {
                    entries.reverse();
                }
                for (index, field) in entries {
                    let value = Value::Integer(index as u64);
                    assert_eq!(
                        fields.insert(field.name, value.clone()),
                        expected.insert(field.name, value)
                    );
                }
                assert_eq!(
                    fields.keys().copied().collect::<Vec<_>>(),
                    expected.keys().copied().collect::<Vec<_>>()
                );
                assert_eq!(fields.get("not_a_pinned_field"), None);
                for (key, value) in &expected {
                    assert_eq!(fields.get(key), Some(value));
                }
                let mut replacements = Fields::new();
                if let Some(field) = spec.fields.first() {
                    replacements.insert(field.name, Value::Integer(123));
                }
                fields.extend(replacements.clone());
                expected.extend(replacements);
                assert_eq!(
                    fields.clone().into_iter().collect::<BTreeMap<_, _>>(),
                    expected
                );
                let mut reordered = Fields::new();
                reordered.extend(fields.clone().into_iter().rev());
                assert_eq!(fields, reordered);
                assert!(fields.get_mut("not_a_pinned_field").is_none());
                assert_eq!(fields.remove("not_a_pinned_field"), None);
                for field in spec.fields {
                    *fields.get_mut(field.name).unwrap() = Value::Integer(456);
                    expected.insert(field.name, Value::Integer(456));
                    assert_eq!(fields.remove(field.name), expected.remove(field.name));
                    assert_eq!(
                        fields.keys().copied().collect::<Vec<_>>(),
                        expected.keys().copied().collect::<Vec<_>>()
                    );
                }
                assert_eq!(fields, Fields::new());
            }
        }
    }

    #[test]
    fn fields_duplicate_keys_replace_values_without_copying_borrowed_bytes() {
        let bytes = Bytes::from_static(b"payload");
        let nested = Arc::new(Fields::from([("args", Value::Bytes(bytes.clone()))]));
        let mut fields = Fields::from([
            ("request", Value::Integer(1)),
            ("msg", Value::Table(nested.clone())),
            ("request", Value::Integer(2)),
        ]);
        assert_eq!(fields.get("request"), Some(&Value::Integer(2)));
        assert_eq!(
            fields.insert("request", Value::Null),
            Some(Value::Integer(2))
        );
        let Value::Table(table) = fields.get("msg").unwrap() else {
            panic!("table");
        };
        assert!(Arc::ptr_eq(table, &nested));
        let Value::Bytes(retained) = table.get("args").unwrap() else {
            panic!("bytes");
        };
        assert_eq!(retained.as_ptr(), bytes.as_ptr());
    }
    #[test]
    fn string_cache_keeps_small_sets_inline_and_aliases_after_overflow() {
        let mut cache = StringCache::default();
        assert!(cache.inline.is_none());
        let mut values = Vec::new();
        for offset in 0..12 {
            let value: Arc<str> = format!("value-{offset}").into();
            cache.insert(offset, value.clone());
            assert!(Arc::ptr_eq(cache.get(&offset).unwrap(), &value));
            if offset < 4 {
                assert!(cache.overflow.is_none());
            }
            values.push(value);
        }
        assert_eq!(cache.used, 4);
        assert_eq!(cache.overflow.as_ref().unwrap().len(), 8);
        for (offset, value) in values.iter().enumerate() {
            assert!(Arc::ptr_eq(cache.get(&offset).unwrap(), value));
        }
        assert!(cache.get(&12).is_none());
        for offset in [0, 11] {
            let replacement: Arc<str> = "replacement".into();
            cache.insert(offset, replacement.clone());
            assert!(Arc::ptr_eq(cache.get(&offset).unwrap(), &replacement));
        }
        assert_eq!(cache.used, 4);
        assert_eq!(cache.overflow.as_ref().unwrap().len(), 8);
    }

    #[test]
    fn cached_strings_preserve_the_original_visit_budget() {
        let text = "x".repeat(512 * 1024);
        let mut bytes = (text.len() as u32).to_le_bytes().to_vec();
        bytes.extend_from_slice(text.as_bytes());
        bytes.push(0);
        let mut reader = Reader {
            bytes: Bytes::from(bytes),
            tables: TableCache::default(),
            strings: StringCache::default(),
            string_bytes: 0,
            elements: 0,
        };
        let Value::Text(first) = reader.string(0).unwrap() else {
            panic!("text");
        };
        let Value::Text(second) = reader.string(0).unwrap() else {
            panic!("text");
        };
        assert!(Arc::ptr_eq(&first, &second));
        assert_eq!(reader.string_bytes, 1024 * 1024);
        assert!(reader
            .string(0)
            .unwrap_err()
            .to_string()
            .contains("string budget"));
    }

    #[test]
    fn malformed_strings_are_rejected_before_cache_overflow_allocation() {
        for (last_byte, terminator, reason) in [(0xff, 0, "UTF-8"), (b'x', 1, "string terminator")]
        {
            let mut bytes = Vec::new();
            let mut offsets = Vec::new();
            for index in 0..5 {
                while bytes.len() % 4 != 0 {
                    bytes.push(0);
                }
                offsets.push(bytes.len());
                bytes.extend_from_slice(&1_u32.to_le_bytes());
                bytes.push(if index == 4 { last_byte } else { b'a' + index });
                bytes.push(if index == 4 { terminator } else { 0 });
            }
            let mut reader = Reader {
                bytes: Bytes::from(bytes),
                tables: TableCache::default(),
                strings: StringCache::default(),
                string_bytes: 0,
                elements: 0,
            };
            for offset in &offsets[..4] {
                reader.string(*offset).unwrap();
            }
            assert!(reader.strings.overflow.is_none());
            assert!(reader
                .string(offsets[4])
                .unwrap_err()
                .to_string()
                .contains(reason));
            assert!(reader.strings.overflow.is_none());
        }
    }

    #[test]
    fn string_reader_observes_storage_once_and_retains_cached_aliases() {
        for text in ["", "écho", "routing.name"] {
            let mut bytes = (text.len() as u32).to_le_bytes().to_vec();
            bytes.extend_from_slice(text.as_bytes());
            bytes.push(0);
            let mut reader = Reader {
                bytes: Bytes::from(bytes),
                tables: TableCache::default(),
                strings: StringCache::default(),
                string_bytes: 0,
                elements: 0,
            };
            let before = super::super::codec_copy_metrics::observed_on_current_thread();
            let Value::Text(first) = reader.string(0).unwrap() else {
                panic!("expected text");
            };
            let once = super::super::codec_copy_metrics::observed_on_current_thread();
            assert_eq!(
                once.string_copy_bytes_total - before.string_copy_bytes_total,
                text.len() as u64
            );
            let Value::Text(second) = reader.string(0).unwrap() else {
                panic!("expected text");
            };
            assert!(Arc::ptr_eq(&first, &second));
            assert_eq!(
                super::super::codec_copy_metrics::observed_on_current_thread(),
                once
            );
        }
    }
}
