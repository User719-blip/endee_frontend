List<String> chunkText(String content, {int chunkSize = 100}) {
  final lines = content.split('\n');
  List<String> chunks = [];

  for (int i = 0; i < lines.length; i += chunkSize) {
    chunks.add(lines.skip(i).take(chunkSize).join('\n'));
  }
  return chunks;
}