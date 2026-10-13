import 'package:flutter_test/flutter_test.dart';
import 'package:medpin_app/data/voice.dart';

void main() {
  test('read aloud: medical shorthand is spoken in words', () {
    expect(Voice.spoken('Metformin 500 mg 1-0-1 after food'), 'Metformin 500 milligram 1 in the morning and 1 at night after food');
    expect(Voice.spoken('**HbA1c** is 7.2. Check BP SOS'), 'H B A 1 C is 7.2. Check blood pressure when needed');
    expect(Voice.spoken('Fee ₹600, see https://medpin.in/x'), 'Fee rupees 600, see');
    expect(Voice.spoken('- Levothyroxine 50 mcg 1-0-0'), 'Levothyroxine 50 microgram 1 in the morning');
  });

  test('read aloud: the voice follows the text\'s language', () {
    expect(Voice.languageOf('Take it after food'), 'en-IN');
    expect(Voice.languageOf('খাবারের পরে খান'), 'bn-IN');
    expect(Voice.languageOf('खाने के बाद लें'), 'hi-IN');
    expect(Voice.languageOf('Metformin 500 mg — খাবারের পরে খান'), 'bn-IN');
  });
}
