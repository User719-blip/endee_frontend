import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_turn.dart';
import '../models/retrieved_chunk.dart';
import '../services/codebase_api_client.dart';

class CodebaseHomePage extends StatefulWidget {
  const CodebaseHomePage({super.key});

  @override
  State<CodebaseHomePage> createState() => _CodebaseHomePageState();
}

class _CodebaseHomePageState extends State<CodebaseHomePage> {
  final TextEditingController _questionController = TextEditingController();

  bool _busy = false;
  String _sessionId = newSessionId();
  String _status = 'Ready';
  String _answer = '';
  String _streamingQuestion = '';
  String _streamingAnswer = '';
  String _contextPreview = '';
  List<RetrievedChunk> _retrievedChunks = const [];
  List<ChatTurn> _conversationTurns = const [];
  bool _showFullSnippets = false;

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _uploadSingleFile() async {
    final selection = await FilePicker.platform.pickFiles(withData: true);
    if (selection == null || selection.files.isEmpty) {
      return;
    }

    final file = selection.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _setStatus('Selected file has no bytes in memory.');
      return;
    }

    await _runBusy(() async {
      _setStatus('Ingesting ${file.name}...');
      final res = await ingestSourceFile(
        bytes: bytes,
        filename: file.name,
        sessionId: _sessionId,
      );
      final count = res['chunk_count'] ?? 0;
      _setStatus(
        'Ingested ${file.name}. Chunks stored: $count (session: $_sessionId)',
      );
    });
  }

  Future<void> _uploadZipFile() async {
    final selection = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (selection == null || selection.files.isEmpty) {
      return;
    }

    final file = selection.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _setStatus('Selected zip has no bytes in memory.');
      return;
    }

    await _runBusy(() async {
      _setStatus('Ingesting zip ${file.name}...');
      final res = await ingestZipArchive(
        bytes: bytes,
        filename: file.name,
        sessionId: _sessionId,
      );
      final count = res['chunk_count'] ?? 0;
      _setStatus(
        'Ingested ${file.name}. Chunks stored: $count (session: $_sessionId)',
      );
    });
  }

  Future<void> _startNewSession() async {
    final previousSession = _sessionId;
    await _runBusy(() async {
      _setStatus('Deleting vectors for session $previousSession...');
      await resetSessionData(sessionId: previousSession);
      setState(() {
        _sessionId = newSessionId();
        _answer = '';
        _streamingQuestion = '';
        _streamingAnswer = '';
        _contextPreview = '';
        _retrievedChunks = const [];
        _conversationTurns = const [];
      });
      _setStatus(
        'Deleted session data for $previousSession. Started new session: $_sessionId',
      );
    });
  }

  Future<void> _endSessionAndDeleteData() async {
    await _startNewSession();
  }

  Future<void> _askQuestion() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) {
      _setStatus('Type a question first.');
      return;
    }

    final wordCount = _wordCount(question);
    if (wordCount >= 100) {
      _setStatus('Question must be less than 100 words. Current: $wordCount');
      return;
    }

    await _runBusy(() async {
      _setStatus('Searching top 3 chunks...');
      final queryRes = await queryDocuments(question, sessionId: _sessionId);
      final results = (queryRes['result'] as List<dynamic>?) ?? <dynamic>[];
      _retrievedChunks = results
          .map(RetrievedChunk.fromResult)
          .toList(growable: false);

      final context = _retrievedChunks
          .map((chunk) => chunk.snippet)
          .where((text) => text.trim().isNotEmpty)
          .join('\n\n');

      final memoryContext = _conversationTurns.isEmpty
          ? ''
          : _conversationTurns
                .map(
                  (turn) => 'User: ${turn.question}\nAssistant: ${turn.answer}',
                )
                .join('\n\n');

      if (context.trim().isEmpty) {
        _answer = '';
        _streamingQuestion = '';
        _streamingAnswer = '';
        _contextPreview = '';
        _retrievedChunks = const [];
        _setStatus('No chunks found. Upload files first, then try again.');
        return;
      }

      final combinedContext = [
        if (memoryContext.trim().isNotEmpty) 'Session memory:\n$memoryContext',
        if (context.trim().isNotEmpty) 'Retrieved code context:\n$context',
      ].join('\n\n');

      _contextPreview = combinedContext.length > 1800
          ? '${combinedContext.substring(0, 1800)}\n\n...[truncated]'
          : combinedContext;

      _setStatus('Generating answer from Supabase/Mistral...');
      try {
        setState(() {
          _streamingQuestion = question;
          _streamingAnswer = '';
        });

        final finalAnswer = await askLlmStream(
          combinedContext,
          question,
          onToken: (partialAnswer) {
            if (!mounted) {
              return;
            }
            setState(() {
              _streamingAnswer = partialAnswer;
              _answer = partialAnswer;
            });
          },
        );

        _answer = finalAnswer;
        _conversationTurns = [
          ..._conversationTurns,
          ChatTurn(
            question: question,
            answer: finalAnswer,
            timestamp: DateTime.now(),
            contextPreview: _contextPreview,
            retrievedCount: results.length,
          ),
        ];
        _streamingQuestion = '';
        _streamingAnswer = '';
        _setStatus(
          'Answer ready. Retrieved ${results.length} chunk(s) from session $_sessionId.',
        );
      } catch (err) {
        _streamingQuestion = '';
        _streamingAnswer = '';
        _answer =
            'AI answer is temporarily unavailable. Retrieved chunks are shown below so you can still inspect relevant code.\n\nError: $err';
        _setStatus(
          'Retrieved ${results.length} chunk(s) from session $_sessionId, but answer generation failed.',
        );
      }
    });
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } catch (err) {
      _setStatus('Error: $err');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _setStatus(String status) {
    if (!mounted) {
      return;
    }
    setState(() {
      _status = status;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Codebase Upload + RAG Query')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1120;

            final sessionPanel = _buildSessionPanel(context);
            final chatPanel = _buildChatPanel(context);

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 380,
                    child: SingleChildScrollView(child: sessionPanel),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: SingleChildScrollView(child: chatPanel)),
                ],
              );
            }

            return ListView(
              children: [sessionPanel, const SizedBox(height: 16), chatPanel],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSessionPanel(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0E1A29), Color(0xFF102638)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white12),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0x1A22C55E),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Session Workspace',
                  style: TextStyle(
                    color: Color(0xFF86EFAC),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Upload code, ask follow-up questions, and keep the session memory active while you work.',
                style: TextStyle(fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _uploadSingleFile,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Source'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _uploadZipFile,
                    icon: const Icon(Icons.folder_zip),
                    label: const Text('ZIP'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _startNewSession,
                    icon: const Icon(Icons.refresh),
                    label: const Text('New session'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _endSessionAndDeleteData,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Reset data'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _infoChip('Session', _sessionId),
              const SizedBox(height: 8),
              _infoChip('Status', _status),
              const SizedBox(height: 8),
              _infoChip('Chunk retrieval', 'Fixed at top 3 chunks'),
              const SizedBox(height: 8),
              _infoChip(
                'Scope',
                'This session stays local to this browser tab until you reset it.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _questionController,
                minLines: 4,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'Ask a question',
                  hintText: 'What does the auth flow do? (max 99 words)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy ? null : _askQuestion,
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Send message'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildConversationRail(),
      ],
    );
  }

  Widget _buildChatPanel(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0C1520), Color(0xFF0B1220)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white12),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Conversation',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                _conversationTurns.isEmpty
                    ? 'No messages yet. Ask a question to begin the session memory.'
                    : 'This session keeps the last exchanges in context so follow-up questions stay grounded.',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              if (_streamingQuestion.isNotEmpty) ...[
                _bubble(
                  title: 'You',
                  accent: const Color(0xFF22C55E),
                  child: Text(
                    _streamingQuestion,
                    style: const TextStyle(height: 1.45),
                  ),
                ),
                const SizedBox(height: 10),
                _bubble(
                  title: 'Assistant',
                  accent: const Color(0xFFF59E0B),
                  child: SelectableText(
                    _streamingAnswer.isEmpty
                        ? 'Streaming answer...'
                        : _streamingAnswer,
                    style: const TextStyle(height: 1.5),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_conversationTurns.isEmpty && _streamingQuestion.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1A29),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Text(
                    'Your chat history will appear here. Each new question is appended to the session, and previous turns are sent back as memory.',
                    style: TextStyle(height: 1.45),
                  ),
                )
              else
                ..._conversationTurns.reversed.map((turn) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _bubble(
                          title: 'You',
                          accent: const Color(0xFF22C55E),
                          child: Text(
                            turn.question,
                            style: const TextStyle(height: 1.45),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _bubble(
                          title: 'Assistant',
                          accent: const Color(0xFF38BDF8),
                          child: SelectableText(
                            turn.answer,
                            style: const TextStyle(height: 1.5),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${turn.timeLabel} · ${turn.retrievedCount} chunks used',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildEvidencePanel(),
      ],
    );
  }

  Widget _buildConversationRail() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1724),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Session memory',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            _conversationTurns.isEmpty
                ? 'No stored turns yet.'
                : 'Last ${_conversationTurns.length} turn(s) retained for follow-up questions.',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          if (_conversationTurns.isEmpty)
            const Text(
              'Once you send a question, the exchange will remain in this session until you reset or start a new session.',
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _conversationTurns.reversed
                  .take(6)
                  .map((turn) {
                    return Chip(
                      label: Text(
                        '${turn.timeLabel} · ${_shorten(turn.question)}',
                      ),
                      backgroundColor: const Color(0xFF142235),
                      side: const BorderSide(color: Colors.white10),
                      labelStyle: const TextStyle(color: Colors.white),
                    );
                  })
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }

  Widget _buildEvidencePanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1724),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Retrieved context',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SelectableText(
            _contextPreview.isEmpty
                ? 'No retrieval context yet.'
                : _contextPreview,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Retrieved chunks',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              if (_retrievedChunks.isNotEmpty)
                Switch.adaptive(
                  value: _showFullSnippets,
                  onChanged: (value) {
                    setState(() {
                      _showFullSnippets = value;
                    });
                  },
                ),
            ],
          ),
          if (_retrievedChunks.isEmpty)
            const Text('No retrieved chunks yet.')
          else
            ..._retrievedChunks.map((chunk) {
              final snippet = chunk.preview(full: _showFullSnippets);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white12),
                    borderRadius: BorderRadius.circular(18),
                    color: const Color(0xFF101C2A),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              '${chunk.locationLabel} · ${chunk.symbol}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copy snippet',
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: chunk.snippet),
                              );
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Copied ${chunk.locationLabel}',
                                    ),
                                  ),
                                );
                            },
                            icon: const Icon(Icons.copy),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _tag(
                            'Confidence ${(chunk.confidence * 100).toStringAsFixed(1)}%',
                          ),
                          _tag('Similarity ${chunk.score.toStringAsFixed(3)}'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        snippet.isEmpty ? '(empty snippet)' : snippet,
                        style: const TextStyle(height: 1.45),
                      ),
                      if (!_showFullSnippets && chunk.snippet.length > 500)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Snippet trimmed. Enable full snippets to expand.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _bubble({
    required String title,
    required Color accent,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111B2B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1A29),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Text(
        '$label: $value',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _tag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF172433),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, color: Colors.white70),
      ),
    );
  }

  String _shorten(String text, [int maxLength = 28]) {
    final trimmed = text.trim();
    if (trimmed.length <= maxLength) {
      return trimmed;
    }
    return '${trimmed.substring(0, maxLength - 1)}…';
  }

  int _wordCount(String text) {
    return text
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .length;
  }
}
