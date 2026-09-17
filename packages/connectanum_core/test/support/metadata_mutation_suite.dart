import '../custom_fields_regression_test.dart' as custom_regressions;
import '../custom_fields_test.dart' as custom;
import '../details_feature_announcement_test.dart' as features;
import '../message_details_regression_test.dart' as details;
import '../serializer_challenge_welcome_test.dart' as handshake;

void main() {
  custom.main();
  custom_regressions.main();
  details.main();
  features.main();
  handshake.main();
}
