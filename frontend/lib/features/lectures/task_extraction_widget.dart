import 'package:flutter/material.dart';
import '../../data/api_client.dart';
import '../../data/notification_service.dart';
import '../../core/utils/error_handler.dart';

class TaskExtractionWidget extends StatefulWidget {
  final String lectureId;
  final bool hasTranscript;

  const TaskExtractionWidget({
    super.key,
    required this.lectureId,
    required this.hasTranscript,
  });

  @override
  State<TaskExtractionWidget> createState() => _TaskExtractionWidgetState();
}

class _TaskExtractionWidgetState extends State<TaskExtractionWidget> {
  List<Map<String, dynamic>> _tasks = [];
  bool _isLoading = false;
  bool _extracted = false;

  Future<void> _extractTasks() async {
    setState(() => _isLoading = true);
    try {
      final result = await apiClient.extractTasksFromLecture(widget.lectureId);
      final tasks = result['tasks'] as List;

      if (mounted) {
        setState(() {
          _tasks = tasks.cast<Map<String, dynamic>>();
          _extracted = true;
          _isLoading = false;
        });

        if (_tasks.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('🤖 Задания не найдены в лекции')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: ${ErrorHandler.getMessage(e)}')),
        );
      }
    }
  }

  Future<void> _addToTasks(Map<String, dynamic> task) async {
    try {
      task['lecture_id'] = widget.lectureId; // Link to lecture
      final savedTask = await apiClient.createTaskFromExtracted(task);
      
      // Schedule notification if due date is set
      if (savedTask.dueDate != null) {
        await notificationService.scheduleTaskReminder(savedTask);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Добавлено в задачи')),
        );
        setState(() => _tasks.remove(task));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: ${ErrorHandler.getMessage(e)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasTranscript) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.purple),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Умное извлечение заданий',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                if (!_extracted)
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _extractTasks,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    label: const Text('Найти'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'ИИ проанализирует лекцию и найдет упоминания дедлайнов, заданий и экзаменов',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (_tasks.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              ..._tasks.map((task) => _TaskCard(
                    task: task,
                    onAdd: () => _addToTasks(task),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final VoidCallback onAdd;

  const _TaskCard({required this.task, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final title = task['title'] ?? 'Задание';
    final description = task['description'];
    final deadlineText = task['deadline_text'];
    final deadlineDate = task['deadline_date'];
    final confidence = (task['confidence'] as num?)?.toDouble() ?? 0.0;

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 12),
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
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (confidence >= 0.8)
                  const Icon(Icons.verified, size: 16, color: Colors.green)
                else if (confidence >= 0.5)
                  const Icon(Icons.help_outline, size: 16, color: Colors.orange),
              ],
            ),
            if (description != null) ...[
              const SizedBox(height: 4),
              Text(description, style: const TextStyle(fontSize: 13)),
            ],
            if (deadlineText != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 14, color: Colors.red),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      deadlineText,
                      style: const TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
            if (deadlineDate != null) ...[
              const SizedBox(height: 4),
              Text(
                'Дата: $deadlineDate',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_task, size: 18),
                label: const Text('Добавить в задачи'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
