import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/transcript.dart';
import '../../data/api_client.dart';

class TranscriptScreen extends StatefulWidget {
  final String lectureId;

  const TranscriptScreen({
    super.key,
    required this.lectureId,
  });

  @override
  State<TranscriptScreen> createState() => _TranscriptScreenState();
}

class _TranscriptScreenState extends State<TranscriptScreen> {
  Transcript? _transcript;
  bool _isLoading = true;
  String? _error;
  bool _showTimestamps = true;

  @override
  void initState() {
    super.initState();
    _loadTranscript();
  }

  Future<void> _loadTranscript() async {
    try {
      final transcript = await apiClient.getTranscript(widget.lectureId);
      setState(() {
        _transcript = transcript;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _copyFullText() {
    if (_transcript != null) {
      Clipboard.setData(ClipboardData(text: _transcript!.fullText));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Текст скопирован')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Транскрипт'),
        actions: [
          IconButton(
            icon: Icon(_showTimestamps ? Icons.timer : Icons.timer_off),
            tooltip: _showTimestamps ? 'Скрыть таймкоды' : 'Показать таймкоды',
            onPressed: () {
              setState(() {
                _showTimestamps = !_showTimestamps;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Скопировать весь текст',
            onPressed: _copyFullText,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Ошибка: $_error'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadTranscript,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    final transcript = _transcript!;

    if (_showTimestamps) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: transcript.segments.length,
        itemBuilder: (context, index) {
          final segment = transcript.segments[index];
          return _SegmentTile(segment: segment);
        },
      );
    } else {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          transcript.fullText,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            height: 1.6,
          ),
        ),
      );
    }
  }
}

class _SegmentTile extends StatelessWidget {
  final TranscriptSegment segment;

  const _SegmentTile({required this.segment});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              segment.timestampText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colorScheme.onPrimaryContainer,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              segment.text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
