import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import 'config.dart';
import 'session.dart';

/// A file to upload: its bytes, name and MIME type.
class UploadFile {
  final List<int> bytes;
  final String name;
  final String mimeType;
  const UploadFile(this.bytes, this.name, this.mimeType);
}

/// An error from the API, with a message that can be shown to the user.
class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  const ApiException(this.status, this.code, this.message);

  bool get isNetwork => status == 0;

  @override
  String toString() => 'ApiException($status $code: $message)';
}

/// JSON client for the MedPin API. Adds the sign-in token, refreshes it once
/// when it has expired, and turns failures into [ApiException]s.
class Api {
  Api._();
  static final Api I = Api._();

  http.Client client = http.Client();
  static const _timeout = Duration(seconds: 25);

  Future<dynamic> get(String path, {Map<String, Object?>? query}) => _send('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body);
  Future<dynamic> patch(String path, [Object? body]) => _send('PATCH', path, body: body);
  Future<dynamic> put(String path, [Object? body]) => _send('PUT', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// Multipart upload (photos, PDFs, voice notes). [files] maps the form field
  /// name to the files sent under it; [fields] are extra text fields.
  Future<dynamic> upload(
    String path, {
    required Map<String, List<UploadFile>> files,
    Map<String, String> fields = const {},
    String method = 'POST',
    bool retried = false,
  }) async {
    final session = Session.I;
    final request = http.MultipartRequest(method, _uri(path, null))..headers['accept'] = 'application/json';
    if (session.accessToken != null) request.headers['authorization'] = 'Bearer ${session.accessToken}';
    if (session.practiceId != null) request.headers['x-practice-id'] = session.practiceId!;
    request.fields.addAll(fields);
    for (final e in files.entries) {
      for (final f in e.value) {
        request.files.add(http.MultipartFile.fromBytes(e.key, f.bytes, filename: f.name, contentType: MediaType.parse(f.mimeType)));
      }
    }
    http.Response res;
    try {
      res = await http.Response.fromStream(await client.send(request).timeout(const Duration(seconds: 90)));
    } on TimeoutException {
      throw const ApiException(0, 'TIMEOUT', 'The upload is taking too long. Please try again.');
    } catch (_) {
      throw const ApiException(0, 'NETWORK', "Can't reach MedPin. Check your internet connection.");
    }
    if (res.statusCode == 401 && !retried && session.refreshToken != null) {
      if (await session.refresh()) return upload(path, files: files, fields: fields, method: method, retried: true);
      await session.expire();
    }
    dynamic json;
    try {
      json = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {}
    if (res.statusCode >= 400) {
      final err = json is Map ? json['error'] : null;
      throw ApiException(
        res.statusCode,
        err is Map ? '${err['code'] ?? 'ERROR'}' : 'ERROR',
        err is Map && err['message'] != null ? '${err['message']}' : 'The upload failed. Please try again.',
      );
    }
    return json;
  }

  Uri _uri(String path, Map<String, Object?>? query) {
    final q = <String, String>{
      for (final e in (query ?? const {}).entries)
        if (e.value != null) e.key: '${e.value}',
    };
    return Uri.parse('${AppConfig.apiBaseUrl}$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Future<dynamic> _send(String method, String path, {Object? body, Map<String, Object?>? query, bool retried = false}) async {
    final session = Session.I;
    final headers = <String, String>{'accept': 'application/json'};
    if (body != null) headers['content-type'] = 'application/json';
    if (session.accessToken != null) headers['authorization'] = 'Bearer ${session.accessToken}';
    if (session.practiceId != null) headers['x-practice-id'] = session.practiceId!;

    final request = http.Request(method, _uri(path, query))..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);

    http.Response res;
    try {
      res = await http.Response.fromStream(await client.send(request).timeout(_timeout));
    } on TimeoutException {
      throw const ApiException(0, 'TIMEOUT', 'MedPin is taking too long to respond. Please try again.');
    } catch (_) {
      throw const ApiException(0, 'NETWORK', "Can't reach MedPin. Check your internet connection.");
    }

    // Expired access token: refresh once and retry.
    if (res.statusCode == 401 && !retried && !path.startsWith('/api/auth/') && session.refreshToken != null) {
      if (await session.refresh()) return _send(method, path, body: body, query: query, retried: true);
      await session.expire();
    }

    if (res.statusCode < 300 && method == 'PATCH' && path == '/api/me' && body is Map) {
      await session.patchUser(body.cast<String, dynamic>());
    }
    final text = res.body;
    dynamic json;
    if (text.isNotEmpty) {
      try {
        json = jsonDecode(text);
      } catch (_) {
        json = null;
      }
    }
    if (res.statusCode >= 400) {
      final err = json is Map ? json['error'] : null;
      throw ApiException(
        res.statusCode,
        err is Map ? '${err['code'] ?? 'ERROR'}' : 'ERROR',
        err is Map && err['message'] != null ? '${err['message']}' : 'Something went wrong. Please try again.',
      );
    }
    return json;
  }
}
