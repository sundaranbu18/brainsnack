import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Where the API lives. Override at build time with
/// `--dart-define=API_BASE=https://your-service.onrender.com`.
/// Debug builds default to the API running on your computer (Android emulator address).
const String apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: kReleaseMode ? 'https://brainsnack-api.onrender.com' : 'http://10.0.2.2:5050',
);

class ApiError implements Exception {
  ApiError(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

typedef Json = Map<String, dynamic>;

class Api {
  static String? token;

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  static Future<Json> get(String path) => _send(() => http.get(Uri.parse('$apiBase/api$path'), headers: _headers));

  static Future<Json> post(String path, [Json body = const {}]) =>
      _send(() => http.post(Uri.parse('$apiBase/api$path'), headers: _headers, body: jsonEncode(body)));

  static Future<Json> delete(String path, [Json body = const {}]) =>
      _send(() => http.delete(Uri.parse('$apiBase/api$path'), headers: _headers, body: jsonEncode(body)));

  static Future<Json> _send(Future<http.Response> Function() call) async {
    http.Response res;
    try {
      // Generous timeout: a free Render server sleeps when idle and takes a while to wake.
      res = await call().timeout(const Duration(seconds: 75));
    } on TimeoutException {
      throw ApiError('The server took too long to respond. Please try again.');
    } on SocketException {
      throw ApiError('No connection. Check your internet and try again.');
    } on http.ClientException {
      throw ApiError('No connection. Check your internet and try again.');
    }
    Json data;
    try {
      data = jsonDecode(res.body) as Json;
    } catch (_) {
      throw ApiError('Unexpected response from the server.', res.statusCode);
    }
    if (res.statusCode >= 400) {
      throw ApiError((data['error'] as String?) ?? 'Something went wrong.', res.statusCode);
    }
    return data;
  }
}

/// Signed-in user and guest nickname. A single shared instance: [session].
class Session extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'token';

  Json? user;
  String guestName = '';
  List<dynamic> categories = const [];

  bool get signedIn => user != null;
  String get displayName => signedIn ? user!['username'] as String : (guestName.isEmpty ? 'Guest' : guestName);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    guestName = prefs.getString('guestName') ?? '';
    try {
      Api.token = await _storage.read(key: _tokenKey);
    } catch (_) {
      Api.token = null;
    }
    if (Api.token != null) {
      try {
        user = (await Api.get('/auth/me'))['user'] as Json;
      } on ApiError catch (e) {
        if (e.status == 401) await logout();
      }
    }
    notifyListeners();
  }

  Future<void> authenticate({required bool register, required String email, required String password, String username = ''}) async {
    final res = await Api.post(register ? '/auth/register' : '/auth/login', {
      'email': email,
      'password': password,
      if (register) 'username': username,
    });
    Api.token = res['token'] as String;
    user = res['user'] as Json;
    await _storage.write(key: _tokenKey, value: Api.token);
    notifyListeners();
  }

  void updateUser(Json? u) {
    if (u == null) return;
    user = u;
    notifyListeners();
  }

  Future<void> setGuestName(String name) async {
    guestName = name.trim();
    (await SharedPreferences.getInstance()).setString('guestName', guestName);
    notifyListeners();
  }

  Future<void> logout() async {
    Api.token = null;
    user = null;
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {}
    notifyListeners();
  }
}

final session = Session();
