import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/local_recording.dart';
import '../../data/upload_queue.dart';
import '../../data/local_recordings_repository.dart';
import '../../app/routes.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isPaused = false;
  String? _recordingPath;
  Duration _duration = Duration.zero;
  Timer? _timer;
  
  final TextEditingController _titleController = TextEditingController();
  String _selectedLanguage = 'auto';

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    _titleController.dispose();
    super.dispose();
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

    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _recordingPath = '${directory.path}/lecture_$timestamp.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: _recordingPath!,
    );

    setState(() {
      _isRecording = true;
      _isPaused = false;
      _duration = Duration.zero;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPaused) {
        setState(() {
          _duration += const Duration(seconds: 1);
        });
      }
    });
  }

  Future<void> _pauseRecording() async {
    await _recorder.pause();
    setState(() {
      _isPaused = true;
    });
  }

  Future<void> _resumeRecording() async {
    await _recorder.resume();
    setState(() {
      _isPaused = false;
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final path = await _recorder.stop();
    
    setState(() {
      _isRecording = false;
      _isPaused = false;
      _recordingPath = path;
    });

    if (path != null) {
      _showUploadDialog();
    }
  }

  void _showUploadDialog() {
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
              _deleteRecording();
            },
            child: const Text('Удалить'),
          ),
          TextButton.icon(
            onPressed: () async {
              if (_recordingPath == null) return;
              final f = File(_recordingPath!);
              if (f.existsSync()) await Share.shareXFiles([XFile(_recordingPath!)], text: _titleController.text.isEmpty ? null : _titleController.text);
            },
            icon: const Icon(Icons.save_alt, size: 18),
            label: const Text('Сохранить копию'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _enqueueAndGoToLectures();
            },
            child: const Text('Загрузить на сервер'),
          ),
        ],
      ),
    );
  }

  void _deleteRecording() {
    if (_recordingPath != null) {
      final file = File(_recordingPath!);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
    setState(() {
      _recordingPath = null;
      _duration = Duration.zero;
    });
  }

  /// Сохраняет запись в локальный список (файл не удаляется при ошибке загрузки),
  /// добавляет в очередь загрузки и переходит к списку лекций.
  void _enqueueAndGoToLectures() {
    if (_recordingPath == null) return;

    final title = _titleController.text.trim();
    final language = _selectedLanguage == 'auto' ? null : _selectedLanguage;

    final local = LocalRecording(
      path: _recordingPath!,
      title: title.isEmpty ? '' : title,
      language: language,
      createdAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    localRecordingsRepository.add(local);

    uploadQueue.addTask(
      filePath: _recordingPath!,
      title: title.isEmpty ? null : title,
      language: language,
    );

    _recordingPath = null;
    _duration = Duration.zero;
    _titleController.clear();
    _selectedLanguage = 'auto';
    setState(() {});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Запись сохранена локально и добавлена в очередь загрузки. При ошибке можно повторить из «Локальные записи».'),
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
                      _formatDuration(_duration),
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontFeatures: [const FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  
                  // Recording indicator
                  if (_isRecording)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: _isPaused ? Colors.orange : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  const SizedBox(height: 48),
                  
                  // Control buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isRecording) ...[
                        // Pause/Resume button
                        FloatingActionButton(
                          heroTag: 'pause',
                          onPressed: _isPaused ? _resumeRecording : _pauseRecording,
                          child: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                        ),
                        const SizedBox(width: 32),
                      ],
                      
                      // Main record/stop button
                      FloatingActionButton.large(
                        heroTag: 'record',
                        onPressed: _isRecording ? _stopRecording : _startRecording,
                        backgroundColor: _isRecording ? Colors.red : colorScheme.primary,
                        child: Icon(
                          _isRecording ? Icons.stop : Icons.mic,
                          size: 36,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  
                  // Status text
                  Text(
                    _isRecording
                        ? (_isPaused ? 'Пауза' : 'Идёт запись...')
                        : 'Нажмите для начала записи',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
        ),
      ),
    );
  }
}
