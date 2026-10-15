//! Logical source bytes in explicit codec buffer copies and key transfers.
//! Scalar encoding and dependency-internal copies are outside these counters.
use flatbuffers::Allocator;
use std::convert::Infallible;
use std::ops::{Deref, DerefMut};
use std::sync::atomic::{AtomicU64, Ordering};

static VECTOR: AtomicU64 = AtomicU64::new(0);
static STRING: AtomicU64 = AtomicU64::new(0);
static GROWTH: AtomicU64 = AtomicU64::new(0);
static PARSER_READ: AtomicU64 = AtomicU64::new(0);
static FRAMING: AtomicU64 = AtomicU64::new(0);
static KEY_MATERIAL: AtomicU64 = AtomicU64::new(0);

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CodecCopyMetricsSnapshot {
    pub vector_copy_bytes_total: u64,
    pub string_copy_bytes_total: u64,
    pub growth_copy_bytes_total: u64,
    pub parser_read_copy_bytes_total: u64,
    pub framing_copy_bytes_total: u64,
    pub key_material_copy_bytes_total: u64,
}

pub fn codec_copy_metrics_snapshot() -> CodecCopyMetricsSnapshot {
    CodecCopyMetricsSnapshot {
        vector_copy_bytes_total: VECTOR.load(Ordering::Relaxed),
        string_copy_bytes_total: STRING.load(Ordering::Relaxed),
        growth_copy_bytes_total: GROWTH.load(Ordering::Relaxed),
        parser_read_copy_bytes_total: PARSER_READ.load(Ordering::Relaxed),
        framing_copy_bytes_total: FRAMING.load(Ordering::Relaxed),
        key_material_copy_bytes_total: KEY_MATERIAL.load(Ordering::Relaxed),
    }
}

#[cfg(test)]
thread_local! {
    static OBSERVED: std::cell::Cell<CodecCopyMetricsSnapshot> = const {
        std::cell::Cell::new(CodecCopyMetricsSnapshot {
            vector_copy_bytes_total: 0,
            string_copy_bytes_total: 0,
            growth_copy_bytes_total: 0,
            parser_read_copy_bytes_total: 0,
            framing_copy_bytes_total: 0,
            key_material_copy_bytes_total: 0,
        })
    };
}

pub fn record_vector_copy(bytes: usize) {
    if bytes == 0 {
        return;
    }
    VECTOR.fetch_add(bytes as u64, Ordering::Relaxed);
    #[cfg(test)]
    OBSERVED.with(|cell| {
        let mut value = cell.get();
        value.vector_copy_bytes_total += bytes as u64;
        cell.set(value);
    });
}

pub(super) fn record_string_copy(bytes: usize) {
    if bytes == 0 {
        return;
    }
    STRING.fetch_add(bytes as u64, Ordering::Relaxed);
    #[cfg(test)]
    OBSERVED.with(|cell| {
        let mut value = cell.get();
        value.string_copy_bytes_total += bytes as u64;
        cell.set(value);
    });
}

/// UTF-8 strings retain real byte storage even when used as routing scalars.
/// Reference-counted aliases are observed at construction, never on Arc::clone.
pub fn copy_codec_string(value: &str) -> String {
    let copied = value.to_owned();
    record_string_copy(copied.len());
    copied
}

pub(super) fn copy_text_arc(value: &str) -> std::sync::Arc<str> {
    let copied = std::sync::Arc::from(value);
    record_string_copy(value.len());
    copied
}

fn record_value_clone(value: &serde_value::Value) {
    use serde_value::Value;
    match value {
        Value::String(value) => record_string_copy(value.len()),
        Value::Bytes(value) => record_vector_copy(value.len()),
        Value::Seq(values) => values.iter().for_each(record_value_clone),
        Value::Map(values) => values.iter().for_each(|(key, value)| {
            record_value_clone(key);
            record_value_clone(value);
        }),
        Value::Option(Some(value)) | Value::Newtype(value) => record_value_clone(value),
        _ => {}
    }
}

pub fn clone_codec_value(value: &serde_value::Value) -> serde_value::Value {
    let copied = value.clone();
    record_value_clone(value);
    copied
}

pub fn clone_codec_map(value: &super::ValueMap) -> super::ValueMap {
    let copied = value.clone();
    for (key, value) in value {
        record_value_clone(key);
        record_value_clone(value);
    }
    copied
}

pub(super) fn clone_codec_values(values: &[serde_value::Value]) -> Vec<serde_value::Value> {
    let copied = values.to_vec();
    values.iter().for_each(record_value_clone);
    copied
}

pub(super) fn record_growth_copy(bytes: usize) {
    if bytes == 0 {
        return;
    }
    GROWTH.fetch_add(bytes as u64, Ordering::Relaxed);
    #[cfg(test)]
    OBSERVED.with(|cell| {
        let mut value = cell.get();
        value.growth_copy_bytes_total += bytes as u64;
        cell.set(value);
    });
}

pub(super) fn record_parser_read_copy(bytes: usize) {
    if bytes == 0 {
        return;
    }
    PARSER_READ.fetch_add(bytes as u64, Ordering::Relaxed);
    #[cfg(test)]
    OBSERVED.with(|cell| {
        let mut value = cell.get();
        value.parser_read_copy_bytes_total += bytes as u64;
        cell.set(value);
    });
}

pub fn record_key_material_copy(bytes: usize) {
    if bytes == 0 {
        return;
    }
    KEY_MATERIAL.fetch_add(bytes as u64, Ordering::Relaxed);
    #[cfg(test)]
    OBSERVED.with(|cell| {
        let mut value = cell.get();
        value.key_material_copy_bytes_total += bytes as u64;
        cell.set(value);
    });
}
pub fn record_framing_copy(bytes: usize) {
    if bytes == 0 {
        return;
    }
    FRAMING.fetch_add(bytes as u64, Ordering::Relaxed);
    #[cfg(test)]
    OBSERVED.with(|cell| {
        let mut value = cell.get();
        value.framing_copy_bytes_total += bytes as u64;
        cell.set(value);
    });
}

/// Preserve collapse-to-Vec ownership while observing the actual downward move.
/// New storage never resizes the old Vec, avoiding an unobserved Vec relocation.
pub(super) struct CodecAllocator {
    bytes: Vec<u8>,
}
impl CodecAllocator {
    pub(super) fn with_capacity(size: usize) -> Self {
        Self {
            bytes: vec![0; size],
        }
    }
    pub(super) fn into_vec(self) -> Vec<u8> {
        self.bytes
    }
}
impl Deref for CodecAllocator {
    type Target = [u8];
    fn deref(&self) -> &[u8] {
        &self.bytes
    }
}
impl DerefMut for CodecAllocator {
    fn deref_mut(&mut self) -> &mut [u8] {
        &mut self.bytes
    }
}
// SAFETY: growth preserves the entire old slice at the end of larger storage;
// the new prefix is zeroed and len always matches the accessible byte slice.
unsafe impl Allocator for CodecAllocator {
    type Error = Infallible;
    fn grow_downwards(&mut self) -> Result<(), Self::Error> {
        let old = self.bytes.len();
        let new = old
            .checked_mul(2)
            .expect("FlatBuffer capacity overflow")
            .max(1);
        let mut replacement = vec![0; new];
        replacement[new - old..].copy_from_slice(&self.bytes);
        record_growth_copy(old);
        self.bytes = replacement;
        Ok(())
    }
    fn len(&self) -> usize {
        self.bytes.len()
    }
}

#[cfg(test)]
pub(super) fn observed_on_current_thread() -> CodecCopyMetricsSnapshot {
    OBSERVED.with(std::cell::Cell::get)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn nested_model_clones_count_owned_utf8_and_byte_vectors_once() {
        use serde_value::Value;
        let nested = Value::Seq(vec![
            Value::String("é".to_owned()),
            Value::Bytes(vec![1, 2, 3]),
            Value::U64(71),
        ]);
        let wrapped = Value::Newtype(Box::new(Value::Option(Some(Box::new(nested)))));
        let map = super::super::ValueMap::from([(Value::String("k".to_owned()), wrapped)]);
        let before = observed_on_current_thread();
        assert_eq!(clone_codec_map(&map), map);
        let after = observed_on_current_thread();
        assert_eq!(
            after.string_copy_bytes_total - before.string_copy_bytes_total,
            3
        );
        assert_eq!(
            after.vector_copy_bytes_total - before.vector_copy_bytes_total,
            3
        );
        let value = Value::Map(map);
        assert_eq!(clone_codec_value(&value), value);
        assert_eq!(clone_codec_values(&[value.clone()]), vec![value]);
        let after_more = observed_on_current_thread();
        assert_eq!(
            after_more.string_copy_bytes_total - after.string_copy_bytes_total,
            6
        );
        assert_eq!(
            after_more.vector_copy_bytes_total - after.vector_copy_bytes_total,
            6
        );
    }

    #[test]
    fn explicit_utf8_storage_clones_and_arc_aliases_have_distinct_counts() {
        for text in ["", "écho", "routing.name"] {
            let before = observed_on_current_thread();
            assert_eq!(copy_codec_string(text), text);
            let arc = copy_text_arc(text);
            let _alias = arc.clone();
            let after = observed_on_current_thread();
            assert_eq!(
                after.string_copy_bytes_total - before.string_copy_bytes_total,
                2 * text.len() as u64
            );
        }
    }

    #[test]
    fn growth_preserves_the_old_suffix_and_counts_actual_bytes() {
        let before = observed_on_current_thread();
        let mut allocator = CodecAllocator::with_capacity(8);
        allocator.bytes.copy_from_slice(&[1, 2, 3, 4, 5, 6, 7, 8]);
        allocator.grow_downwards().unwrap();
        assert_eq!(&allocator[..8], &[0; 8]);
        assert_eq!(&allocator[8..], &[1, 2, 3, 4, 5, 6, 7, 8]);
        assert_eq!(
            observed_on_current_thread().growth_copy_bytes_total - before.growth_copy_bytes_total,
            8
        );
    }
    #[test]
    fn empty_growth_initializes_without_inventing_copied_bytes() {
        let before = observed_on_current_thread();
        let mut allocator = CodecAllocator::with_capacity(0);
        allocator.grow_downwards().unwrap();
        assert_eq!(&*allocator, &[0]);
        assert_eq!(observed_on_current_thread(), before);
        allocator.bytes[0] = 9;
        allocator.grow_downwards().unwrap();
        assert_eq!(allocator.into_vec(), vec![0, 9]);
        assert_eq!(
            observed_on_current_thread().growth_copy_bytes_total - before.growth_copy_bytes_total,
            1
        );
    }
    #[test]
    fn preallocated_builder_matches_default_wire_bytes_without_growth() {
        use flatbuffers::FlatBufferBuilder;
        let before = observed_on_current_thread();
        let mut observed = FlatBufferBuilder::new_in(CodecAllocator::with_capacity(256));
        let vector = observed.create_vector(&[3u8, 5, 7]);
        observed.finish(vector, None);
        let (allocator, start) = observed.collapse_in();
        let bytes = allocator.into_vec();
        let mut baseline = FlatBufferBuilder::with_capacity(256);
        let vector = baseline.create_vector(&[3u8, 5, 7]);
        baseline.finish(vector, None);
        assert_eq!(&bytes[start..], baseline.finished_data());
        assert_eq!(observed_on_current_thread(), before);
    }
}
