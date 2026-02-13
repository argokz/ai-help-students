import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../models/lecture.dart' show Lecture, LectureSearchResult;
import '../../models/upload_task.dart' show UploadTask;
import '../../data/api_client.dart';
import '../../data/auth_repository.dart';
import '../../data/upload_queue.dart';
import '../../app/routes.dart';
import '../../core/layout/responsive.dart';
import '../../core/utils/error_handler.dart';

class LecturesScreen extends StatefulWidget {
  final bool isMainTab;
  const LecturesScreen({super.key, this.isMainTab = false});

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
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadLectures();
    });
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
    final titleController = TextEditingController(text: file?.name ?? '');
    var selectedLanguage = 'auto';

    final dialogResult = await showDialog<Map<String, String>>(
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
    if (dialogResult == null || !mounted) return;

    uploadQueue.addTask(
      filePath: path,
      title: (dialogResult['title'] ?? '').isEmpty ? null : dialogResult['title'],
      language: (dialogResult['language'] ?? 'auto') == 'auto' ? null : dialogResult['language'],
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавлено в очередь загрузки')),
      );
    }
  }

  Future<void> _loadLectures() async {
    if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        _lectures = result.lectures;
        _subjects = result.subjects;
        _groups = result.groups;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorHandler.getMessage(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _runSearch() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      if (mounted) setState(() => _searchResults = null);
      return;
    }
    if (!mounted) return;
    setState(() => _isSearching = true);
    try {
      final results = await apiClient.searchLectures(
        q,
        subject: _selectedSubject,
        groupName: _selectedGroup,
      );
      if (!mounted) return;
      setState(() {
        _searchQuery = q;
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: uploadQueue,
        builder: (context, _) {
          return RefreshIndicator(
            onRefresh: _loadLectures,
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  title: const Text('Мои лекции'),
                  floating: true,
                  pinned: true,
                  actions: [
                     IconButton(
                      icon: const Icon(Icons.chat_bubble_outline),
                      tooltip: 'Общий чат',
                      onPressed: () => Navigator.pushNamed(context, AppRoutes.globalChat),
                    ),
                    IconButton(
                      icon: const Icon(Icons.upload_file),
                      tooltip: 'Загрузить файл',
                      onPressed: _pickAndUploadFile,
                    ),
                  ],
                ),
                if (uploadQueue.tasks.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _UploadTasksSection(
                      tasks: uploadQueue.tasks,
                      onRetry: uploadQueue.retry,
                      onDismiss: uploadQueue.remove,
                    ),
                  ),
                _buildContent(),
              ],
            ),
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

  Widget _buildContent() {
    final padding = Responsive.contentPadding(context);
    final crossAxisCount = Responsive.gridCrossAxisCount(context);

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(padding, 0, padding, padding + 80),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
           Column(
             crossAxisAlignment: CrossAxisAlignment.stretch,
             children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'Поиск по названию...',
                          prefixIcon: Icon(Icons.search),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _runSearch(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _isSearching ? null : _runSearch,
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _isSearching
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.arrow_forward),
                    ),
                  ],
                ),
                if (_searchResults != null && _searchQuery.isNotEmpty) 
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchResults = null;
                          _searchQuery = '';
                        });
                      },
                      child: const Text('Очистить поиск'),
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
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
                      ),
                      ..._subjects.map((s) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(s, overflow: TextOverflow.ellipsis),
                              selected: _selectedSubject == s,
                              onSelected: (_) async {
                                setState(() {
                                  _selectedSubject = _selectedSubject == s ? null : s;
                                  _selectedGroup = null;
                                });
                                await _loadLectures();
                              },
                            ),
                          )),
                      ..._groups.map((g) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(g, overflow: TextOverflow.ellipsis),
                              selected: _selectedGroup == g,
                              onSelected: (_) async {
                                setState(() {
                                  _selectedGroup = _selectedGroup == g ? null : g;
                                  _selectedSubject = null;
                                });
                                await _loadLectures();
                              },
                            ),
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
             ],
           ),
           if (_isLoading)
             const Padding(
               padding: EdgeInsets.all(32.0),
               child: Center(child: CircularProgressIndicator()),
             )
           else if (_error != null)
              Padding(
               padding: EdgeInsets.all(32.0),
               child: Center(
                 child: Column(
                   children: [
                     const Icon(Icons.error_outline, size: 48, color: Colors.red),
                     const SizedBox(height: 16),
                     Text('Ошибка: $_error'),
                     TextButton(onPressed: _loadLectures, child: const Text('Повторить')),
                   ],
                 ),
               ),
             )
           else if ((_searchResults != null && _searchResults!.isEmpty) || (_lectures != null && _lectures!.isEmpty))
              Padding(
               padding: const EdgeInsets.all(32.0),
               child: Center(
                 child: Column(
                   children: [
                     Icon(Icons.school_outlined, size: 64, color: Theme.of(context).disabledColor),
                     const SizedBox(height: 16),
                     Text(
                       _searchResults != null ? 'Ничего не найдено' : 'Нет лекций',
                       style: Theme.of(context).textTheme.titleMedium?.copyWith(
                         color: Theme.of(context).disabledColor,
                       ),
                     ),
                   ],
                 ),
               ),
             )
           else
             ListView.builder(
               shrinkWrap: true,
               physics: const NeverScrollableScrollPhysics(),
               itemCount: _searchResults?.length ?? _lectures?.length ?? 0,
               itemBuilder: (context, index) {
                 if (_searchResults != null) {
                   final r = _searchResults![index];
                   return Padding(
                     padding: const EdgeInsets.only(bottom: 12),
                     child: _SearchResultCard(
                       result: r,
                       onTap: () => Navigator.pushNamed(
                         context,
                         AppRoutes.lectureDetail,
                         arguments: r.id,
                       ),
                     ),
                   );
                 } else {
                   final lecture = _lectures![index];
                   return Padding(
                     padding: const EdgeInsets.only(bottom: 12),
                     child: _LectureCard(
                       lecture: lecture,
                       onTap: () {
                         Navigator.pushNamed(
                           context,
                           AppRoutes.lectureDetail,
                           arguments: lecture.id,
                         );
                       },
                       onDelete: () => _onDeleteLecture(context, lecture),
                     ),
                   );
                 }
               },
             ),
        ]),
      ),
    );
  }

  Future<void> _onDeleteLecture(BuildContext context, Lecture lecture) async {
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
    if (confirm != true) return;
    final deletedId = lecture.id;
    setState(() {
      _lectures = _lectures?.where((l) => l.id != deletedId).toList() ?? [];
      _searchResults = null;
      _searchQuery = '';
      _searchController.clear();
    });
    try {
      await apiClient.deleteLecture(deletedId);
      if (!mounted) return;
      await _loadLectures();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Лекция удалена')),
      );
    } catch (e) {
      if (mounted) {
        await _loadLectures();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка удаления: ${ErrorHandler.getMessage(e)}')),
        );
      }
    }
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: InkWell(
        onTap: lecture.isReady ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lecture.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (lecture.subject != null || lecture.groupName != null) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (lecture.subject != null && lecture.subject!.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    lecture.subject!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              if (lecture.groupName != null && lecture.groupName!.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.secondaryContainer.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    lecture.groupName!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSecondaryContainer,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  PopupMenuButton(
                    icon: Icon(Icons.more_vert, size: 20, color: theme.disabledColor),
                    padding: EdgeInsets.zero,
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: Colors.red, size: 20),
                            SizedBox(width: 8),
                            Text('Удалить', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      if (value == 'delete') onDelete();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _StatusChip(status: lecture.status),
                  const Spacer(),
                  Icon(Icons.access_time, size: 14, color: theme.disabledColor),
                  const SizedBox(width: 4),
                  Text(
                    lecture.durationText,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
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
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.5)),
      ),
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (result.snippet != null)
                Text(
                  '...${result.snippet}...',
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
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
    final theme = Theme.of(context);
    Color color;
    String text;

    switch (status) {
      case 'processing':
        color = Colors.orange;
        text = 'Обработка';
        break;
      case 'completed':
        color = Colors.green;
        text = 'Готово';
        break;
      case 'ready': // Для обратной совместимости
        color = Colors.green;
        text = 'Готово';
        break;
      case 'failed':
        color = Colors.red;
        text = 'Ошибка';
        break;
      default:
        color = Colors.grey;
        text = 'Ожидание';
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
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
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
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: tasks.map((task) => _UploadTaskTile(
          task: task,
          onRetry: () => onRetry(task),
          onDismiss: () => onDismiss(task),
        )).toList(),
      ),
    );
  }
}

class _UploadTaskTile extends StatelessWidget {
  final UploadTask task;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  const _UploadTaskTile({
    required this.task,
    required this.onRetry,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(task.title ?? 'Загрузка...', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: task.errorMessage != null
            ? Text(task.errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12))
            : LinearProgressIndicator(value: task.isProcessing && task.processingProgress != null ? task.processingProgress : task.uploadProgress),
        trailing: task.errorMessage != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.blue),
                    onPressed: onRetry,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onDismiss,
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

class _DrawerAvatar extends StatelessWidget {
  final String? photoUrl;
  const _DrawerAvatar({this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 20,
      backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
      child: photoUrl == null ? const Icon(Icons.person) : null,
    );
  }
}
