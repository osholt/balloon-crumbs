import 'package:balloon_crumbs/features/map/os_api_branding_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the official OS map logo at its fixed digital size', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: OsApiBrandingLogo())),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.width, 90);
    expect(image.height, 24);
    expect(find.bySemanticsLabel('Ordnance Survey map data'), findsOneWidget);
  });
}
