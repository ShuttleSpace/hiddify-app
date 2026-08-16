import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hiddify/features/backup/data/secure_storage_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:xml/xml.dart';

class WebdavCredentials {
  const WebdavCredentials({required this.url, required this.username, required this.password});

  final String url;
  final String username;
  final String password;

  bool get isConfigured => url.trim().isNotEmpty;
}

class RemoteBackupFile {
  const RemoteBackupFile({required this.name, required this.url});

  final String name;
  final String url;
}

class WebdavBackupRepository {
  WebdavBackupRepository(this._storage);

  final FlutterSecureStorage _storage;

  static const _urlKey = 'backup_webdav_url';
  static const _usernameKey = 'backup_webdav_username';
  static const _passwordKey = 'backup_webdav_password';

  Future<WebdavCredentials?> load() async {
    final url = await _storage.read(key: _urlKey);
    if (url == null || url.trim().isEmpty) return null;
    return WebdavCredentials(
      url: url,
      username: await _storage.read(key: _usernameKey) ?? '',
      password: await _storage.read(key: _passwordKey) ?? '',
    );
  }

  Future<void> save(WebdavCredentials credentials) async {
    await _storage.write(key: _urlKey, value: credentials.url.trim());
    await _storage.write(key: _usernameKey, value: credentials.username);
    await _storage.write(key: _passwordKey, value: credentials.password);
  }

  Future<void> clear() async {
    await _storage.delete(key: _urlKey);
    await _storage.delete(key: _usernameKey);
    await _storage.delete(key: _passwordKey);
  }

  Future<void> testConnection(WebdavCredentials credentials) async {
    final response = await _request(
      credentials,
      'PROPFIND',
      credentials.url,
      data: _propfindXml,
      headers: const {'Depth': '0'},
    );
    if (response.statusCode != 207 && response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    }
  }

  Future<void> upload(WebdavCredentials credentials, String fileName, List<int> bytes) async {
    final path = _join(credentials.url, fileName);
    await _request(credentials, 'PUT', path, data: bytes, headers: const {'Content-Type': 'application/octet-stream'});
  }

  Future<List<RemoteBackupFile>> list(WebdavCredentials credentials) async {
    final response = await _request(
      credentials,
      'PROPFIND',
      credentials.url,
      data: _propfindXml,
      headers: const {'Depth': '1'},
    );
    if (response.data is! String) return const [];

    final document = XmlDocument.parse(response.data as String);
    final baseUri = Uri.parse(_ensureTrailingSlash(credentials.url));
    return document.descendantElements
        .where((element) => element.name.local == 'href')
        .map((element) => element.innerText.trim())
        .where((value) => value.endsWith('.json') || value.endsWith('.hiddifybackup'))
        .map((value) {
          final uri = baseUri.resolve(value);
          final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
          return RemoteBackupFile(name: segments.isEmpty ? uri.toString() : segments.last, url: uri.toString());
        })
        .toSet()
        .toList();
  }

  Future<List<int>> download(WebdavCredentials credentials, String url) async {
    final response = await _request(credentials, 'GET', url, options: Options(responseType: ResponseType.bytes));
    if (response.data is List<int>) return response.data as List<int>;
    return utf8.encode(response.data.toString());
  }

  Dio _dio(WebdavCredentials credentials) {
    final basic = base64Encode(utf8.encode('${credentials.username}:${credentials.password}'));
    return Dio(
      BaseOptions(
        headers: {'Authorization': 'Basic $basic'},
        validateStatus: (status) => status != null && status >= 200 && status < 300,
        followRedirects: true,
      ),
    );
  }

  Future<Response<dynamic>> _request(
    WebdavCredentials credentials,
    String method,
    String url, {
    Object? data,
    Map<String, String>? headers,
    Options? options,
  }) {
    return _dio(credentials).request(
      url,
      data: data,
      options: (options ?? Options()).copyWith(method: method, headers: {...?options?.headers, ...?headers}),
    );
  }

  String _join(String baseUrl, String fileName) {
    final base = _ensureTrailingSlash(baseUrl);
    return '$base${Uri.encodeComponent(fileName)}';
  }

  String _ensureTrailingSlash(String value) => value.endsWith('/') ? value : '$value/';

  static const _propfindXml =
      '<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/></d:prop></d:propfind>';
}

final webdavBackupRepositoryProvider = Provider<WebdavBackupRepository>(
  (ref) => WebdavBackupRepository(ref.watch(secureStorageProvider)),
);

final webdavCredentialsProvider = FutureProvider<WebdavCredentials?>(
  (ref) => ref.watch(webdavBackupRepositoryProvider).load(),
);
