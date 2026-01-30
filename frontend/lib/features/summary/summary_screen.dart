import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/summary.dart';
import '../../data/api_client.dart';

class SummaryScreen extends StatefulWidget {
  final String lectureId;

  const SummaryScreen({
    super.key,
    required this.lectureId,
  });

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  Summary? _summary;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary({bool regenerate = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final summary = await apiClient.getSummary(
        widget.lectureId,
        regenerate: regenerate,
      );
      setState(() {
        _summary = summary;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String _formatAsText() {
    if (_summary == null) return '';
    
    final buffer = StringBuffer();
    
    buffer.writeln('КОНСПЕКТ ЛЕКЦИИ');
    buffer.writeln('=' * 40);
    buffer.writeln();
    
    buffer.writeln('📋 КРАТКОЕ СОДЕРЖАНИЕ');
    buffer.writeln(_summary!.briefSummary);
    buffer.writeln();
    
    if (_summary!.mainTopics.isNotEmpty) {
      buffer.writeln('📌 ОСНОВНЫЕ ТЕМЫ');
      for (final topic in _summary!.mainTopics) {
        buffer.writeln('• $topic');
      }
      buffer.writeln();
    }
    
    if (_summary!.keyDefinitions.isNotEmpty) {
      buffer.writeln('📖 КЛЮЧЕВЫЕ ОПРЕДЕЛЕНИЯ');
      for (final def in _summary!.keyDefinitions) {
        buffer.writeln('${def.term}: ${def.definition}');
      }
      buffer.writeln();
    }
    
    if (_summary!.importantFacts.isNotEmpty) {
      buffer.writeln('💡 ВАЖНЫЕ ФАКТЫ');
      for (final fact in _summary!.importantFacts) {
        buffer.writeln('• $fact');
      }
      buffer.writeln();
    }
    
    if (_summary!.assignments.isNotEmpty) {
      buffer.writeln('📝 ЗАДАНИЯ');
      for (final assignment in _summary!.assignments) {
        buffer.writeln('• $assignment');
      }
    }
    
    return buffer.toString();
  }

  void _copySummary() {
    Clipboard.setData(ClipboardData(text: _formatAsText()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Конспект скопирован')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Конспект'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Сгенерировать заново',
            onPressed: () => _loadSummary(regenerate: true),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Скопировать',
            onPressed: _summary != null ? _copySummary : null,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Генерация конспекта...'),
          ],
        ),
      );
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
              onPressed: () => _loadSummary(),
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    final summary = _summary!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Brief summary
        _SummarySection(
          icon: Icons.short_text,
          title: 'Краткое содержание',
          child: Text(
            summary.briefSummary,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),

        // Main topics
        if (summary.mainTopics.isNotEmpty)
          _SummarySection(
            icon: Icons.topic,
            title: 'Основные темы',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: summary.mainTopics
                  .map((topic) => _BulletPoint(text: topic))
                  .toList(),
            ),
          ),

        // Key definitions
        if (summary.keyDefinitions.isNotEmpty)
          _SummarySection(
            icon: Icons.book,
            title: 'Ключевые определения',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: summary.keyDefinitions
                  .map((def) => _DefinitionTile(definition: def))
                  .toList(),
            ),
          ),

        // Important facts
        if (summary.importantFacts.isNotEmpty)
          _SummarySection(
            icon: Icons.lightbulb,
            title: 'Важные факты',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: summary.importantFacts
                  .map((fact) => _BulletPoint(text: fact))
                  .toList(),
            ),
          ),

        // Assignments
        if (summary.assignments.isNotEmpty)
          _SummarySection(
            icon: Icons.assignment,
            title: 'Задания',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: summary.assignments
                  .map((assignment) => _BulletPoint(
                        text: assignment,
                        bulletColor: Colors.orange,
                      ))
                  .toList(),
            ),
          ),

        const SizedBox(height: 32),
      ],
    );
  }
}

class _SummarySection extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _SummarySection({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  final String text;
  final Color? bulletColor;

  const _BulletPoint({
    required this.text,
    this.bulletColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: bulletColor ?? Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _DefinitionTile extends StatelessWidget {
  final KeyDefinition definition;

  const _DefinitionTile({required this.definition});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            definition.term,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            definition.definition,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
