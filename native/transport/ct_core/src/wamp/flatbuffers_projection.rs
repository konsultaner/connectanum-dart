use super::{
    flatbuffers_schema as schema,
    flatbuffers_wire::{self as wire, FieldSpec, Fields, Kind, Value},
    ParseError, ValueMap,
};
use serde_value::Value as Cbor;
use std::sync::Arc;

pub(super) fn agree(
    name: &str,
    body: &Fields,
    dictionary: &ValueMap,
    reference: usize,
) -> Result<(), ParseError> {
    let expected = project(name, dictionary, reference)?;
    for field in schema::TABLES[reference].fields {
        if ignored(name, field.name) {
            continue;
        }
        let actual = body.get(field.name).unwrap_or(&Value::Null);
        let target = expected.get(field.name).unwrap_or(&Value::Null);
        if field.kind == Kind::Table && schema::TABLES[field.reference].name == "Map" {
            if let Value::Table(pair) = actual {
                let source =
                    if field.name == "extra" && ["Challenge", "Authenticate"].contains(&name) {
                        Some(dictionary)
                    } else {
                        match get(dictionary, field.name) {
                            Some(Cbor::Map(map)) => Some(map),
                            _ => None,
                        }
                    };
                let key = match pair.get("key") {
                    Some(Value::Text(key)) => key,
                    _ => return Err(wire::invalid("map key")),
                };
                let value = match pair.get("value") {
                    Some(Value::Text(value)) => Some(Cbor::String(
                        super::codec_copy_metrics::copy_codec_string(value),
                    )),
                    Some(Value::Null) => Some(Cbor::Unit),
                    _ => None,
                };
                if value.as_ref().is_none_or(|value| {
                    source
                        .and_then(|map| get(map, key))
                        .is_none_or(|item| item != value)
                }) {
                    return Err(wire::invalid("contradictory Map metadata"));
                }
                continue;
            }
        }
        if !matches(field, actual, target)? {
            return Err(wire::invalid("contradictory metadata"));
        }
    }
    Ok(())
}
fn ignored(name: &str, key: &str) -> bool {
    if [
        "session",
        "request",
        "args",
        "kwargs",
        "payload",
        "method",
        "method_name",
    ]
    .contains(&key)
    {
        return true;
    }
    match name {
        "Hello" => key == "realm",
        "Authenticate" => key == "signature",
        "Abort" | "Goodbye" => key == "reason",
        "Error" => ["request_type", "error"].contains(&key),
        "Publish" | "Subscribe" => key == "topic",
        "Event" => ["subscription", "publication"].contains(&key),
        "Published" => key == "publication",
        "Subscribed" | "Unsubscribe" => key == "subscription",
        "Registered" | "Unregister" => key == "registration",
        "Call" | "Register" => key == "procedure",
        "Invocation" => key == "registration",
        _ => false,
    }
}
fn get<'a>(map: &'a ValueMap, key: &str) -> Option<&'a Cbor> {
    // Common control dictionaries contain only a few keys. Borrow their keys
    // instead of allocating a temporary serde value for each schema field.
    if map.len() <= 8 {
        return map.iter().find_map(|(candidate, value)| match candidate {
            Cbor::String(candidate) if candidate == key => Some(value),
            _ => None,
        });
    }
    map.get(&Cbor::String(super::codec_copy_metrics::copy_codec_string(
        key,
    )))
}
fn unsigned(value: &Cbor) -> Option<u64> {
    match value {
        Cbor::U8(v) => Some(*v as u64),
        Cbor::U16(v) => Some(*v as u64),
        Cbor::U32(v) => Some(*v as u64),
        Cbor::U64(v) => Some(*v),
        Cbor::I8(v) => u64::try_from(*v).ok(),
        Cbor::I16(v) => u64::try_from(*v).ok(),
        Cbor::I32(v) => u64::try_from(*v).ok(),
        Cbor::I64(v) => u64::try_from(*v).ok(),
        _ => None,
    }
    .filter(|v| *v <= 9_007_199_254_740_992)
}
fn enumeration(key: &str) -> Option<&'static [(&'static str, u64)]> {
    Some(match key {
        "method" | "authmethod" | "authmethods" => &[
            ("anonymous", 0),
            ("ticket", 1),
            ("wampcra", 2),
            ("wamp-scram", 3),
            ("cryptosign", 4),
        ],
        "match" => &[("exact", 0), ("prefix", 1), ("wildcard", 2)],
        "invoke" => &[
            ("single", 0),
            ("first", 1),
            ("last", 2),
            ("roundrobin", 3),
            ("random", 4),
        ],
        "mode" => &[("skip", 0), ("kill", 1), ("killnowait", 2)],
        "ppt_scheme" => &[("cryptobox", 1), ("mqtt", 2), ("xbr", 3), ("opaque", 4)],
        "ppt_serializer" => &[
            ("transport", 0),
            ("json", 1),
            ("msgpack", 2),
            ("cbor", 3),
            ("ubjson", 4),
            ("opaque", 5),
            ("flatbuffers", 6),
            ("flexbuffers", 7),
        ],
        "ppt_cipher" => &[("xsalsa20poly1305", 1), ("aes256gcm", 2)],
        _ => return None,
    })
}
pub(super) fn project(name: &str, map: &ValueMap, reference: usize) -> Result<Fields, ParseError> {
    let mut result = Fields::with_capacity(schema::TABLES[reference].fields.len());
    for field in schema::TABLES[reference].fields {
        if ignored(name, field.name) {
            continue;
        }
        let extra = field.name == "extra" && ["Challenge", "Authenticate"].contains(&name);
        let value = if extra { None } else { get(map, field.name) };
        if !extra && (value.is_none() || value == Some(&Cbor::Unit)) {
            if field.required {
                result.insert(
                    field.name,
                    match field.kind {
                        Kind::String => Value::Text(super::codec_copy_metrics::copy_text_arc("")),
                        Kind::Table => Value::Table(Arc::new(Fields::new())),
                        _ => return Err(wire::invalid("required metadata")),
                    },
                );
            }
            continue;
        }
        let invalid = || wire::invalid("metadata field type");
        let projected = match field.kind {
            Kind::String => {
                if let Some(Cbor::String(value)) = value {
                    Some(Value::Text(super::codec_copy_metrics::copy_text_arc(
                        value.as_str(),
                    )))
                } else {
                    return Err(invalid());
                }
            }
            Kind::Scalar => {
                if let Some(enumeration) = enumeration(field.name) {
                    let Some(Cbor::String(value)) = value else {
                        return Err(invalid());
                    };
                    enumeration
                        .iter()
                        .find(|(name, _)| *name == value)
                        .map(|(_, v)| Value::Integer(*v))
                } else if field.width == 1 && field.values == [0, 1] {
                    let Some(Cbor::Bool(value)) = value else {
                        return Err(invalid());
                    };
                    Some(Value::Integer(u64::from(*value)))
                } else {
                    let integer = value.and_then(unsigned).ok_or_else(invalid)?;
                    let maximum = if field.width == 8 {
                        9_007_199_254_740_992
                    } else {
                        (1u64 << (field.width * 8)) - 1
                    };
                    (integer <= maximum).then_some(Value::Integer(integer))
                }
            }
            Kind::ScalarVector | Kind::StringVector => {
                let Some(Cbor::Seq(values)) = value else {
                    return Err(invalid());
                };
                let mut vector = Vec::new();
                for value in values {
                    if field.name == "authmethods" {
                        let Cbor::String(name) = value else {
                            return Err(invalid());
                        };
                        if name.is_empty() {
                            return Err(invalid());
                        }
                        if let Some((_, value)) = enumeration(field.name)
                            .unwrap()
                            .iter()
                            .find(|(key, _)| *key == name)
                        {
                            vector.push(Value::Integer(*value));
                        }
                    } else if field.kind == Kind::StringVector {
                        let Cbor::String(value) = value else {
                            return Err(invalid());
                        };
                        vector.push(Value::Text(super::codec_copy_metrics::copy_text_arc(
                            value.as_str(),
                        )));
                    } else {
                        vector.push(Value::Integer(unsigned(value).ok_or_else(invalid)?));
                    }
                }
                Some(Value::Vector(vector))
            }
            Kind::Table => {
                let source = if extra {
                    map
                } else {
                    let Some(Cbor::Map(map)) = value else {
                        return Err(invalid());
                    };
                    map
                };
                let table = &schema::TABLES[field.reference];
                if table.name == "Map" {
                    source.iter().find_map(|(key, value)| {
                        if let (Cbor::String(key), Cbor::String(value)) = (key, value) {
                            let mut chars = key.chars();
                            let first = chars.next()?;
                            if !(first.is_ascii_alphabetic() || first == '_')
                                || !chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
                            {
                                return None;
                            }
                            Some(Value::Table(Arc::new(Fields::from([
                                (
                                    "key",
                                    Value::Text(super::codec_copy_metrics::copy_text_arc(
                                        key.as_str(),
                                    )),
                                ),
                                (
                                    "value",
                                    Value::Text(super::codec_copy_metrics::copy_text_arc(
                                        value.as_str(),
                                    )),
                                ),
                            ]))))
                        } else {
                            None
                        }
                    })
                } else {
                    let mut roles = Fields::new();
                    for role in table.fields {
                        let Some(role_value) = get(source, role.name) else {
                            continue;
                        };
                        if *role_value == Cbor::Unit {
                            continue;
                        }
                        let Cbor::Map(role_value) = role_value else {
                            return Err(invalid());
                        };
                        let mut features = Fields::new();
                        if let Some(feature_value) = get(role_value, "features") {
                            if *feature_value != Cbor::Unit {
                                let Cbor::Map(feature_value) = feature_value else {
                                    return Err(invalid());
                                };
                                for feature in schema::TABLES[role.reference].fields {
                                    let key = if feature.name == "payload_transparency" {
                                        "payload_passthru_mode"
                                    } else {
                                        feature.name
                                    };
                                    if let Some(value) = get(feature_value, key) {
                                        if *value == Cbor::Unit {
                                            continue;
                                        }
                                        let Cbor::Bool(value) = value else {
                                            return Err(invalid());
                                        };
                                        features.insert(
                                            feature.name,
                                            Value::Integer(u64::from(*value)),
                                        );
                                    }
                                }
                            }
                        }
                        roles.insert(role.name, Value::Table(Arc::new(features)));
                    }
                    Some(Value::Table(Arc::new(roles)))
                }
            }
            Kind::TableVector => {
                let Some(Cbor::Seq(values)) = value else {
                    return Err(invalid());
                };
                let mut vector = Vec::new();
                for value in values {
                    let Cbor::Map(value) = value else {
                        return Err(invalid());
                    };
                    let mut principal = Fields::new();
                    if let Some(value) = get(value, "session") {
                        if *value != Cbor::Unit {
                            principal.insert(
                                "session",
                                Value::Integer(unsigned(value).ok_or_else(invalid)?),
                            );
                        }
                    }
                    for key in ["authid", "authrole"] {
                        if let Some(item) = get(value, key) {
                            if *item != Cbor::Unit {
                                let Cbor::String(item) = item else {
                                    return Err(invalid());
                                };
                                principal.insert(
                                    key,
                                    Value::Text(super::codec_copy_metrics::copy_text_arc(
                                        item.as_str(),
                                    )),
                                );
                            }
                        }
                    }
                    vector.push(Value::Table(Arc::new(principal)));
                }
                Some(Value::Vector(vector))
            }
            Kind::Union => return Err(invalid()),
        };
        if let Some(projected) = projected {
            result.insert(field.name, projected);
        }
    }
    Ok(result)
}
fn matches(field: &FieldSpec, actual: &Value, expected: &Value) -> Result<bool, ParseError> {
    if field.kind == Kind::Scalar {
        return Ok(if *expected == Value::Null {
            actual == &Value::Integer(field.default)
        } else {
            actual == expected
        });
    }
    match (actual, expected) {
        (Value::Table(actual), Value::Table(expected)) if field.kind == Kind::Table => {
            table_matches(field.reference, actual, expected)
        }
        (Value::Vector(actual), Value::Vector(expected))
            if field.kind == Kind::TableVector && actual.len() == expected.len() =>
        {
            for (actual, expected) in actual.iter().zip(expected) {
                let (Value::Table(actual), Value::Table(expected)) = (actual, expected) else {
                    return Ok(false);
                };
                if !table_matches(field.reference, actual, expected)? {
                    return Ok(false);
                }
            }
            Ok(true)
        }
        _ => Ok(actual == expected),
    }
}
fn table_matches(reference: usize, actual: &Fields, expected: &Fields) -> Result<bool, ParseError> {
    for field in schema::TABLES[reference].fields {
        if !matches(
            field,
            actual.get(field.name).unwrap_or(&Value::Null),
            expected.get(field.name).unwrap_or(&Value::Null),
        )? {
            return Ok(false);
        }
    }
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::super::codec_copy_metrics;
    use super::*;

    #[test]
    fn flatbuffers_metadata_lookup_preserves_exact_keys_and_borrowed_values() {
        let queries = [
            "",
            "a",
            "aa",
            "a\0",
            "é",
            "e\u{301}",
            "ppt_scheme",
            "vendor",
            "missing",
            "PPT_scheme",
        ];
        for length in 0..24 {
            for non_string_key in [false, true] {
                let mut map = ValueMap::new();
                for index in 0..length {
                    let key = queries
                        .get(index)
                        .map(|v| (*v).to_owned())
                        .unwrap_or_else(|| format!("vendor_{index}"));
                    let value = match index % 3 {
                        0 => Cbor::Unit,
                        1 => Cbor::Bytes(vec![0xff, 0, 0x80]),
                        _ => Cbor::Seq(vec![Cbor::Bool(false)]),
                    };
                    map.insert(Cbor::String(key), value);
                }
                if non_string_key {
                    map.insert(Cbor::U64(1), Cbor::Unit);
                }
                for key in queries {
                    let expected = map.get(&Cbor::String(key.to_owned()));
                    let actual = get(&map, key);
                    assert_eq!(actual, expected);
                    if let (Some(actual), Some(expected)) = (actual, expected) {
                        assert!(
                            std::ptr::eq(actual, expected),
                            "lookup must borrow the actual map entry"
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn flatbuffers_small_metadata_lookup_copies_no_key_strings() {
        for length in 0..10 {
            let map = (0..length)
                .map(|n| (Cbor::String(format!("key_{n}")), Cbor::U64(n)))
                .collect();
            let before = codec_copy_metrics::observed_on_current_thread();
            for key in ["key_0", "key_7", "absent"] {
                get(&map, key);
            }
            let after = codec_copy_metrics::observed_on_current_thread();
            assert_eq!(
                after.string_copy_bytes_total - before.string_copy_bytes_total,
                if length <= 8 { 0 } else { 16 },
                "bounded lookup should not allocate copied key strings"
            );
        }
    }

    #[test]
    fn flatbuffers_small_ppt_projection_needs_no_key_copies() {
        let map = ValueMap::from([
            (
                Cbor::String("ppt_scheme".into()),
                Cbor::String("opaque".into()),
            ),
            (
                Cbor::String("ppt_serializer".into()),
                Cbor::String("flatbuffers".into()),
            ),
        ]);
        let reference = schema::TABLES
            .iter()
            .position(|s| s.name == "Result")
            .unwrap();
        let before = codec_copy_metrics::observed_on_current_thread();
        let body = project("Result", &map, reference).unwrap();
        let after = codec_copy_metrics::observed_on_current_thread();
        assert_eq!(body.get("ppt_scheme"), Some(&Value::Integer(4)));
        assert_eq!(body.get("ppt_serializer"), Some(&Value::Integer(6)));
        assert_eq!(
            after.string_copy_bytes_total - before.string_copy_bytes_total,
            0
        );
    }
}
