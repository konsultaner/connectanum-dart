mod common;

use bytes::Bytes;
use ct_core::{parse_message, RawSocketSerializer};

#[test]
fn parse_all_messages_via_cbor() {
    for scenario in common::scenarios() {
        let bytes = Bytes::from(serde_cbor::to_vec(&scenario.json).unwrap());
        let parsed = parse_message(RawSocketSerializer::Cbor, bytes.clone());
        assert_eq!(
            parsed
                .as_ref()
                .map(|message| (message.message.code(), message.serializer))
                .map_err(|error| format!("{error:?}")),
            Ok((
                scenario.json[0].as_u64().unwrap(),
                RawSocketSerializer::Cbor
            )),
            "scenario {} must retain its independently encoded identity",
            scenario.name
        );
        let parsed =
            parsed.unwrap_or_else(|err| panic!("scenario '{}' failed: {err:?}", scenario.name));
        assert_eq!(parsed.raw.as_contiguous(), Some(&bytes));
        assert_eq!(parsed.serializer, RawSocketSerializer::Cbor);
        let actual_json = common::message_to_json(&parsed.message, RawSocketSerializer::Cbor);
        assert_eq!(actual_json, scenario.json, "scenario {}", scenario.name);
    }
}
