import 'package:flutter_test/flutter_test.dart';
import 'package:medpin_app/screens/doctor/appointments_manage.dart';

void main() {
  // Thu 15 Oct 2026 and Fri 16 Oct 2026, slots at 10:00 and 17:30 (IST).
  Map<String, dynamic> slot(String day, String hhmm, String time) => {'available': true, 'startAt': '${day}T$hhmm:00+05:30', 'time': time};
  final days = [
    {'slots': [slot('2026-10-15', '10:00', '10:00 AM'), slot('2026-10-15', '17:30', '5:30 PM')]},
    {'slots': [slot('2026-10-16', '10:00', '10:00 AM'), slot('2026-10-16', '17:30', '5:30 PM')]},
  ];

  test('English, Bengali and Hindi wishes pick the same slot', () {
    expect(preferredSlotFor('Thu or Fri, after 5 PM', days), (0, '5:30 PM'));
    expect(preferredSlotFor('বৃহস্পতিবার বিকেল ৫টার পরে', days), (0, '5:30 PM'));
    expect(preferredSlotFor('गुरुवार शाम 5 बजे के बाद', days), (0, '5:30 PM'));
    expect(preferredSlotFor('শুক্রবার সকাল', days), (1, '10:00 AM'));
    expect(preferredSlotFor('शुक्रवार सुबह', days), (1, '10:00 AM'));
  });

  test('no usable wish → no preselection', () {
    expect(preferredSlotFor('Any time', days), isNull);
    expect(preferredSlotFor('যেকোনো সময়', days), isNull);
    expect(preferredSlotFor('', days), isNull);
  });
}
