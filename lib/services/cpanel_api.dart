// Historical compatibility code; excluded from the production app import graph.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/backend_config.dart';

class CpanelApiException implements Exception {
  CpanelApiException(this.status, this.message, {this.details = const {}});
  final int status;
  final String message;
  final Map<String, dynamic> details;
}

class CpanelApi {
  CpanelApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl = baseUrl ?? kApiBaseUrl;

  final http.Client _client;
  final String baseUrl;

  Uri _uri(String path) {
    if (baseUrl.isEmpty) {
      throw CpanelApiException(0, 'Server URL is not configured');
    }
    return Uri.parse(baseUrl.endsWith('/') ? '$baseUrl$path' : '$baseUrl$path');
  }

  Future<Map<String, dynamic>> send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
  }) async {
    final response = await _client
        .send(
          http.Request(method, _uri(path))
            ..headers.addAll({
              'Content-Type': 'application/json',
              if (accessToken != null) 'Authorization': 'Bearer $accessToken',
            })
            ..body = jsonEncode(body ?? <String, dynamic>{}),
        )
        .timeout(const Duration(seconds: 25));
    final decoded = jsonDecode(await response.stream.bytesToString());
    final map = decoded is Map
        ? decoded.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    if (response.statusCode >= 400) {
      throw CpanelApiException(
        response.statusCode,
        map['error']?.toString() ?? 'Request failed',
        details: map,
      );
    }
    return map;
  }

  Future<Map<String, dynamic>> uploadPhoto({
    required String accessToken,
    required String guestId,
    required String slot,
    required File file,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/v1/photos'));
    request.headers['Authorization'] = 'Bearer $accessToken';
    request.fields['guestId'] = guestId;
    request.fields['slot'] = slot;
    request.files.add(await http.MultipartFile.fromPath('photo', file.path));
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 40));
    final map = jsonDecode(await response.stream.bytesToString());
    if (response.statusCode >= 400 || map is! Map) {
      throw CpanelApiException(response.statusCode, 'Photo was not accepted');
    }
    return map.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<void> downloadPhoto({
    required String accessToken,
    required String photoId,
    required File destination,
  }) async {
    final response = await _client
        .send(
          http.Request('GET', _uri('/v1/photos/$photoId'))
            ..headers['Authorization'] = 'Bearer $accessToken',
        )
        .timeout(const Duration(seconds: 40));
    if (response.statusCode >= 400) {
      throw CpanelApiException(response.statusCode, 'Photo was not accepted');
    }
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(await response.stream.toBytes());
  }
}
