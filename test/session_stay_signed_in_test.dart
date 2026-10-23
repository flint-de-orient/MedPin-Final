import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medpin_app/data/api.dart';
import 'package:medpin_app/data/session.dart';

/// Staying signed in: the app signs itself out only when the server ends the
/// sign-in — never because the 15-minute access token ran out, the server was
/// restarting, or another part of the app (a background push) rotated the token.
/// And a phone that is signed out drops its push token.

const _account = {
  'user': {'id': 'u1', 'name': 'Priya Sharma', 'phone': '9000000002'},
  'memberships': [],
  'patientId': 'pt1',
  'landing': 'Main',
};

http.Response _json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
http.Response _error(int status, String code) => _json({
      'error': {'code': code, 'message': code},
    }, status);

final _calls = <String>[];
var _signedOutHere = 0;

Future<void> _saved({String access = 'old-access', String refresh = 'r1'}) async {
  final store = MemorySessionStore();
  await store.write(jsonEncode({'accessToken': access, 'refreshToken': refresh, 'account': _account}));
  Session.I
    ..store = store
    ..accessToken = null
    ..refreshToken = null
    ..account = null
    ..onSignedOutHere = () async => _signedOutHere++;
}

void _serve(http.Response Function(http.Request req) answer) {
  _calls.clear();
  Api.I.client = MockClient((req) async {
    _calls.add('${req.method} ${req.url.path}');
    return answer(req);
  });
}

void main() {
  setUp(() => _signedOutHere = 0);

  test('Opening the app after the 15-minute access token ran out refreshes it and stays signed in', () async {
    await _saved();
    _serve((req) {
      if (req.url.path == '/api/auth/refresh') return _json({'accessToken': 'new-access', 'refreshToken': 'r2'});
      if (req.url.path == '/api/auth/session') {
        return req.headers['authorization'] == 'Bearer new-access' ? _json(_account) : _error(401, 'TOKEN_EXPIRED');
      }
      return _error(404, 'NOT_MOCKED');
    });
    expect(await Session.I.restore(), isTrue);
    expect(Session.I.signedIn, isTrue);
    expect(Session.I.refreshToken, 'r2');
    expect(_calls, ['GET /api/auth/session', 'POST /api/auth/refresh', 'GET /api/auth/session']);
    expect(jsonDecode((await Session.I.store.read())!)['refreshToken'], 'r2', reason: 'the new token is saved');
    expect(_signedOutHere, 0);
  });

  test('A server restart (502) while refreshing keeps the user signed in', () async {
    await _saved();
    _serve((req) {
      if (req.url.path == '/api/auth/refresh') return http.Response('<html>502 Bad Gateway</html>', 502);
      return _error(401, 'TOKEN_EXPIRED');
    });
    expect(await Session.I.restore(), isTrue);
    expect(Session.I.signedIn, isTrue);
    expect(Session.I.refreshToken, 'r1');
    expect(await Session.I.store.read(), isNotNull, reason: 'the saved sign-in is kept');
    expect(_signedOutHere, 0);
  });

  test('A busy server during a normal request: an error to retry, not a sign-out', () async {
    await _saved();
    await Session.I.restore().catchError((_) => false); // loads the saved tokens (session call fails below)
    Session.I
      ..accessToken = 'old-access'
      ..refreshToken = 'r1'
      ..account = _account;
    _serve((req) {
      if (req.url.path == '/api/auth/refresh') return _error(503, 'UNAVAILABLE');
      return _error(401, 'TOKEN_EXPIRED');
    });
    await expectLater(Api.I.get('/api/patient/home'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'UNAVAILABLE')));
    expect(Session.I.signedIn, isTrue);
    expect(_signedOutHere, 0);
  });

  test('When the server ended the sign-in, the app signs out and drops its push token', () async {
    await _saved();
    _serve((req) {
      if (req.url.path == '/api/auth/refresh') return _error(401, 'REFRESH_INVALID');
      return _error(401, 'SESSION_REVOKED');
    });
    expect(await Session.I.restore(), isFalse);
    expect(Session.I.signedIn, isFalse);
    expect(await Session.I.store.read(), isNull);
    expect(_signedOutHere, greaterThan(0), reason: 'push token and alarms are dropped');
  });

  test('A token another part of the app already rotated is used, not sent again', () async {
    await _saved(refresh: 'r1');
    Session.I
      ..accessToken = 'old-access'
      ..refreshToken = 'r1'
      ..account = _account;
    // A background push refreshed meanwhile and saved r2.
    await Session.I.store.write(jsonEncode({'accessToken': 'bg-access', 'refreshToken': 'r2', 'account': _account, 'savedAt': DateTime.now().millisecondsSinceEpoch + 1000}));
    _serve((req) {
      if (req.url.path == '/api/auth/refresh') return _error(401, 'REFRESH_INVALID'); // r1 is spent
      return req.headers['authorization'] == 'Bearer bg-access' ? _json({'ok': true}) : _error(401, 'TOKEN_EXPIRED');
    });
    expect(await Api.I.get('/api/patient/home'), {'ok': true});
    expect(_calls.where((c) => c.endsWith('/api/auth/refresh')), isEmpty, reason: 'the spent token is never sent');
    expect(Session.I.refreshToken, 'r2');
    expect(Session.I.signedIn, isTrue);
  });

  test('Opening the app while signed out drops any push token left behind', () async {
    Session.I
      ..store = MemorySessionStore()
      ..accessToken = null
      ..refreshToken = null
      ..account = null
      ..onSignedOutHere = () async => _signedOutHere++;
    expect(await Session.I.restore(), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(_signedOutHere, 1);
  });

  test('An older saved copy is never adopted (it would be a spent token)', () async {
    await _saved(refresh: 'r0');
    await Session.I.loadSaved();
    // The app refreshed (r1, saved), then the save of a later state failed: memory is ahead.
    Session.I.refreshToken = 'r1';
    _serve((req) {
      if (req.url.path == '/api/auth/refresh') return _json({'accessToken': 'new-access', 'refreshToken': 'r2'});
      return req.headers['authorization'] == 'Bearer new-access' ? _json({'ok': true}) : _error(401, 'TOKEN_EXPIRED');
    });
    // The saved r0 has savedAt 0 (older): it is ignored; r1 is refreshed normally.
    expect(await Api.I.get('/api/patient/home'), {'ok': true});
    expect(Session.I.refreshToken, 'r2');
  });
}
