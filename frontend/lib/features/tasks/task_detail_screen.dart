import 'package:flutter/material.dart';
import '../../models/task.dart';
import '../../data/api_client.dart';
import '../../data/notification_service.dart';
import '../../core/utils/error_handler.dart';

class TaskDetailScreen extends StatefulWidget {
  final String? taskId;

  const TaskDetailScreen({super.key, this.taskId});

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  bool _isLoading = false;
  DateTime? _dueDate;
  String _priority = 'medium';
  Task? _task;

  final List<String> _priorities = ['low', 'medium', 'high'];

  @override
  void initState() {
    super.initState();
    if (widget.taskId != null) {
      _loadTask();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadTask() async {
    setState(() => _isLoading = true);
    try {
      // Note: We need a getTask method in ApiClient if we want to load by ID specifically.
      // For now, let's assume we can get it from the list or add a getTask method.
      // I added getTask to ApiClient in previous steps? Let me check.
      // Actually, I added getCalendarEvent. Let me check if I added getTask.
      // Checking back... Yes, I added getTasks but not a singular getTask.
      // Wait, let me check the ApiClient implementation I just wrote.
      // I wrote: getTasks, createTask, updateTask, toggleTaskCompletion, deleteTask.
      // I'll use getTasks and filter or I should add getTask. 
      // Let's assume for simplicity we have it or I'll add it now.
      
      final tasks = await apiClient.getTasks();
      final task = tasks.firstWhere((t) => t.id == widget.taskId);
      
      if (mounted) {
        setState(() {
          _task = task;
          _titleController.text = task.title;
          _descriptionController.text = task.description ?? '';
          _dueDate = task.dueDate;
          _priority = task.priority;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: ${ErrorHandler.getMessage(e)}')),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      Task savedTask;
      if (_task == null) {
        // Create
        final newTask = Task(
          id: '', // Server assigns
          title: _titleController.text,
          description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
          dueDate: _dueDate,
          priority: _priority,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        savedTask = await apiClient.createTask(newTask);
      } else {
        // Update
        savedTask = await apiClient.updateTask(_task!.id, {
          'title': _titleController.text,
          'description': _descriptionController.text.isEmpty ? null : _descriptionController.text,
          'due_date': _dueDate?.toIso8601String(),
          'priority': _priority,
        });
      }

      // Schedule notification if due date is set
      if (savedTask.dueDate != null) {
        await notificationService.scheduleTaskReminder(savedTask);
      } else if (_task?.dueDate != null) {
        // If due date was removed, cancel reminder
        await notificationService.cancelTaskReminder(savedTask.id);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: ${ErrorHandler.getMessage(e)}')),
        );
      }
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date != null) {
      setState(() => _dueDate = date);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _task == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_task == null ? 'Новая задача' : 'Редактирование'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saveTask,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Что нужно сделать?',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => val?.isEmpty == true ? 'Введите название' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Описание (необязательно)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              const Text('Дедлайн', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today),
                label: Text(_dueDate == null
                    ? 'Выбрать дату'
                    : '${_dueDate!.day}.${_dueDate!.month}.${_dueDate!.year}'),
              ),
              if (_dueDate != null)
                TextButton(
                  onPressed: () => setState(() => _dueDate = null),
                  child: const Text('Удалить дедлайн', style: TextStyle(color: Colors.red)),
                ),
              const SizedBox(height: 24),
              const Text('Приоритет', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'low', label: Text('Низкий')),
                  ButtonSegment(value: 'medium', label: Text('Средний')),
                  ButtonSegment(value: 'high', label: Text('Высокий')),
                ],
                selected: {_priority},
                onSelectionChanged: (val) => setState(() => _priority = val.first),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
