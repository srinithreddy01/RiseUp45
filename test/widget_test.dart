import 'package:flutter_test/flutter_test.dart';
import 'package:riseup/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('schedules recurring tasks on the expected date', () {
    expect(nextOccurrence(DateTime(2026, 8, 14), TaskRecurrence.daily),
        DateTime(2026, 8, 15));
    expect(nextOccurrence(DateTime(2026, 8, 14), TaskRecurrence.weekdays),
        DateTime(2026, 8, 17));
    expect(nextOccurrence(DateTime(2026, 8, 14), TaskRecurrence.weekly),
        DateTime(2026, 8, 21));
  });

  testWidgets('shows the RiseUP home screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const RiseUpApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('Good morning, Friend'), findsOneWidget);
  });
}
