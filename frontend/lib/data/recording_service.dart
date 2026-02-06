import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

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

    // Check permissions should be handled by UI before calling this, 
    // but good to have a check if possible. Assuming mostly granted.
    
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
    // Assuming path matches _currentPath
    
    _isRecording = false;
    _isPaused = false;
    // We keep _duration and _currentPath for a moment in case UI needs it, 
    // or we can reset them. Let's reset them after returning.
    final resultPath = _currentPath;

    // Reset state
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
     }
     _isRecording = false;
     _isPaused = false;
     _currentPath = null;
     _duration = Duration.zero;
     notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPaused && _isRecording) {
        _duration += const Duration(seconds: 1);
        notifyListeners();
      }
    });
  }
}

final recordingService = RecordingService();
