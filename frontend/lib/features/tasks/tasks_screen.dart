import 'package:flutter/material.dart';
import '../../models/task.dart';
import '../../data/api_client.dart';
import '../../data/notification_service.dart';
import '../../app/routes.dart';
import '../../core/utils/error_handler.dart';
import '../../core/mixins/safe_execution_mixin.dart';

class TasksScreen extends StatefulWidget {
  final bool isMainTab;
  const TasksScreen({super.key, this.isMainTab = false});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> with SingleTickerProviderStateMixin, SafeExecutionMixin {
  late TabController _tabController;
  List<Task> _allTasks = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadTasks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    await safeExecute(() async {
      final tasks = await apiClient.getTasks();
      if (mounted) {
        setState(() {
          _allTasks = tasks;
        });
      }
    }); // isLoading is handled by mixin, but we might want to show skeleton instead of full screen loader
        // for better UX, but for now mixin's loader is fine or we can customize.
        // Actually mixin sets _isLoading state, we can use it in build.
  }

  Future<void> _toggleTask(Task task) async {
    // Optimistic update
    final wasCompleted = task.isCompleted;
    setState(() {
      final index = _allTasks.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        _allTasks[index] = task.copyWith(isCompleted: !wasCompleted);
      }
    });

    try {
      final updatedTask = await apiClient.toggleTaskCompletion(task.id);
      if (updatedTask.isCompleted) {
        await notificationService.cancelTaskReminder(task.id);
      } else if (updatedTask.dueDate != null) {
        await notificationService.scheduleTaskReminder(updatedTask);
      }
      // Reload to ensure consistency (or just keep optimistic state if backend returns same)
      _loadTasks();
    } catch (e) {
      // Revert on error
      if (mounted) {
        setState(() {
           final index = _allTasks.indexWhere((t) => t.id == task.id);
           if (index != -1) {
             _allTasks[index] = task.copyWith(isCompleted: wasCompleted);
           }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: ${ErrorHandler.getMessage(e)}')),
        );
      }
    }
  }

  Future<void> _deleteTask(Task task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить задачу?'),
        content: Text('Задача "${task.title}" будет удалена.'),
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

    await safeExecute(() async {
      await apiClient.deleteTask(task.id);
      await notificationService.cancelTaskReminder(task.id);
      await _loadTasks();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Sort tasks: Active first by due date/priority, Completed by completion date (if available) or update time
    final activeTasks = _allTasks.where((t) => !t.isCompleted).toList();
    final completedTasks = _allTasks.where((t) => t.isCompleted).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Задачи'),
        automaticallyImplyLeading: !widget.isMainTab,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadTasks),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Активные (${activeTasks.length})'),
            Tab(text: 'Выполненные (${completedTasks.length})'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.pushNamed(context, AppRoutes.taskDetail);
          if (result == true) _loadTasks();
        },
        child: const Icon(Icons.add),
      ),
      body: isLoading && _allTasks.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTaskList(activeTasks),
                _buildTaskList(completedTasks),
              ],
            ),
    );
  }

  Widget _buildTaskList(List<Task> tasks) {
    if (tasks.isEmpty && !isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Theme.of(context).disabledColor),
            const SizedBox(height: 16),
            Text(
              'Нет задач',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).disabledColor,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTasks,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: tasks.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final task = tasks[index];
          return _TaskCard(
            task: task,
            onToggle: () => _toggleTask(task),
            onDelete: () => _deleteTask(task),
            onTap: () async {
              final result = await Navigator.pushNamed(
                context,
                AppRoutes.taskDetail,
                arguments: task.id,
              );
              if (result == true) _loadTasks();
            },
          );
        },
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _TaskCard({
    required this.task,
    required this.onToggle,
    required this.onDelete,
    required this.onTap,
  });

  Color _getPriorityColor() {
    switch (task.priority) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Priority Indicator
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: _getPriorityColor(),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                // Checkbox Area - Separate touch target logic is handled by standard Checkbox,
                // but we want to make sure the row doesn't capture tap if checkbox is tapped.
                // Standard Checkbox in Flutter captures its own taps.
                // However, user reported issues. Let's make it a dedicated InkWell/IconButton for better control if needed,
                // or just wrap Checkbox in a SizedBox/Transform scale for larger hit test.
                // Using standard Checkbox is usually fine if not overlaid by another InkWell.
                // Here, the parent Card > InkWell covers everything.
                // To fix the "hit test issue" where the card tap overrides checkbox or vice versa:
                // We should exclude the checkbox area from the card's InkWell or put the checkbox on top?
                // Actually, material Checkbox handles gestures. The issue might be the parent InkWell stealing it 
                // or the user finding it hard to hit.
                // A better UX pattern: The whole LEFT part including checkbox toggles it, or just a large leading area.
                // Let's explicitly wrap Checkbox in a widget that stops propagation if needed, 
                // but InkWell usually plays nice with interactive children.
                // Let's try using a dedicated IconButton for the check to be sure, or just styling.
                Center(
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Checkbox(
                      value: task.isCompleted,
                      onChanged: (v) => onToggle(),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        task.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                          color: task.isCompleted ? theme.disabledColor : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (task.description != null && task.description!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          task.description!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (task.dueDate != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 12,
                              color: task.isOverdue && !task.isCompleted ? theme.colorScheme.error : theme.disabledColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              task.dueDateFormatted,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: task.isOverdue && !task.isCompleted ? theme.colorScheme.error : theme.disabledColor,
                                fontWeight: task.isOverdue && !task.isCompleted ? FontWeight.bold : null,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Delete/Actions
                Center(
                  child: IconButton(
                    icon: Icon(Icons.delete_outline, color: theme.colorScheme.error.withOpacity(0.7)),
                    onPressed: onDelete,
                    tooltip: 'Удалить',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
