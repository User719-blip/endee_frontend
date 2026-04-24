import 'dart:convert';

import 'package:http/http.dart' as http;

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const pyBackendUrl = String.fromEnvironment(
  'PY_BACKEND_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

void ensureSupabaseConfigured() {
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    throw Exception(
      'Missing SUPABASE_URL or SUPABASE_ANON_KEY. Pass them with --dart-define.',
    );
  }

  final looksLikeJwt = supabaseAnonKey.split('.').length == 3;
  final looksLikePublishableKey = supabaseAnonKey.startsWith('sb_publishable_');
  if (!looksLikeJwt && !looksLikePublishableKey) {
    throw Exception(
      'SUPABASE_ANON_KEY does not look like a Supabase anon or publishable key.',
    );
  }
}

Map<String, String> _supabaseHeaders() {
  ensureSupabaseConfigured();
  final headers = <String, String>{
    'apikey': supabaseAnonKey,
    'Content-Type': 'application/json',
  };

  if (supabaseAnonKey.split('.').length == 3) {
    headers['Authorization'] = 'Bearer $supabaseAnonKey';
  }

  return headers;
}

Future<dynamic> invokeSupabaseFunction(
  String functionName,
  Map<String, dynamic> payload,
) async {
  ensureSupabaseConfigured();
  final res = await http.post(
    Uri.parse('$supabaseUrl/functions/v1/$functionName'),
    headers: _supabaseHeaders(),
    body: jsonEncode(payload),
  );

  final dynamic decoded = jsonDecode(res.body);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception(
      'Supabase function $functionName failed (${res.statusCode}): ${res.body}',
    );
  }

  return decoded;
}

Future<Map<String, dynamic>> ingestSourceFile({
  required List<int> bytes,
  required String filename,
  required String sessionId,
  String path = '',
}) async {
  final request = http.MultipartRequest(
    'POST',
    Uri.parse('$pyBackendUrl/ingest/file'),
  );
  request.files.add(
    http.MultipartFile.fromBytes('file', bytes, filename: filename),
  );
  if (path.isNotEmpty) {
    request.fields['path'] = path;
  }
  request.fields['session_id'] = sessionId;

  final response = await request.send();
  final body = await response.stream.bytesToString();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception(
      'Python backend ingest/file failed (${response.statusCode}): $body',
    );
  }

  final dynamic decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw Exception('Unexpected ingest/file response: $decoded');
  }
  return decoded;
}

Future<Map<String, dynamic>> ingestZipArchive({
  required List<int> bytes,
  required String filename,
  required String sessionId,
}) async {
  final request = http.MultipartRequest(
    'POST',
    Uri.parse('$pyBackendUrl/ingest/zip'),
  );
  request.files.add(
    http.MultipartFile.fromBytes('file', bytes, filename: filename),
  );
  request.fields['session_id'] = sessionId;

  final response = await request.send();
  final body = await response.stream.bytesToString();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception(
      'Python backend ingest/zip failed (${response.statusCode}): $body',
    );
  }

  final dynamic decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw Exception('Unexpected ingest/zip response: $decoded');
  }
  return decoded;
}

Future<Map<String, dynamic>> queryDocuments(
  String question, {
  required String sessionId,
}) async {
  final res = await http.post(
    Uri.parse('$pyBackendUrl/query'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'question': question,
      'top_k': 3,
      'session_id': sessionId,
    }),
  );

  final dynamic decoded = jsonDecode(res.body);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception(
      'Python backend query failed (${res.statusCode}): ${res.body}',
    );
  }

  if (decoded is! Map<String, dynamic> || decoded['result'] is! List<dynamic>) {
    throw Exception('Unexpected query response: $decoded');
  }

  return decoded;
}

Future<Map<String, dynamic>> resetSessionData({
  required String sessionId,
}) async {
  final res = await http.post(
    Uri.parse('$pyBackendUrl/session/reset'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'session_id': sessionId}),
  );

  final dynamic decoded = jsonDecode(res.body);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception(
      'Python backend session reset failed (${res.statusCode}): ${res.body}',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw Exception('Unexpected session reset response: $decoded');
  }
  return decoded;
}

String newSessionId() {
  final now = DateTime.now();
  return 'sess_${now.millisecondsSinceEpoch}_${now.microsecondsSinceEpoch % 1000000}';
}

Future<String> askLlm(String context, String question) async {
  final decoded = await invokeSupabaseFunction('answer', {
    'context': context,
    'question': question,
  });

  if (decoded is Map<String, dynamic> && decoded['generated_text'] is String) {
    return decoded['generated_text'] as String;
  }

  throw Exception('Unexpected answer response: $decoded');
}

Future<String> askLlmStream(
  String context,
  String question, {
  required void Function(String token) onToken,
}) async {
  final request = http.Request(
    'POST',
    Uri.parse('$supabaseUrl/functions/v1/answer'),
  );
  request.headers.addAll({
    ..._supabaseHeaders(),
    'Accept': 'text/event-stream',
  });
  request.body = jsonEncode({
    'context': context,
    'question': question,
    'stream': true,
  });

  final streamed = await request.send();
  final contentType = streamed.headers['content-type'] ?? '';
  if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
    final body = await streamed.stream.bytesToString();
    throw Exception(
      'Supabase streaming answer failed (${streamed.statusCode}): $body',
    );
  }

  if (!contentType.contains('text/event-stream')) {
    final body = await streamed.stream.bytesToString();
    final dynamic decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic> &&
        decoded['generated_text'] is String) {
      final answer = decoded['generated_text'] as String;
      onToken(answer);
      return answer;
    }
    throw Exception('Unexpected streaming response: $body');
  }

  final buffer = StringBuffer();
  var answer = '';
  await for (final line
      in streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    if (!line.startsWith('data:')) {
      continue;
    }

    final payloadText = line.substring(5).trim();
    if (payloadText.isEmpty) {
      continue;
    }

    final dynamic decoded = jsonDecode(payloadText);
    if (decoded is! Map<String, dynamic>) {
      continue;
    }

    final type = decoded['type']?.toString();
    if (type == 'token') {
      final token = decoded['token']?.toString() ?? '';
      if (token.isEmpty) {
        continue;
      }
      buffer.write(token);
      answer += token;
      onToken(answer);
    } else if (type == 'done') {
      final finalText = decoded['generated_text']?.toString();
      if (finalText != null && finalText.isNotEmpty) {
        answer = finalText;
        onToken(answer);
      }
    }
  }

  return answer.isEmpty ? buffer.toString() : answer;
}
