import 'package:flutter_test/flutter_test.dart';

import 'package:wifi_device_finder/main.dart';

void main() {
  testWidgets('Home screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const WifiDeviceFinderApp());

    expect(find.text('Wi-Fi Device Finder'), findsWidgets);
  });
}
