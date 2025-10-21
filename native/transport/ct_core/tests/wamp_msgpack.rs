mod common;

use bytes::Bytes;
use ct_core::{parse_message, RawSocketSerializer};

#[test]
fn parse_all_messages_via_msgpack() {
    for scenario in common::scenarios() {
        let bytes = Bytes::from(rmp_serde::to_vec(&scenario.json).unwrap());
        let parsed = parse_message(RawSocketSerializer::MessagePack, bytes)
            .unwrap_or_else(|err| panic!("scenario '{}' failed: {err:?}", scenario.name));
        assert_eq!(parsed.serializer, RawSocketSerializer::MessagePack);
        let actual_json =
            common::message_to_json(&parsed.message, RawSocketSerializer::MessagePack);
        assert_eq!(actual_json, scenario.json, "scenario {}", scenario.name);
    }
}
