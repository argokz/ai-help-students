import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/lecture.dart';
import '../../data/api_client.dart';
import '../../app/routes.dart';

class LectureDetailScreen extends StatefulWidget {
  final String lectureId;

  const LectureDetailScreen({
    super.key,
    required this.lectureId,
  });

  @override
  State<LectureDetailScreen> createState() => _LectureDetailScreenState();
}

class _LectureDetailScreenState extends State<LectureDetailScreen> {
  Lecture? _lecture;
  bool _isLoading = true;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadLecture();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLecture() async {
    try {
      final lecture = await apiClient.getLecture(widget.lectureId);
      setState(() {
        _lecture = lecture;
        _isLoading = false;
        _error = null;
      });

      // Poll for updates if still processing
      if (lecture.isProcessing) {
        _pollTimer?.cancel();
        _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
          _loadLecture();
        });
      } else {
        _pollTimer?.cancel();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_lecture?.title ?? 'Лекция'),
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
              onPressed: _loadLecture,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    final lecture = _lecture!;

    if (lecture.isProcessing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Обработка лекции...',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Распознавание речи и индексация',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              lecture.statusText,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    if (lecture.status == 'failed') {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Ошибка обработки',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('Попробуйте загрузить лекцию ещё раз'),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Lecture info card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lecture.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 20),
                    const SizedBox(width: 8),
                    Text('Длительность: ${lecture.durationText}'),
                  ],
                ),
                if (lecture.language != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.language, size: 20),
                      const SizedBox(width: 8),
                      Text('Язык: ${_languageName(lecture.language!)}'),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Actions
        Text(
          'Возможности',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),

        _ActionTile(
          icon: Icons.text_snippet,
          title: 'Транскрипт',
          subtitle: 'Полный текст с таймкодами',
          enabled: lecture.hasTranscript,
          onTap: () {
            Navigator.pushNamed(
              context,
              AppRoutes.transcript,
              arguments: lecture.id,
            );
          },
        ),

        _ActionTile(
          icon: Icons.summarize,
          title: 'Конспект',
          subtitle: 'Структурированные заметки',
          enabled: lecture.hasTranscript,
          onTap: () {
            Navigator.pushNamed(
              context,
              AppRoutes.summary,
              arguments: lecture.id,
            );
          },
        ),

        _ActionTile(
          icon: Icons.chat,
          title: 'Чат',
          subtitle: 'Задайте вопросы по лекции',
          enabled: lecture.hasTranscript,
          onTap: () {
            Navigator.pushNamed(
              context,
              AppRoutes.chat,
              arguments: lecture.id,
            );
          },
        ),
      ],
    );
  }

  String _languageName(String code) {
    switch (code) {
      case 'ru':
        return 'Русский';
      case 'kk':
      case 'kz':
        return 'Қазақша';
      case 'en':
        return 'English';
      default:
        return code.toUpperCase();
    }
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: enabled
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          child: Icon(
            icon,
            color: enabled
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        enabled: enabled,
        onTap: enabled ? onTap : null,
      ),
    );
  }
}
