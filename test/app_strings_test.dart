import 'package:flutter_test/flutter_test.dart';
import 'package:nus_presentation_capture/l10n/app_strings.dart';

void main() {
  test('English and Chinese strings are available', () {
    expect(AppStrings('en').get('record'), 'Record presentation');
    expect(AppStrings('zh').get('record'), '录制演示视频');
  });

  test('Unknown language falls back to English', () {
    expect(AppStrings('fr').get('uploaded'), 'Uploaded');
  });
}
