import 'package:flutter/material.dart';
import '../../models/note.dart';
import '../../data/api_client.dart';
import '../../app/routes.dart';
import '../../core/layout/responsive.dart';
import '../../core/utils/error_handler.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<Note>? _notes;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final notes = await apiClient.getNotes();
      if (mounted) {
        setState(() {
          _notes = notes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ErrorHandler.getMessage(e);
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Заметки'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNotes,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // Navigate to create note
          final result = await Navigator.pushNamed(context, AppRoutes.noteDetail, arguments: null);
          if (result == true) {
            _loadNotes();
          }
        },
        child: const Icon(Icons.add),
      ),
      body: _buildBody(),
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
              onPressed: _loadNotes,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_notes == null || _notes!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.note_alt_outlined, size: 80, color: Theme.of(context).disabledColor),
            const SizedBox(height: 16),
            const Text('Нет заметок'),
            const SizedBox(height: 8),
            const Text('Нажмите +, чтобы создать'),
          ],
        ),
      );
    }
    
    final padding = Responsive.contentPadding(context);
    
    return ListView.builder(
      padding: EdgeInsets.all(padding),
      itemCount: _notes!.length,
      itemBuilder: (context, index) {
        final note = _notes![index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final result = await Navigator.pushNamed(context, AppRoutes.noteDetail, arguments: note.id);
              if (result == true) {
                _loadNotes();
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          note.titleDisplay,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (note.createdAt.difference(DateTime.now()).inDays == 0)
                        Text(
                          "${note.createdAt.hour}:${note.createdAt.minute.toString().padLeft(2, '0')}",
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (note.contentDisplay.isNotEmpty) ...[
                    Text(
                      note.contentDisplay,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      if (note.hasAudio) ...[
                        const Icon(Icons.mic, size: 16, color: Colors.blue),
                        const SizedBox(width: 4),
                        const Text('Аудио', style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 12),
                      ],
                      if (note.lectureId != null) ...[
                        const Icon(Icons.link, size: 16, color: Colors.orange),
                        const SizedBox(width: 4),
                        const Text('Привязано', style: TextStyle(fontSize: 12)),
                      ],
                       if (note.attachments.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        const Icon(Icons.attach_file, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text('${note.attachments.length}', style: const TextStyle(fontSize: 12)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
