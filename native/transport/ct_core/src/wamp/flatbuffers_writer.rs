//! Schema-driven construction with the pinned FlatBuffers runtime.
use super::{
    codec_copy_metrics::{self, CodecAllocator},
    flatbuffers_schema as schema,
    flatbuffers_wire::{self as wire, FieldSpec, Fields, Kind, Value},
    ParseError,
};
use bytes::Bytes;
use flatbuffers::{FlatBufferBuilder, TableFinishedWIPOffset, UnionWIPOffset, WIPOffset};

// The common opaque-PPT control frame fits in 256 bytes. Starting at that
// size avoids repeated growth while retaining its previous final allocation.
pub(super) fn write(fields: &Fields) -> Result<Bytes, ParseError> {
    let mut writer = Writer {
        builder: FlatBufferBuilder::new_in(CodecAllocator::with_capacity(256)),
        strings: 0,
        elements: 0,
        tables: 0,
        estimated: 0,
        deferred: None,
        terminal_vector: None,
    };
    let root = writer.table(fields, schema::ROOT, 1)?;
    writer.builder.finish(root, None);
    let (allocation, start) = writer.builder.collapse_in();
    let bytes = Bytes::from(allocation.into_vec()).slice(start..);
    if bytes.len() > wire::MAX_BYTES {
        return Err(wire::invalid("byte limit"));
    }
    Ok(bytes)
}
// Derive bounded staging storage from the pinned schema, including future
// schema additions, instead of allocating a temporary vector for each table.
const MAX_TABLE_FIELDS: usize = {
    let mut maximum = 0;
    let mut index = 0;
    while index < schema::TABLES.len() {
        let count = schema::TABLES[index].fields.len();
        if count > maximum {
            maximum = count;
        }
        index += 1;
    }
    maximum
};

enum Slot {
    Scalar(u64),
    Offset(WIPOffset<UnionWIPOffset>),
    Borrowed(WIPOffset<UnionWIPOffset>, Bytes),
}
struct DeferredVector {
    table: u32,
    slot: u16,
    bytes: Bytes,
}
struct Writer<'a> {
    builder: FlatBufferBuilder<'a, CodecAllocator>,
    strings: usize,
    elements: usize,
    tables: usize,
    estimated: usize,
    deferred: Option<Vec<DeferredVector>>,
    terminal_vector: Option<WIPOffset<UnionWIPOffset>>,
}

/// Keep application vectors in their existing owners and append them after the
/// newly built envelope. Only bounded metadata and vector headers are allocated.
pub(super) fn write_segments(fields: &Fields) -> Result<Vec<Bytes>, ParseError> {
    let mut builder = FlatBufferBuilder::new_in(CodecAllocator::with_capacity(256));
    // The builder grows backwards. A vector created first ends the envelope,
    // so its header can directly precede one borrowed application span.
    let single_vector = match fields.get("msg") {
        Some(Value::Table(body)) => {
            ["args", "kwargs", "payload"]
                .iter()
                .filter(|key| matches!(body.get(**key), Some(Value::Bytes(_))))
                .count()
                == 1
        }
        _ => false,
    };
    let terminal_vector = single_vector.then(|| builder.create_vector::<u8>(&[]).as_union_value());
    let mut writer = Writer {
        builder,
        strings: 0,
        elements: 0,
        tables: 0,
        estimated: 0,
        deferred: Some(Vec::new()),
        terminal_vector,
    };
    let root = writer.table(fields, schema::ROOT, 1)?;
    writer.builder.finish(root, None);
    let (allocator, start) = writer.builder.collapse_in();
    let mut allocation = allocator.into_vec();
    let mut length = allocation.len() - start;
    let mut deferred = writer.deferred.unwrap_or_default();
    if let Some(vector) = terminal_vector.filter(|_| deferred.len() == 1) {
        let bytes = deferred.pop().unwrap().bytes;
        let header = allocation
            .len()
            .checked_sub(vector.value() as usize)
            .ok_or_else(|| wire::invalid("vector offset"))?;
        if header.checked_add(4) != Some(allocation.len()) {
            return Err(wire::invalid("terminal vector offset"));
        }
        length = length
            .checked_add(bytes.len())
            .ok_or_else(|| wire::invalid("byte limit"))?;
        if length > wire::MAX_BYTES {
            return Err(wire::invalid("byte limit"));
        }
        let count = u32::try_from(bytes.len()).map_err(|_| wire::invalid("vector limit"))?;
        allocation[header..].copy_from_slice(&count.to_le_bytes());
        return Ok(vec![Bytes::from(allocation).slice(start..), bytes]);
    }
    let mut segments = vec![Bytes::new()];
    for vector in deferred {
        let table = allocation
            .len()
            .checked_sub(vector.table as usize)
            .ok_or_else(|| wire::invalid("table offset"))?;
        let distance = i32::from_le_bytes(
            allocation
                .get(table..table + 4)
                .ok_or_else(|| wire::invalid("table offset"))?
                .try_into()
                .unwrap(),
        );
        let vtable = usize::try_from((table as i64) - i64::from(distance))
            .map_err(|_| wire::invalid("vtable offset"))?;
        let slot = vtable + usize::from(vector.slot);
        let field_offset = u16::from_le_bytes(
            allocation
                .get(slot..slot + 2)
                .ok_or_else(|| wire::invalid("vtable slot"))?
                .try_into()
                .unwrap(),
        );
        if field_offset == 0 {
            return Err(wire::invalid("missing vector slot"));
        }
        let field = table + usize::from(field_offset);
        let relative_field = field
            .checked_sub(start)
            .ok_or_else(|| wire::invalid("vector slot"))?;
        // The vector header is four-byte aligned and its borrowed data starts
        // at an eight-byte boundary in the assembled wire frame.
        let padding = (12 - length % 8) % 8;
        let target = length
            .checked_add(padding)
            .ok_or_else(|| wire::invalid("byte limit"))?;
        length = target
            .checked_add(4)
            .and_then(|n| n.checked_add(vector.bytes.len()))
            .ok_or_else(|| wire::invalid("byte limit"))?;
        if length > wire::MAX_BYTES {
            return Err(wire::invalid("byte limit"));
        }
        let offset = u32::try_from(
            target
                .checked_sub(relative_field)
                .ok_or_else(|| wire::invalid("vector offset"))?,
        )
        .map_err(|_| wire::invalid("vector offset"))?;
        allocation
            .get_mut(field..field + 4)
            .ok_or_else(|| wire::invalid("vector slot"))?
            .copy_from_slice(&offset.to_le_bytes());
        let mut header = vec![0; padding + 4];
        let count = u32::try_from(vector.bytes.len()).map_err(|_| wire::invalid("vector limit"))?;
        header[padding..].copy_from_slice(&count.to_le_bytes());
        segments.push(Bytes::from(header));
        segments.push(vector.bytes);
    }
    if length > wire::MAX_BYTES {
        return Err(wire::invalid("byte limit"));
    }
    segments[0] = Bytes::from(allocation).slice(start..);
    Ok(segments)
}
impl Writer<'_> {
    fn charge(&mut self, bytes: usize) -> Result<(), ParseError> {
        self.estimated = self
            .estimated
            .checked_add(bytes)
            .ok_or_else(|| wire::invalid("byte limit"))?;
        if self.estimated > wire::MAX_BYTES {
            return Err(wire::invalid("byte limit"));
        }
        Ok(())
    }
    fn scalar(&self, value: u64, field: &FieldSpec) -> Result<(), ParseError> {
        if (field.wamp_integer && value > 9_007_199_254_740_992)
            || (field.width < 8 && value >= 1u64 << (field.width * 8))
            || (!field.values.is_empty() && !field.values.contains(&(value as i64)))
        {
            return Err(wire::invalid("scalar value"));
        }
        Ok(())
    }
    fn string(&mut self, value: &str) -> Result<WIPOffset<UnionWIPOffset>, ParseError> {
        self.strings = self
            .strings
            .checked_add(value.len())
            .ok_or_else(|| wire::invalid("string limit"))?;
        if self.strings > 1024 * 1024 {
            return Err(wire::invalid("string limit"));
        }
        self.charge(value.len() + 8)?;
        let offset = self.builder.create_string(value).as_union_value();
        codec_copy_metrics::record_string_copy(value.len());
        Ok(offset)
    }
    fn table(
        &mut self,
        fields: &Fields,
        reference: usize,
        depth: usize,
    ) -> Result<WIPOffset<TableFinishedWIPOffset>, ParseError> {
        self.tables += 1;
        if depth > 64 || self.tables > 10000 {
            return Err(wire::invalid("table or depth limit"));
        }
        let spec = schema::TABLES
            .get(reference)
            .ok_or_else(|| wire::invalid("table type"))?;
        if fields
            .keys()
            .any(|key| !spec.fields.iter().any(|field| field.name == *key))
        {
            return Err(wire::invalid("field absent from pinned schema"));
        }
        self.charge(8 + spec.fields.len() * 16)?;
        let mut slots: [Option<Slot>; MAX_TABLE_FIELDS] = std::array::from_fn(|_| None);
        for (index, field) in spec.fields.iter().enumerate() {
            let value = fields.get(field.name).unwrap_or(&Value::Null);
            if *value == Value::Null {
                if field.required {
                    return Err(wire::invalid("missing required field"));
                }
                continue;
            }
            let slot = match (field.kind, value) {
                (Kind::Scalar, Value::Integer(value)) => {
                    self.scalar(*value, field)?;
                    Slot::Scalar(*value)
                }
                (Kind::String, Value::Text(value)) => Slot::Offset(self.string(value)?),
                (Kind::Table | Kind::Union, Value::Table(value)) => {
                    let target = if field.kind == Kind::Union {
                        let Some(Value::Integer(tag)) = fields.get("msg_type") else {
                            return Err(wire::invalid("union discriminator"));
                        };
                        let index = usize::try_from(*tag)
                            .map_err(|_| wire::invalid("union discriminator"))?;
                        usize::try_from(
                            *field
                                .values
                                .get(index)
                                .ok_or_else(|| wire::invalid("union discriminator"))?,
                        )
                        .map_err(|_| wire::invalid("union discriminator"))?
                    } else {
                        field.reference
                    };
                    Slot::Offset(self.table(value, target, depth + 1)?.as_union_value())
                }
                (Kind::ScalarVector, Value::Bytes(bytes)) if field.width == 1 => {
                    self.charge(bytes.len() + 8)?;
                    if self.deferred.is_some()
                        && matches!(field.name, "args" | "kwargs" | "payload")
                    {
                        let offset = self.terminal_vector.take().unwrap_or_else(|| {
                            self.builder.create_vector::<u8>(&[]).as_union_value()
                        });
                        Slot::Borrowed(offset, bytes.clone())
                    } else {
                        let offset = self.builder.create_vector(bytes.as_ref()).as_union_value();
                        codec_copy_metrics::record_vector_copy(bytes.len());
                        Slot::Offset(offset)
                    }
                }
                (
                    Kind::ScalarVector | Kind::StringVector | Kind::TableVector,
                    Value::Vector(values),
                ) => {
                    self.elements = self
                        .elements
                        .checked_add(values.len())
                        .ok_or_else(|| wire::invalid("vector limit"))?;
                    if self.elements > 1000000 {
                        return Err(wire::invalid("vector limit"));
                    }
                    self.charge(values.len() * field.width + 8)?;
                    let offset = match field.kind {
                        Kind::StringVector => {
                            let mut offsets = Vec::with_capacity(values.len());
                            for value in values {
                                let Value::Text(value) = value else {
                                    return Err(wire::invalid("string vector"));
                                };
                                offsets.push(self.string(value)?);
                            }
                            self.builder.create_vector(&offsets).as_union_value()
                        }
                        Kind::TableVector => {
                            let mut offsets = Vec::with_capacity(values.len());
                            for value in values {
                                let Value::Table(value) = value else {
                                    return Err(wire::invalid("table vector"));
                                };
                                offsets.push(self.table(value, field.reference, depth + 1)?);
                            }
                            self.builder.create_vector(&offsets).as_union_value()
                        }
                        _ => {
                            let mut integers = Vec::with_capacity(values.len());
                            for value in values {
                                let Value::Integer(value) = value else {
                                    return Err(wire::invalid("scalar vector"));
                                };
                                self.scalar(*value, field)?;
                                integers.push(*value);
                            }
                            match field.width {
                                1 => self
                                    .builder
                                    .create_vector(
                                        &integers.iter().map(|v| *v as u8).collect::<Vec<_>>(),
                                    )
                                    .as_union_value(),
                                2 => self
                                    .builder
                                    .create_vector(
                                        &integers.iter().map(|v| *v as u16).collect::<Vec<_>>(),
                                    )
                                    .as_union_value(),
                                4 => self
                                    .builder
                                    .create_vector(
                                        &integers.iter().map(|v| *v as u32).collect::<Vec<_>>(),
                                    )
                                    .as_union_value(),
                                8 => self.builder.create_vector(&integers).as_union_value(),
                                _ => return Err(wire::invalid("scalar width")),
                            }
                        }
                    };
                    Slot::Offset(offset)
                }
                _ => return Err(wire::invalid("field type")),
            };
            slots[index] = Some(slot);
        }
        let start = self.builder.start_table();
        for (index, (field, slot)) in spec.fields.iter().zip(slots.iter()).enumerate().rev() {
            let offset = (4 + index * 2) as u16;
            match slot {
                Some(Slot::Offset(value) | Slot::Borrowed(value, _)) => {
                    self.builder.push_slot_always(offset, *value)
                }
                Some(Slot::Scalar(value)) => match field.width {
                    1 => self
                        .builder
                        .push_slot(offset, *value as u8, field.default as u8),
                    2 => self
                        .builder
                        .push_slot(offset, *value as u16, field.default as u16),
                    4 => self
                        .builder
                        .push_slot(offset, *value as u32, field.default as u32),
                    8 => self.builder.push_slot(offset, *value, field.default),
                    _ => return Err(wire::invalid("scalar width")),
                },
                None => (),
            }
        }
        let table = self.builder.end_table(start);
        if let Some(deferred) = &mut self.deferred {
            for (index, slot) in slots.into_iter().take(spec.fields.len()).enumerate().rev() {
                if let Some(Slot::Borrowed(_, bytes)) = slot {
                    deferred.push(DeferredVector {
                        table: table.value(),
                        slot: (4 + index * 2) as u16,
                        bytes,
                    });
                }
            }
        }
        Ok(table)
    }
}

#[cfg(test)]
mod copy_tests {
    use super::*;
    #[test]
    fn string_writer_counts_utf8_bytes_once_including_empty_strings() {
        let mut writer = Writer {
            builder: FlatBufferBuilder::new_in(CodecAllocator::with_capacity(256)),
            strings: 0,
            elements: 0,
            tables: 0,
            estimated: 0,
            deferred: None,
            terminal_vector: None,
        };
        for text in ["", "écho", "routing.name"] {
            let before = codec_copy_metrics::observed_on_current_thread();
            writer.string(text).unwrap();
            let after = codec_copy_metrics::observed_on_current_thread();
            assert_eq!(
                after.string_copy_bytes_total - before.string_copy_bytes_total,
                text.len() as u64
            );
            assert_eq!(
                after.vector_copy_bytes_total,
                before.vector_copy_bytes_total
            );
        }
    }
}
