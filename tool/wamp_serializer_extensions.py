"""Declared supplemental WAMP diagnostics; never primary parity acceptance."""
from __future__ import annotations
from typing import Any

INVENTORY = 'flatbuffers_extensions_v1'
CODECS = ('cbor', 'msgpack', 'flatbuffers')


def extension_cases() -> list[dict[str, Any]]:
    cases = []

    def add(group, mode, transport, secure, client='native', size=65536, typed=True, **extra):
        construction = 'native_buffer' if typed and client == 'native' else 'values'
        fields = {'peer_count': 1, 'request_bytes': size, 'response_bytes': size,
                  'path': 'bench.wamp.topic' if mode in ('pubsub', 'publish_ack', 'subscribe_cycle') else 'bench.rpc.echo'}
        if typed:
            fields.update(ppt_scheme='x_connectanum_bench_typed', payload_construction=construction)
        fields.update(extra)
        case_id = f'ext_{len(cases):02d}_{group}'
        case = {'id': case_id, 'group': group, 'mode': mode, 'transport': transport,
                'secure_transport': secure, 'client_impl': client, 'construction': construction,
                'payload_profile': 'typed' if typed else f'encrypted_ppt_{fields["ppt_serializer"]}' if fields.get('ppt_cipher') else 'wamp_envelope_cbor_args', 'fields': fields,
                'workloads': {codec: f'{case_id}_{codec}' for codec in CODECS}}
        if group == 'encrypted_ppt':
            case['peer_serializer_mode'] = 'match_envelope'
        if typed and client == 'native':
            case['zero_copy_codecs'] = ['flatbuffers']
        cases.append(case)

    transports = [('rawsocket', False), ('websocket', True)]
    for mode in ('publish_ack', 'subscribe_cycle', 'register_cycle', 'cancel_cycle'):
        for transport, secure in transports:
            add('small_control', mode, transport, secure, size=128 if mode == 'publish_ack' else 0, typed=False)
    for size in (10240, 102400, 1048576):
        for transport, secure in transports:
            for client in ('dart', 'native'):
                add('payload_sizes', 'rpc', transport, secure, client, size)
    for transport, secure in transports:
        add('fanout8', 'pubsub', transport, secure, peer_count=8)
        for client in ('dart', 'native'):
            add('progressive', 'progressive_rpc', transport, secure, client, 10240, typed=False)
        for peer in ('json', 'msgpack', 'cbor'):
            add('mixed_serializers', 'rpc', transport, secure, peer_serializer=peer)
        for cipher in ('xsalsa20poly1305', 'aes256gcm'):
            for serializer in ('cbor', 'flatbuffers'):
                add('encrypted_ppt', 'rpc', transport, secure, typed=False,
                    ppt_scheme='wamp', ppt_serializer=serializer, ppt_cipher=cipher, ppt_keyid='bench-key')
    for secure in (False, True):
        add('fragmented_masked_websocket', 'rpc', 'websocket', secure, websocket_fragment_size=1024)
    assert len(cases) == 42
    return cases


def workload_fields(case: dict[str, Any], codec: str) -> dict[str, Any]:
    fields = dict(case['fields'])
    if case['payload_profile'] == 'typed':
        fields['ppt_serializer'] = codec
    if case.get('peer_serializer_mode') == 'match_envelope':
        fields['peer_serializer'] = codec
    return fields


def configuration_findings(report, case, codec, *, label):
    fields = workload_fields(case, codec)
    expected = {
        'serializer': codec, 'secure_transport': case['secure_transport'], 'payload_bytes': fields['request_bytes'],
        **{key: fields.get(key) for key in ('peer_serializer', 'ppt_scheme', 'ppt_serializer',
                                          'ppt_cipher', 'ppt_keyid', 'payload_construction',
                                          'websocket_fragment_size')},
        'peer_count': fields['peer_count'], 'in_flight_per_session': 1,
    }
    configuration = report.get('wamp_configuration')
    if not isinstance(configuration, dict):
        return [f'{label}: missing actual WAMP configuration']
    findings = []
    for key, value in expected.items():
        if key not in configuration or type(configuration[key]) is not type(value) or configuration[key] != value:
            findings.append(f'{label}: actual WAMP {key} does not match the declared extension')
    for key, value in {'protocol': f'wamp_{case["transport"]}_{case["mode"]}',
                       'client_impl': case['client_impl'], 'concurrency': 1}.items():
        if type(report.get(key)) is not type(value) or report.get(key) != value:
            findings.append(f'{label}: reported {key} does not match the declared extension')
    if fields.get('websocket_fragment_size'):
        mask = report.get('copy_metrics', {}).get('websocket_mask_copy_bytes')
        if type(mask) is not int or mask <= 0:
            findings.append(f'{label}: fragmented native WebSocket masking must be observed')
    return findings
