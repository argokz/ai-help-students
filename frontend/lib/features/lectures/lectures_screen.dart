import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../models/lecture.dart' show Lecture, LectureSearchResult;
import '../../models/upload_task.dart';
import '../../data/api_client.dart';
import '../../data/auth_repository.dart';
import '../../data/upload_queue.dart';
import '../../app/routes.dart';

class LecturesScreen extends StatefulWidget {
  const LecturesScreen({super.key});

  @override
  State<LecturesScreen> createState() => _LecturesScreenState();
}

class _LecturesScreenState extends State<LecturesScreen> {
  List<Lecture>? _lectures;
  List<String> _subjects = [];
  List<String> _groups = [];
  String? _selectedSubject;
  String? _selectedGroup;
  String _searchQuery = '';
  List<LectureSearchResult>? _searchResults;
  bool _isSearching = false;
  bool _isLoading = true;
  String? _error;
  Timer? _processingTicker;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLectures();
    uploadQueue.onLectureCompleted = _onLectureCompleted;
    _startProcessingTicker();
  }

  void _startProcessingTicker() {
    _processingTicker?.cancel();
    _processingTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final hasProcessing = uploadQueue.tasks.any((t) => t.isProcessing);
      if (hasProcessing) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _processingTicker?.cancel();
    if (uploadQueue.onLectureCompleted == _onLectureCompleted) {
      uploadQueue.onLectureCompleted = null;
    }
    super.dispose();
  }

  void _onLectureCompleted() {
    if (mounted) _loadLectures();
  }

  Future<void> _pickAndUploadFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    final file = result?.files.singleOrNull;
    final path = file?.path;
    if (path == null || path.isEmpty) return;

    if (!mounted) return;
    final titleController = TextEditingController(text: file.name);
    var selectedLanguage = 'auto';

    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Загрузить аудио'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Название лекции',
                      hintText: 'Введите название...',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedLanguage,
                    decoration: const InputDecoration(labelText: 'Язык'),
                    items: const [
                      DropdownMenuItem(value: 'auto', child: Text('Автоопределение')),
                      DropdownMenuItem(value: 'ru', child: Text('Русский')),
                      DropdownMenuItem(value: 'kz', child: Text('Қазақша')),
                      DropdownMenuItem(value: 'en', child: Text('English')),
                    ],
                    onChanged: (value) {
                      setDialogState(() => selectedLanguage = value ?? 'auto');
                    },
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
                    'title': titleController.text.trim(),
                    'language': selectedLanguage,
                  }),
                  child: const Text('Загрузить'),
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
    if (result == null || !mounted) return;

    uploadQueue.addTask(
      filePath: path,
      title: result['title']!.isEmpty ? null : result['title'],
      language: result['language'] == 'auto' ? null : result['language'],
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавлено в очередь загрузки')),
      );
    }
  }

  Future<void> _loadLectures() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _searchResults = null;
    });
    try {
      final result = await apiClient.getLectures(
        subject: _selectedSubject,
        groupName: _selectedGroup,
      );
      setState(() {
        _lectures = result.lectures;
        _subjects = result.subjects;
        _groups = result.groups;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _runSearch() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      setState(() => _searchResults = null);
      return;
    }
    setState(() => _isSearching = true);
    try {
      final results = await apiClient.searchLectures(
        q,
        subject: _selectedSubject,
        groupName: _selectedGroup,
      );
      setState(() {
        _searchQuery = q;
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои лекции'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'Общий чат по всем лекциям',
            onPressed: () => Navigator.pushNamed(context, AppRoutes.globalChat),
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Загрузить аудиофайл',
            onPressed: _pickAndUploadFile,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLectures,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Выйти',
            onPressed: () async {
              await authRepository.logout();
              if (!context.mounted) return;
              Navigator.pushReplacementNamed(context, AppRoutes.login);
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: uploadQueue,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (uploadQueue.tasks.isNotEmpty)
                _UploadTasksSection(
                  tasks: uploadQueue.tasks,
                  onRetry: uploadQueue.retry,
                  onDismiss: uploadQueue.remove,
                ),
              Expanded(child: _buildBody()),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.pushNamed(context, AppRoutes.recording);
        },
        icon: const Icon(Icons.mic),
        label: const Text('Записать'),
      ),
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
              onPressed: _loadLectures,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    final showSearchResults = _searchResults != null;
    final listEmpty = _lectures == null || _lectures!.isEmpty;
    final searchEmpty = showSearchResults && _searchResults!.isEmpty;

    if (!showSearchResults && listEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.school_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Пока нет записей',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Нажмите "Записать" чтобы начать',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLectures,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Поиск
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Поиск по названию и тексту...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _runSearch(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _isSearching ? null : _runSearch,
                icon: _isSearching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
              ),
            ],
          ),
          if (_searchResults != null && _searchQuery.isNotEmpty) ...[
            TextButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchResults = null;
                  _searchQuery = '';
                });
              },
              child: const Text('Очистить поиск'),
            ),
          ],
          const SizedBox(height: 12),
          // Фильтры: предмет и группа
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('Все'),
                selected: _selectedSubject == null && _selectedGroup == null,
                onSelected: (_) async {
                  setState(() {
                    _selectedSubject = null;
                    _selectedGroup = null;
                  });
                  await _loadLectures();
                },
              ),
              ..._subjects.map((s) => FilterChip(
                    label: Text(s),
                    selected: _selectedSubject == s,
                    onSelected: (_) async {
                      setState(() {
                        _selectedSubject = _selectedSubject == s ? null : s;
                        _selectedGroup = null;
                      });
                      await _loadLectures();
                    },
                  )),
              ..._groups.map((g) => FilterChip(
                    label: Text(g),
                    selected: _selectedGroup == g,
                    onSelected: (_) async {
                      setState(() {
                        _selectedGroup = _selectedGroup == g ? null : g;
                        _selectedSubject = null;
                      });
                      await _loadLectures();
                    },
                  )),
            ],
          ),
          const SizedBox(height: 16),
          if (showSearchResults) ...[
            if (searchEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Ничего не найдено'),
                ),
              )
            else
              ..._searchResults!.map((r) => _SearchResultCard(
                    result: r,
                    onTap: () => Navigator.pushNamed(
                      context,
                      AppRoutes.lectureDetail,
                      arguments: r.id,
                    ),
                  )),
          ] else
            ..._lectures!.map((lecture) => _LectureCard(
                  lecture: lecture,
                  onTap: () {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.lectureDetail,
                      arguments: lecture.id,
                    );
                  },
                  onDelete: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Удалить лекцию?'),
                        content: Text('Лекция "${lecture.title}" будет удалена.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Отмена'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Удалить'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      try {
                        await apiClient.deleteLecture(lecture.id);
                        if (!mounted) return;
                        await _loadLectures();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Лекция удалена')),
                        );
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Ошибка удаления: $e')),
                          );
                        }
                      }
                    }
                  },
                )),
        ],
      ),
    );
  }
}

class _LectureCard extends StatelessWidget {
  final Lecture lecture;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _LectureCard({
    required this.lecture,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: lecture.isReady ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      lecture.title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton(
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Удалить'),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      if (value == 'delete') {
                        onDelete();
                      }
                    },
                  ),
                ],
              ),
              if (lecture.subject != null || lecture.groupName != null) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (lecture.subject != null && lecture.subject!.isNotEmpty)
                      Chip(
                        label: Text(lecture.subject!, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    if (lecture.groupName != null && lecture.groupName!.isNotEmpty)
                      Chip(
                        label: Text(lecture.groupName!, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  _StatusChip(status: lecture.status),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.access_time,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    lecture.durationText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (lecture.language != null) ...[
                    const SizedBox(width: 12),
                    Icon(
                      Icons.language,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      lecture.language!.toUpperCase(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
              if (lecture.isReady) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (lecture.hasTranscript)
                      _FeatureChip(
                        icon: Icons.text_snippet,
                        label: 'Транскрипт',
                      ),
                    if (lecture.hasSummary) ...[
                      const SizedBox(width: 8),
                      _FeatureChip(
                        icon: Icons.summarize,
                        label: 'Конспект',
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;

    switch (status) {
      case 'completed':
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case 'processing':
        color = Colors.orange;
        icon = Icons.hourglass_top;
        break;
      case 'failed':
        color = Colors.red;
        icon = Icons.error;
        break;
      default:
        color = Colors.grey;
        icon = Icons.schedule;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            _statusText(status),
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _statusText(String status) {
    switch (status) {
      case 'completed':
        return 'Готово';
      case 'processing':
        return 'Обработка';
      case 'failed':
        return 'Ошибка';
      default:
        return 'Ожидание';
    }
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onPrimaryContainer),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  final LectureSearchResult result;
  final VoidCallback onTap;

  const _SearchResultCard({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result.title,
                style: theme.textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (result.subject != null || result.groupName != null) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    if (result.subject != null)
                      Chip(
                        label: Text(result.subject!, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    if (result.groupName != null)
                      Chip(
                        label: Text(result.groupName!, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
              if (result.snippet != null && result.snippet!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  result.snippet!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadTasksSection extends StatelessWidget {
  final List<UploadTask> tasks;
  final void Function(UploadTask) onRetry;
  final void Function(UploadTask) onDismiss;

  const _UploadTasksSection({
    required this.tasks,
    required this.onRetry,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 1,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'Загрузки',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ...tasks.map((task) => _UploadTaskCard(
                  task: task,
                  onRetry: () => onRetry(task),
                  onDismiss: () => onDismiss(task),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

String _processingStatusText(UploadTask task) {
  if (task.processingStartedAt == null) return 'Обработка на сервере...';
  final elapsed = DateTime.now().difference(task.processingStartedAt!);
  final m = elapsed.inMinutes;
  final s = elapsed.inSeconds.remainder(60);
  if (m > 0) {
    return 'Обработка... $m:${s.toString().padLeft(2, '0')}';
  }
  return 'Обработка... ${s} сек';
}

class _UploadTaskCard extends StatelessWidget {
  final UploadTask task;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  const _UploadTaskCard({
    required this.task,
    required this.onRetry,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = task.title?.isNotEmpty == true ? task.title! : 'Без названия';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (task.isFailed)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: onDismiss,
                    tooltip: 'Убрать из списка',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (task.isUploading) ...[
              LinearProgressIndicator(value: task.uploadProgress),
              const SizedBox(height: 4),
              Text(
                'Загрузка ${task.uploadPercent}%',
                style: theme.textTheme.bodySmall,
              ),
            ] else if (task.isProcessing) ...[
              LinearProgressIndicator(
                value: task.processingProgress != null ? task.processingProgress : null,
              ),
              const SizedBox(height: 4),
              Text(
                task.processingPercent != null
                    ? 'Обработка ${task.processingPercent}%'
                    : _processingStatusText(task),
                style: theme.textTheme.bodySmall,
              ),
              if (task.processingPercent == null) ...[
                const SizedBox(height: 2),
                Text(
                  'Обычно 1–3 минуты',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ] else if (task.isFailed) ...[
              Text(
                task.errorMessage ?? 'Ошибка',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Повторить'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
