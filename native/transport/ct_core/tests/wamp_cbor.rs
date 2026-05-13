mod common;

use bytes::Bytes;
use ct_core::{parse_message, RawSocketSerializer};

#[test]
fn parse_all_messages_via_cbor() {
    for scenario in common::scenarios() {
        let bytes = Bytes::from(serde_cbor::to_vec(&scenario.json).unwrap());
        let parsed = parse_message(RawSocketSerializer::Cbor, bytes)
            .unwrap_or_else(|err| panic!("scenario '{}' failed: {err:?}", scenario.name));
        assert_eq!(parsed.serializer, RawSocketSerializer::Cbor);
        let actual_json = common::message_to_json(&parsed.message, RawSocketSerializer::Cbor);
        assert_eq!(actual_json, scenario.json, "scenario {}", scenario.name);
    }
}
