import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/local_recording.dart';

const _keyList = 'local_recordings_list';
const _audioExtensions = ['.m4a', '.wav', '.mp3'];

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

  /// Список всех записей: из репозитория + найденные на диске в папке приложения.
  /// Записи только с диска получают title по имени файла и createdAt по lastModified.
  Future<List<LocalRecording>> getAllWithDiscovered() async {
    await _load();
    final fromRepo = Map.fromEntries(_list.map((e) => MapEntry(e.path, e)));

    try {
      final dir = await getApplicationDocumentsDirectory();
      final directory = Directory(dir.path);
      if (!directory.existsSync()) return _sortedList(fromRepo.values.toList());

      final entities = directory.listSync();
      for (final entity in entities) {
        if (entity is! File) continue;
        final path = entity.path;
        final ext = p.extension(path).toLowerCase();
        if (!_audioExtensions.contains(ext)) continue;
        if (fromRepo.containsKey(path)) continue;
        final lastModified = entity.lastModifiedSync();
        final name = p.basenameWithoutExtension(path);
        fromRepo[path] = LocalRecording(
          path: path,
          title: name,
          language: null,
          createdAtMillis: lastModified.millisecondsSinceEpoch,
        );
      }
    } catch (_) {
      // Оставляем только из репозитория при ошибке доступа к диску
    }

    return _sortedList(fromRepo.values.toList());
  }

  static List<LocalRecording> _sortedList(List<LocalRecording> list) {
    list.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
    return list;
  }
}

final localRecordingsRepository = LocalRecordingsRepository();
