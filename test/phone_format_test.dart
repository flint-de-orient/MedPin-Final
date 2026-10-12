import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medpin_app/widgets/mp.dart';

/// Mobile number boxes: digits only, at most 10, shown as "98765 43210".
void main() {
  const f = MpPhoneFormatter();
  String type(String before, String after) =>
      f.formatEditUpdate(TextEditingValue(text: before), TextEditingValue(text: after)).text;

  test('formats as it is typed', () {
    expect(type('', '9'), '9');
    expect(type('9876', '98765'), '98765');
    expect(type('98765', '987654'), '98765 4');
    expect(type('98765 4321', '98765 43210'), '98765 43210');
  });

  test('never more than 10 digits', () {
    expect(type('98765 43210', '98765 432109'), '98765 43210', reason: 'an 11th digit is ignored');
    expect(type('12345 67890', '12345 678902'), '12345 67890');
  });

  test('letters and symbols are dropped', () {
    expect(type('', '98a7-6'), '9876');
  });

  test('a pasted +91 or 0 in front keeps the 10-digit number', () {
    expect(type('', '+91 98765 43210'), '98765 43210');
    expect(type('', '+919876543210'), '98765 43210');
    expect(type('', '09876543210'), '98765 43210');
  });
}
