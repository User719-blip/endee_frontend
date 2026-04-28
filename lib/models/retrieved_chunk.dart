class RetrievedChunk {
  const RetrievedChunk({
    required this.file,
    required this.symbol,
    required this.score,
    required this.confidence,
    required this.startLine,
    required this.endLine,
    required this.snippet,
  });

  final String file;
  final String symbol;
  final double score;
  final double confidence;
  final int? startLine;
  final int? endLine;
  final String snippet;

  factory RetrievedChunk.fromResult(dynamic resultItem) {
    if (resultItem is! Map) {
      return RetrievedChunk(
        file: 'unknown',
        symbol: '-',
        score: 0,
        confidence: 0,
        startLine: null,
        endLine: null,
        snippet: resultItem.toString(),
      );
    }

    final dynamic meta =
        resultItem['meta'] ?? resultItem['payload'] ?? <String, dynamic>{};
    final mappedMeta = meta is Map ? meta : <String, dynamic>{};
    final text = _textFromResult(resultItem);

    return RetrievedChunk(
      file: _stringOrDefault(mappedMeta['file'], 'unknown'),
      symbol: _stringOrDefault(mappedMeta['symbol'], '-'),
      score: _toScore(
        resultItem['similarity'] ??
            resultItem['score'] ??
            resultItem['distance'],
      ),
      confidence: _toConfidence(resultItem),
      startLine: _toInt(mappedMeta['start_line']),
      endLine: _toInt(mappedMeta['end_line']),
      snippet: text,
    );
  }

  String get locationLabel {
    if (startLine == null) {
      return file;
    }
    if (endLine != null && endLine != startLine) {
      return '$file:$startLine-$endLine';
    }
    return '$file:$startLine';
  }

  String preview({int maxLength = 500, bool full = false}) {
    if (full || snippet.length <= maxLength) {
      return snippet;
    }
    return '${snippet.substring(0, maxLength)}...';
  }

  static String _textFromResult(dynamic resultItem) {
    if (resultItem is! Map) {
      return resultItem.toString();
    }

    final dynamic meta = resultItem['meta'] ?? resultItem['payload'];
    if (meta is Map) {
      final text = meta['text'] ?? meta['content'] ?? meta['snippet'];
      if (text != null && text.toString().trim().isNotEmpty) {
        return text.toString();
      }
    }

    final nestedContainers = [
      resultItem['document'],
      resultItem['source'],
      resultItem['_source'],
    ];
    for (final container in nestedContainers) {
      if (container is! Map) {
        continue;
      }
      final nestedMeta = container['meta'] ?? container['payload'] ?? container;
      if (nestedMeta is Map) {
        final text =
            nestedMeta['text'] ??
            nestedMeta['content'] ??
            nestedMeta['snippet'];
        if (text != null && text.toString().trim().isNotEmpty) {
          return text.toString();
        }
      }
    }

    final text =
        resultItem['text'] ?? resultItem['content'] ?? resultItem['snippet'];
    if (text != null) {
      return text.toString();
    }
    return '';
  }

  static double _toScore(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return 0;
  }

  static int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static double _toConfidence(dynamic resultItem) {
    if (resultItem is! Map) {
      return 0;
    }

    final similarity = resultItem['similarity'] ?? resultItem['score'];
    if (similarity is num) {
      return similarity.toDouble().clamp(0, 1);
    }

    final distance = resultItem['distance'];
    if (distance is num) {
      return (1 - distance.toDouble()).clamp(0, 1);
    }

    return 0;
  }

  static String _stringOrDefault(dynamic value, String fallback) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return fallback;
    }
    return text;
  }
}
