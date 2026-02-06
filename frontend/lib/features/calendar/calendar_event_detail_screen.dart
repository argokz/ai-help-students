import 'package:flutter/material.dart';
import '../../models/calendar_event.dart';
import '../../data/api_client.dart';
import '../../data/notification_service.dart';
import '../../core/utils/error_handler.dart';

class CalendarEventDetailScreen extends StatefulWidget {
  final String? eventId;
  final DateTime? preselectedDate;

  const CalendarEventDetailScreen({
    super.key,
    this.eventId,
    this.preselectedDate,
  });

  @override
  State<CalendarEventDetailScreen> createState() => _CalendarEventDetailScreenState();
}

class _CalendarEventDetailScreenState extends State<CalendarEventDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();

  CalendarEvent? _event;
  bool _isLoading = false;

  DateTime? _startDate;
  TimeOfDay? _startTime;
  DateTime? _endDate;
  TimeOfDay? _endTime;
  DateTime? _remindAt;
  String _selectedColor = 'blue';

  final List<Map<String, dynamic>> _colors = [
    {'name': 'blue', 'color': Colors.blue, 'label': 'Синий'},
    {'name': 'red', 'color': Colors.red, 'label': 'Красный'},
    {'name': 'green', 'color': Colors.green, 'label': 'Зеленый'},
    {'name': 'orange', 'color': Colors.orange, 'label': 'Оранжевый'},
    {'name': 'purple', 'color': Colors.purple, 'label': 'Фиолетовый'},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.eventId != null) {
      _loadEvent();
    } else {
      // New event
      final date = widget.preselectedDate ?? DateTime.now();
      _startDate = date;
      _endDate = date;
      _startTime = TimeOfDay(hour: DateTime.now().hour + 1, minute: 0);
      _endTime = TimeOfDay(hour: DateTime.now().hour + 2, minute: 0);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _loadEvent() async {
    setState(() => _isLoading = true);
    try {
      final event = await apiClient.getCalendarEvent(widget.eventId!);
      if (mounted) {
        setState(() {
          _event = event;
          _titleController.text = event.title;
          _descriptionController.text = event.description ?? '';
          _locationController.text = event.location ?? '';
          _startDate = event.startTime;
          _startTime = TimeOfDay.fromDateTime(event.startTime);
          _endDate = event.endTime;
          _endTime = TimeOfDay.fromDateTime(event.endTime);
          _remindAt = event.remindAt;
          _selectedColor = event.color;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: ${ErrorHandler.getMessage(e)}')),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _saveEvent() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _startTime == null || _endDate == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заполните дату и время')),
      );
      return;
    }

    final startDateTime = DateTime(
      _startDate!.year,
      _startDate!.month,
      _startDate!.day,
      _startTime!.hour,
      _startTime!.minute,
    );

    final endDateTime = DateTime(
      _endDate!.year,
      _endDate!.month,
      _endDate!.day,
      _endTime!.hour,
      _endTime!.minute,
    );

    if (endDateTime.isBefore(startDateTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Время окончания должно быть позже начала')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      CalendarEvent savedEvent;
      if (_event == null) {
        // Create
        final newEvent = CalendarEvent(
          id: '', // Will be assigned by server
          title: _titleController.text,
          description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
          startTime: startDateTime,
          endTime: endDateTime,
          location: _locationController.text.isEmpty ? null : _locationController.text,
          remindAt: _remindAt,
          color: _selectedColor,
          createdAt: DateTime.now(),
        );
        savedEvent = await apiClient.createCalendarEvent(newEvent);
      } else {
        // Update
        savedEvent = await apiClient.updateCalendarEvent(_event!.id, {
          'title': _titleController.text,
          'description': _descriptionController.text.isEmpty ? null : _descriptionController.text,
          'start_time': startDateTime.toIso8601String(),
          'end_time': endDateTime.toIso8601String(),
          'location': _locationController.text.isEmpty ? null : _locationController.text,
          'remind_at': _remindAt?.toIso8601String(),
          'color': _selectedColor,
        });
      }

      // Schedule notification
      if (savedEvent.remindAt != null) {
        await notificationService.scheduleEventReminder(savedEvent);
      }
      // Also schedule a reminder 15 minutes before start
      await notificationService.scheduleEventStartReminder(savedEvent, minutesBefore: 15);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сохранено')),
        );
        Navigator.pop(context, true);
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

  Future<void> _deleteEvent() async {
    if (_event == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить событие?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Да')),
        ],
      ),
    );

    if (confirm == true) {
      await apiClient.deleteCalendarEvent(_event!.id);
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _pickDate(bool isStart) async {
    final date = await showDatePicker(
      context: context,
      initialDate: isStart ? (_startDate ?? DateTime.now()) : (_endDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (date != null) {
      setState(() {
        if (isStart) {
          _startDate = date;
        } else {
          _endDate = date;
        }
      });
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final time = await showTimePicker(
      context: context,
      initialTime: isStart ? (_startTime ?? TimeOfDay.now()) : (_endTime ?? TimeOfDay.now()),
    );
    if (time != null) {
      setState(() {
        if (isStart) {
          _startTime = time;
        } else {
          _endTime = time;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _event == null && widget.eventId != null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_event == null ? 'Новое событие' : 'Редактирование'),
        actions: [
          if (_event != null)
            IconButton(icon: const Icon(Icons.delete), onPressed: _deleteEvent),
          IconButton(icon: const Icon(Icons.check), onPressed: _saveEvent),
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
                  labelText: 'Название *',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => val?.isEmpty == true ? 'Обязательное поле' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Описание',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'Место',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Начало', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(true),
                      icon: const Icon(Icons.calendar_today),
                      label: Text(_startDate != null
                          ? '${_startDate!.day}.${_startDate!.month}.${_startDate!.year}'
                          : 'Выбрать дату'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickTime(true),
                      icon: const Icon(Icons.access_time),
                      label: Text(_startTime != null
                          ? '${_startTime!.hour}:${_startTime!.minute.toString().padLeft(2, '0')}'
                          : 'Выбрать время'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Окончание', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(false),
                      icon: const Icon(Icons.calendar_today),
                      label: Text(_endDate != null
                          ? '${_endDate!.day}.${_endDate!.month}.${_endDate!.year}'
                          : 'Выбрать дату'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickTime(false),
                      icon: const Icon(Icons.access_time),
                      label: Text(_endTime != null
                          ? '${_endTime!.hour}:${_endTime!.minute.toString().padLeft(2, '0')}'
                          : 'Выбрать время'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text('Цвет', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _colors.map((c) {
                  final isSelected = _selectedColor == c['name'];
                  return ChoiceChip(
                    label: Text(c['label']),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedColor = c['name']),
                    avatar: CircleAvatar(
                      backgroundColor: c['color'],
                      radius: 10,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              const Text('Напоминание', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _remindAt != null
                        ? Chip(
                            label: Text(
                              '${_remindAt!.day}.${_remindAt!.month} ${_remindAt!.hour}:${_remindAt!.minute.toString().padLeft(2, '0')}',
                            ),
                            onDeleted: () => setState(() => _remindAt = null),
                          )
                        : const Text('Не установлено'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _startDate ?? DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: _startDate ?? DateTime(2030),
                      );
                      if (date != null && mounted) {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );
                        if (time != null) {
                          setState(() {
                            _remindAt = DateTime(
                              date.year,
                              date.month,
                              date.day,
                              time.hour,
                              time.minute,
                            );
                          });
                        }
                      }
                    },
                    icon: const Icon(Icons.notifications),
                    label: const Text('Установить'),
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
