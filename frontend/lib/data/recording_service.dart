import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'recording_foreground_task.dart';

class RecordingService extends ChangeNotifier {
  static final RecordingService _instance = RecordingService._internal();
  factory RecordingService() => _instance;
  RecordingService._internal();

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isPaused = false;
  String? _currentPath;
  Duration _duration = Duration.zero;
  Timer? _timer;

  // Getters
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  String? get currentPath => _currentPath;
  Duration get duration => _duration;
  
  // Initialize (if needed) or dispose
  void disposeRecorder() {
    _timer?.cancel();
    _recorder.dispose();
  }

  Future<void> startRecording() async {
    if (_isRecording) return;

    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${directory.path}/lecture_$timestamp.m4a';
    _currentPath = path;

    // На Android запускаем foreground-сервис с типом microphone, чтобы при
    // блокировке экрана запись не прерывалась и микрофон продолжал работать.
    if (Platform.isAndroid) {
      final started = await startRecordingForegroundService();
      if (!started) {
        // Не удалось запустить сервис — запись может оборваться при блокировке
        debugPrint('RecordingService: foreground service failed to start');
      }
    }

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );

    _isRecording = true;
    _isPaused = false;
    _duration = Duration.zero;
    notifyListeners();

    _startTimer();
  }

  Future<void> pauseRecording() async {
    if (!_isRecording || _isPaused) return;
    await _recorder.pause();
    _isPaused = true;
    notifyListeners();
  }

  Future<void> resumeRecording() async {
    if (!_isRecording || !_isPaused) return;
    await _recorder.resume();
    _isPaused = false;
    notifyListeners();
  }

  Future<String?> stopRecording() async {
    if (!_isRecording) return null;
    
    _timer?.cancel();
    final path = await _recorder.stop();
    if (Platform.isAndroid) await stopRecordingForegroundService();
    
    _isRecording = false;
    _isPaused = false;
    final resultPath = _currentPath;

    _currentPath = null;
    _duration = Duration.zero;
    notifyListeners();
    
    return resultPath;
  }
  
  // Cancel recording and delete file
  Future<void> cancelRecording() async {
    _timer?.cancel();
    if (_isRecording) {
      await _recorder.stop();
      if (Platform.isAndroid) await stopRecordingForegroundService();
    }
    _isRecording = false;
    _isPaused = false;
    _currentPath = null;
    _duration = Duration.zero;
    notifyListeners();
  }

  static String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = d.inHours;
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPaused && _isRecording) {
        _duration += const Duration(seconds: 1);
        updateRecordingNotificationText(_formatDuration(_duration));
        notifyListeners();
      }
    });
  }
}

final recordingService = RecordingService();
