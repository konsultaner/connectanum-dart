// ignore_for_file: implementation_imports

// Building blocks for Connectanum router bindings and isolate orchestration.

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' show Random;
import 'dart:typed_data';
import 'dart:io'
    show
        ContentType,
        HttpHeaders,
        HttpRequest,
        HttpServer,
        HttpStatus,
        InternetAddress,
        Platform,
        ProcessInfo,
        pid;

import 'package:cbor/cbor.dart';
import 'package:collection/collection.dart';
import 'package:connectanum_core/connectanum_core.dart'
    show
        AbstractMessage,
        AbstractMessageWithPayload,
        Challenge,
        Details,
        decodeLazyPayloadView,
        Extra,
        Heartbeat,
        Hello,
        LazyMessagePayload,
        LazyPayloadEncoding,
        MessageTypes,
        PayloadListDecoder,
        PayloadMapDecoder,
        ResultPayload,
        UnknownMessage,
        containsMcpWhitespaceOrControl,
        Welcome;
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack_dart;
import 'package:connectanum_core/src/message/abort.dart' as abort_msg;
import 'package:connectanum_core/src/message/authenticate.dart'
    as authenticate_msg;
import 'package:connectanum_core/src/message/call.dart' as call_msg;
import 'package:connectanum_core/src/message/cancel.dart' as cancel_msg;
import 'package:connectanum_core/src/message/error.dart' as error_msg;
import 'package:connectanum_core/src/message/goodbye.dart' as goodbye_msg;
import 'package:connectanum_core/src/message/event.dart' as event_msg;
import 'package:connectanum_core/src/message/interrupt.dart' as interrupt_msg;
import 'package:connectanum_core/src/message/publish.dart' as publish_msg;
import 'package:connectanum_core/src/message/register.dart' as register_msg;
import 'package:connectanum_core/src/message/registered.dart' as registered_msg;
import 'package:connectanum_core/src/message/subscribe.dart' as subscribe_msg;
import 'package:connectanum_core/src/message/subscribed.dart' as subscribed_msg;
import 'package:connectanum_core/src/message/invocation.dart' as invocation_msg;
import 'package:connectanum_core/src/message/published.dart' as published_msg;
import 'package:connectanum_core/src/message/result.dart' as result_msg;
import 'package:connectanum_core/src/message/unregister.dart' as unregister_msg;
import 'package:connectanum_core/src/message/unregistered.dart'
    as unregistered_msg;
import 'package:connectanum_core/src/message/unsubscribe.dart'
    as unsubscribe_msg;

import 'http/http_context.dart';
import 'package:connectanum_core/src/message/unsubscribed.dart'
    as unsubscribed_msg;
import 'package:connectanum_core/src/message/yield.dart' as yield_msg;
import 'package:connectanum_core/src/message/uri_pattern.dart' as uri_pattern;
import 'package:connectanum_core/src/serializer/json/serializer.dart'
    as json_serializer;
import 'package:connectanum_core/src/serializer/cbor/serializer.dart'
    as cbor_serializer;
import 'package:connectanum_core/src/serializer/msgpack/serializer.dart'
    as msgpack_serializer;
import 'package:connectanum_core/connectanum_core.dart' as wamp_core show Error;
import 'package:connectanum_mcp/connectanum_mcp.dart' as mcp;
import 'package:meta/meta.dart';

import 'config/authenticator.dart';
import 'config/auth_registry.dart';
import 'config/http_route_transport_auth.dart';

import '../native/runtime.dart';
import 'isolate_support.dart';
import 'models/endpoint.dart';
import 'models/router_config.dart';
import 'models/router_listener.dart';
import 'models/router_message.dart';
import 'models/router_metrics.dart';
import 'models/sni_certificate.dart';
import 'models/tls_client_auth.dart';
import 'models/tls_mode.dart';
import 'state/commands.dart';
import 'state/procedure.dart';
import 'state/store.dart';
import 'state/subscription.dart';
import 'state/snapshot.dart';
import 'state/session.dart';
import 'config/router_settings.dart';
import 'config/router_settings_builder.dart';
import 'config/router_settings_codec.dart';
import 'auth/authorization.dart';
import 'auth/default_authenticators.dart';
import 'auth/http_auth_provider.dart';
import 'auth/remote_wamp_delegate.dart';
import 'auth/security.dart';

export 'models/router_listener.dart';
export 'models/router_message.dart';
export 'config/router_settings.dart';
export 'config/router_settings_builder.dart';
export 'config/router_config_loader.dart';
export 'http/http_context.dart';

part 'router_instance/router_binding.dart';
part 'router_instance/router_boss.dart';
part 'router_instance/realm_context.dart';
part 'state/worker_connection_state.dart';
part 'state/authenticator_selection.dart';
part 'router_instance/router_worker_handshake.dart';
part 'router_instance/router_worker_session.dart';
part 'router_instance/router_worker.dart';
part 'router_instance/router_controller.dart';
part 'router_instance/router_mcp.dart';
part 'router_instance/router_internal_session.dart';
