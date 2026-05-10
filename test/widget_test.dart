import 'package:flutter_test/flutter_test.dart';
import 'package:vll_sms/main.dart';

void main() {
  testWidgets('app boots', (tester) async {
    await tester.pumpWidget(const VllSmsApp());
    expect(find.byType(VllSmsApp), findsOneWidget);
  });
}
