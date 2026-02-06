import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/local_recording.dart';
import '../../data/upload_queue.dart';
import '../../data/local_recordings_repository.dart';
import '../../data/recording_service.dart';
import '../../app/routes.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  final TextEditingController _titleController = TextEditingController();
  String _selectedLanguage = 'auto';

  @override
  void initState() {
    super.initState();
    recordingService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    recordingService.removeListener(_onServiceUpdate);
    _titleController.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<bool> _requestPermissions() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> _startRecording() async {
    if (!await _requestPermissions()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Разрешение на микрофон не получено')),
        );
      }
      return;
    }
    await recordingService.startRecording();
  }

  Future<void> _pauseRecording() async {
    await recordingService.pauseRecording();
  }

  Future<void> _resumeRecording() async {
    await recordingService.resumeRecording();
  }

  Future<void> _stopRecording() async {
    final path = await recordingService.stopRecording();
    if (path != null && mounted) {
      _showUploadDialog(path);
    }
  }

  void _showUploadDialog(String path) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Сохранить запись'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Название лекции',
                hintText: 'Введите название...',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedLanguage,
              decoration: const InputDecoration(
                labelText: 'Язык',
              ),
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('Автоопределение')),
                DropdownMenuItem(value: 'ru', child: Text('Русский')),
                DropdownMenuItem(value: 'kz', child: Text('Қазақша')),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: (value) {
                _selectedLanguage = value ?? 'auto';
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteFile(path);
            },
            child: const Text('Удалить'),
          ),
          TextButton.icon(
            onPressed: () async {
              final f = File(path);
              if (f.existsSync()) await Share.shareXFiles([XFile(path)], text: _titleController.text.isEmpty ? null : _titleController.text);
            },
            icon: const Icon(Icons.save_alt, size: 18),
            label: const Text('Сохранить копию'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _enqueueAndGoToLectures(path);
            },
            child: const Text('Загрузить на сервер'),
          ),
        ],
      ),
    );
  }

  void _deleteFile(String path) {
    final file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
    if (mounted) setState(() {});
  }

  void _enqueueAndGoToLectures(String path) {
    final title = _titleController.text.trim();
    final language = _selectedLanguage == 'auto' ? null : _selectedLanguage;

    final local = LocalRecording(
      path: path,
      title: title.isEmpty ? '' : title,
      language: language,
      createdAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    localRecordingsRepository.add(local);

    uploadQueue.addTask(
      filePath: path,
      title: title.isEmpty ? null : title,
      language: language,
    );

    _titleController.clear();
    _selectedLanguage = 'auto';

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Запись сохранена локально и добавлена в очередь загрузки.'),
        ),
      );
      Navigator.of(context).pushReplacementNamed(AppRoutes.lectures);
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isRecording = recordingService.isRecording;
    final isPaused = recordingService.isPaused;
    final duration = recordingService.duration;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Запись лекции'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Timer display
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 16,
              ),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _formatDuration(duration),
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 48),
            
            // Recording indicator
            if (isRecording)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: isPaused ? Colors.orange : Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            const SizedBox(height: 48),
            
            // Control buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isRecording) ...[
                  // Pause/Resume button
                  FloatingActionButton(
                    heroTag: 'pause',
                    onPressed: isPaused ? _resumeRecording : _pauseRecording,
                    child: Icon(isPaused ? Icons.play_arrow : Icons.pause),
                  ),
                  const SizedBox(width: 32),
                ],
                
                // Main record/stop button
                FloatingActionButton.large(
                  heroTag: 'record',
                  onPressed: isRecording ? _stopRecording : _startRecording,
                  backgroundColor: isRecording ? Colors.red : colorScheme.primary,
                  child: Icon(
                    isRecording ? Icons.stop : Icons.mic,
                    size: 36,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            
            // Status text
            Text(
              isRecording
                  ? (isPaused ? 'Пауза' : 'Идёт запись...')
                  : 'Нажмите для начала записи',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
