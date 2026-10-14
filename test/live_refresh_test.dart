import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medpin_app/data/config.dart';
import 'package:medpin_app/data/live.dart';
import 'package:medpin_app/data/session.dart';

/// A live screen that counts how often it fetched.
class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

int fetches = 0;

class _CounterState extends State<_Counter> with LiveData {
  @override
  Future<Object?> fetch() async => {'n': ++fetches};

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Builder(builder: (c) => TextButton(onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('form')))), child: Text('n=${data?['n']}'))),
  );
}

void main() {
  setUp(() {
    AppMode.preview = false;
    Session.I.store = MemorySessionStore();
    Session.I
      ..accessToken = 'a'
      ..refreshToken = 'r'
      ..account = {'user': {'id': 'u1'}, 'landing': 'Doctor-Home'};
    fetches = 0;
  });

  testWidgets('a live screen refreshes after a change, when shown again and every 30 s', (t) async {
    await t.pumpWidget(MaterialApp(navigatorObservers: [LiveBus.routes], home: const _Counter()));
    await t.pump();
    await t.pump();
    expect(fetches, 1);

    // Something saved elsewhere (e.g. a patient added): refresh, even under another screen.
    await t.tap(find.textContaining('n='));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 4));
    LiveBus.changed();
    await t.pump(const Duration(milliseconds: 700));
    expect(fetches, 2);

    // Back to it: refresh again.
    await t.pump(const Duration(seconds: 4));
    Navigator.of(t.element(find.text('form'))).pop();
    await t.pumpAndSettle();
    expect(fetches, 3);

    // In front, every 30 s.
    await t.pump(const Duration(seconds: 31));
    expect(fetches, 4);
    await t.pumpWidget(const SizedBox());
  });
}
