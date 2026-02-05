import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../../models/local_recording.dart';
import '../../models/upload_task.dart';
import '../../data/local_recordings_repository.dart';
import '../../data/upload_queue.dart';
import '../../app/routes.dart';

class LocalRecordingsScreen extends StatefulWidget {
  const LocalRecordingsScreen({super.key});

  @override
  State<LocalRecordingsScreen> createState() => _LocalRecordingsScreenState();
}

class _LocalRecordingsScreenState extends State<LocalRecordingsScreen> {
  List<LocalRecording> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await localRecordingsRepository.getAllWithDiscovered();
    if (mounted) setState(() {
      _list = list;
      _loading = false;
    });
  }

  bool _isInQueue(String path) {
    return uploadQueue.tasks.any((t) => t.filePath == path);
  }

  UploadTask? _taskForPath(String path) {
    try {
      return uploadQueue.tasks.firstWhere((t) => t.filePath == path);
    } catch (_) {
      return null;
    }
  }

  Future<void> _playFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Файл не найден')),
        );
      }
      return;
    }
    final player = AudioPlayer();
    try {
      await player.setFilePath(path);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _LocalPlayerDialog(path: path, player: player),
      );
    } finally {
      await player.dispose();
    }
  }

  Future<void> _shareFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Файл не найден')),
        );
      }
      return;
    }
    await Share.shareXFiles([XFile(path)], text: 'Запись лекции');
  }

  Future<void> _saveCopyToDownloads(LocalRecording rec) async {
    final file = File(rec.path);
    if (!file.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Файл не найден')),
        );
      }
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final name = '${rec.title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_')}_${rec.fileName}';
    final destPath = '${dir.path}/$name';
    await file.copy(destPath);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Копия сохранена: $name')),
      );
    }
    await Share.shareXFiles([XFile(destPath)], text: 'Копия записи');
  }

  void _retryUpload(LocalRecording rec) {
    final file = File(rec.path);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Файл не найден')),
      );
      return;
    }
    uploadQueue.addTask(
      filePath: rec.path,
      title: rec.title.isEmpty ? null : rec.title,
      language: rec.language,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Добавлено в очередь загрузки')),
    );
    Navigator.pushNamed(context, AppRoutes.lectures);
  }

  Future<void> _deleteRecording(LocalRecording rec) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить запись?'),
        content: Text(
          '«${rec.title.isEmpty ? rec.fileName : rec.title}» будет удалена с устройства.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final file = File(rec.path);
    if (file.existsSync()) file.deleteSync();
    await localRecordingsRepository.removeByPath(rec.path);
    final task = _taskForPath(rec.path);
    if (task != null) uploadQueue.remove(task);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Локальные записи'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _list.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_off_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Нет локальных записей',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Записанные лекции появятся здесь.\nМожно воспроизвести, сохранить копию или отправить на сервер.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : ListenableBuilder(
                  listenable: uploadQueue,
                  builder: (context, _) {
                    return RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _list.length,
                        itemBuilder: (context, index) {
                          final rec = _list[index];
                          final exists = File(rec.path).existsSync();
                          final task = _taskForPath(rec.path);
                          return _LocalRecordingCard(
                            recording: rec,
                            fileExists: exists,
                            uploadTask: task,
                            onPlay: () => _playFile(rec.path),
                            onShare: () => _shareFile(rec.path),
                            onSaveCopy: () => _saveCopyToDownloads(rec),
                            onRetryUpload: () => _retryUpload(rec),
                            onDelete: () => _deleteRecording(rec),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}

class _LocalRecordingCard extends StatelessWidget {
  final LocalRecording recording;
  final bool fileExists;
  final UploadTask? uploadTask;
  final VoidCallback onPlay;
  final VoidCallback onShare;
  final VoidCallback onSaveCopy;
  final VoidCallback onRetryUpload;
  final VoidCallback onDelete;

  const _LocalRecordingCard({
    required this.recording,
    required this.fileExists,
    required this.uploadTask,
    required this.onPlay,
    required this.onShare,
    required this.onSaveCopy,
    required this.onRetryUpload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr = DateFormat('dd.MM.yyyy, HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(recording.createdAtMillis),
    );
    final title = recording.title.isEmpty ? recording.fileName : recording.title;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                PopupMenuButton<String>(
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'delete', child: Text('Удалить')),
                  ],
                  onSelected: (v) {
                    if (v == 'delete') onDelete();
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              dateStr,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (!fileExists)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Файл не найден',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            if (uploadTask != null) ...[
              const SizedBox(height: 8),
              _UploadStatusRow(task: uploadTask!),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (fileExists) ...[
                  FilledButton.tonalIcon(
                    onPressed: onPlay,
                    icon: const Icon(Icons.play_arrow, size: 20),
                    label: const Text('Слушать'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: onShare,
                    icon: const Icon(Icons.share, size: 20),
                    label: const Text('Поделиться'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: onSaveCopy,
                    icon: const Icon(Icons.save_alt, size: 20),
                    label: const Text('Сохранить копию'),
                  ),
                  if (uploadTask == null || uploadTask!.isFailed)
                    FilledButton.tonalIcon(
                      onPressed: onRetryUpload,
                      icon: const Icon(Icons.cloud_upload, size: 20),
                      label: const Text('Загрузить на сервер'),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadStatusRow extends StatelessWidget {
  final UploadTask task;

  const _UploadStatusRow({required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String text;
    if (task.isUploading) {
      text = 'Загрузка ${task.uploadPercent}%';
    } else if (task.isProcessing) {
      text = task.processingPercent != null
          ? 'Обработка ${task.processingPercent}%'
          : 'Обработка на сервере...';
    } else if (task.isFailed) {
      text = 'Ошибка загрузки. Можно повторить.';
    } else {
      text = 'Загружено';
    }
    return Row(
      children: [
        Icon(
          task.isFailed ? Icons.error_outline : Icons.cloud_upload,
          size: 18,
          color: task.isFailed ? theme.colorScheme.error : theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: task.isFailed ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (task.isUploading || task.isProcessing)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
  }
}

class _LocalPlayerDialog extends StatefulWidget {
  final String path;
  final AudioPlayer player;

  const _LocalPlayerDialog({required this.path, required this.player});

  @override
  State<_LocalPlayerDialog> createState() => _LocalPlayerDialogState();
}

class _LocalPlayerDialogState extends State<_LocalPlayerDialog> {
  Duration _position = Duration.zero;
  Duration? _duration;

  @override
  void initState() {
    super.initState();
    widget.player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    widget.player.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
  }

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Воспроизведение'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<PlayerState>(
            stream: widget.player.playerStateStream,
            builder: (context, snapshot) {
              final state = snapshot.data;
              final playing = state?.playing ?? false;
              return IconButton.filled(
                iconSize: 48,
                onPressed: () async {
                  if (playing) {
                    await widget.player.pause();
                  } else {
                    await widget.player.play();
                  }
                },
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              );
            },
          ),
          const SizedBox(height: 12),
          if (_duration != null && _duration!.inMilliseconds > 0)
            Slider(
              value: _position.inMilliseconds.clamp(0, _duration!.inMilliseconds).toDouble(),
              max: _duration!.inMilliseconds.toDouble(),
              onChanged: (v) => widget.player.seek(Duration(milliseconds: v.round())),
            ),
          Text(
            '${_format(_position)} / ${_duration != null ? _format(_duration!) : "--:--"}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}
