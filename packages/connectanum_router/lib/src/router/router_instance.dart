/// Building blocks for Connectanum router bindings and isolate orchestration.
library connectanum_router_instance;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart'
    show AbstractMessage, Details, Hello, Welcome;
import 'package:connectanum_core/src/message/abort.dart' as abort_msg;
import 'package:connectanum_core/src/message/authenticate.dart'
    as authenticate_msg;
import 'package:connectanum_core/src/serializer/json/serializer.dart'
    as json_serializer;
import 'package:connectanum_core/src/serializer/msgpack/serializer.dart'
    as msgpack_serializer;

import '../native/runtime.dart';
import 'isolate_support.dart';
import 'models/endpoint.dart';
import 'models/router_config.dart';
import 'models/router_listener.dart';
import 'models/router_message.dart';
import 'models/sni_certificate.dart';
import 'models/tls_mode.dart';
import 'state/commands.dart';
import 'state/store.dart';
import 'state/subscription.dart';
import 'state/snapshot.dart';
import 'state/session.dart';
import 'config/router_settings.dart';
import 'config/router_settings_builder.dart';
import 'config/router_settings_codec.dart';
import 'auth/default_authenticators.dart';

export 'models/router_listener.dart';
export 'models/router_message.dart';
export 'config/router_settings.dart';
export 'config/router_settings_builder.dart';
export 'config/router_config_loader.dart';

part 'router_instance/router_binding.dart';
part 'router_instance/router_boss.dart';
part 'router_instance/realm_context.dart';
part 'router_instance/router_worker.dart';
part 'router_instance/router_controller.dart';
