import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/infrastructure/fcm_platform_push_token_source.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final platformPushTokenSource = createConfiguredPlatformPushTokenSource();
  runApp(WampApp(platformPushTokenSource: platformPushTokenSource));
}
