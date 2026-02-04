import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/lecture.dart';
import '../../data/api_client.dart';
import '../../data/auth_repository.dart';
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
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  Duration _position = Duration.zero;
  Duration? _duration;

  @override
  void initState() {
    super.initState();
    _loadLecture();
    _positionSub = _audioPlayer.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durationSub = _audioPlayer.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _playerStateSub = _audioPlayer.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playerStateSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playPauseAudio() async {
    if (_lecture == null) return;
    try {
      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
      } else {
        final token = await authRepository.getToken();
        if (token == null || token.isEmpty) return;
        final url = ApiClient.lectureAudioUrl(_lecture!.id);
        await _audioPlayer.setUrl(url, headers: {'Authorization': 'Bearer $token'});
        await _audioPlayer.play();
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка воспроизведения: $e')),
        );
      }
    }
  }

  Future<void> _showEditSubjectGroupDialog() async {
    if (_lecture == null) return;
    final subjectController = TextEditingController(text: _lecture!.subject);
    final groupController = TextEditingController(text: _lecture!.groupName);
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Предмет и группа'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subjectController,
                decoration: const InputDecoration(
                  labelText: 'Предмет',
                  hintText: 'Например: Математика',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: groupController,
                decoration: const InputDecoration(
                  labelText: 'Группа',
                  hintText: 'Например: ИС-21',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'subject': subjectController.text.trim(),
                'groupName': groupController.text.trim(),
              }),
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
    subjectController.dispose();
    groupController.dispose();
    if (result != null) {
      await _updateSubjectGroup(
        subject: result['subject'] ?? '',
        groupName: result['groupName'] ?? '',
      );
    }
  }

  Future<void> _updateSubjectGroup({
    String? subject,
    String? groupName,
  }) async {
    if (_lecture == null) return;
    try {
      final updated = await apiClient.updateLecture(
        _lecture!.id,
        subject: subject,
        groupName: groupName,
      );
      if (mounted) setState(() => _lecture = updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  Future<void> _downloadAudio() async {
    if (_lecture == null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final name = _lecture!.filename.isNotEmpty
          ? _lecture!.filename
          : 'lecture_${_lecture!.id}.m4a';
      final savePath = '${dir.path}/$name';
      await apiClient.downloadLectureAudio(_lecture!.id, savePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Сохранено: $name')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка скачивания: $e')),
        );
      }
    }
  }

  Future<void> _loadLecture() async {
    try {
      final lecture = await apiClient.getLecture(widget.lectureId);
      if (mounted) setState(() {
        _lecture = lecture;
        _isLoading = false;
        _error = null;
      });

      // Poll for updates if still processing
      if (mounted && lecture.isProcessing) {
        _pollTimer?.cancel();
        _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
          _loadLecture();
        });
      } else {
        _pollTimer?.cancel();
      }
    } catch (e) {
      if (mounted) setState(() {
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
                if (lecture.subject != null || lecture.groupName != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      if (lecture.subject != null && lecture.subject!.isNotEmpty)
                        Chip(label: Text(lecture.subject!)),
                      if (lecture.groupName != null && lecture.groupName!.isNotEmpty)
                        Chip(label: Text(lecture.groupName!)),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _showEditSubjectGroupDialog,
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Предмет / Группа'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Audio playback
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.audiotrack, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Аудио лекции',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.download),
                      tooltip: 'Скачать',
                      onPressed: _downloadAudio,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton.filled(
                      onPressed: _playPauseAudio,
                      icon: Icon(_audioPlayer.playing ? Icons.pause : Icons.play_arrow),
                      iconSize: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_duration != null && _duration!.inMilliseconds > 0)
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              ),
                              child: Slider(
                                value: _position.inMilliseconds.clamp(0, _duration!.inMilliseconds).toDouble(),
                                max: _duration!.inMilliseconds.toDouble(),
                                onChanged: (v) async {
                                  await _audioPlayer.seek(Duration(milliseconds: v.round()));
                                },
                              ),
                            ),
                          Text(
                            '${_formatDuration(_position)} / ${_duration != null ? _formatDuration(_duration!) : lecture.durationText}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$m:$s';
    return '$m:$s';
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
