import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/local_recording.dart';

const _keyList = 'local_recordings_list';

class LocalRecordingsRepository {
  List<LocalRecording> _list = [];
  bool _loaded = false;

  List<LocalRecording> get list => List.unmodifiable(_list);

  Future<void> _load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyList);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _list = decoded
            .map((e) => LocalRecording.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _list = [];
      }
    } else {
      _list = [];
    }
    _loaded = true;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_list.map((e) => e.toJson()).toList());
    await prefs.setString(_keyList, encoded);
  }

  Future<void> add(LocalRecording recording) async {
    await _load();
    if (_list.any((e) => e.path == recording.path)) return;
    _list.insert(0, recording);
    await _save();
  }

  Future<void> removeByPath(String path) async {
    await _load();
    _list.removeWhere((e) => e.path == path);
    await _save();
  }

  Future<List<LocalRecording>> getAll() async {
    await _load();
    return List.from(_list);
  }
}

final localRecordingsRepository = LocalRecordingsRepository();
