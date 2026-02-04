import 'package:flutter/material.dart';
import '../../models/lecture.dart';
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
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLectures();
  }

  Future<void> _loadLectures() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final lectures = await apiClient.getLectures();
      setState(() {
        _lectures = lectures;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
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

    if (_lectures == null || _lectures!.isEmpty) {
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
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _lectures!.length,
        itemBuilder: (context, index) {
          final lecture = _lectures![index];
          return _LectureCard(
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
                  _loadLectures();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка удаления: $e')),
                    );
                  }
                }
              }
            },
          );
        },
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
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              Text(
                'Обработка на сервере...',
                style: theme.textTheme.bodySmall,
              ),
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
