import 'dart:ui';
import 'package:flutter/material.dart';
import '../../data/recording_service.dart';
import '../../data/notification_service.dart';
import '../../app/routes.dart';

class RecordingOverlay extends StatefulWidget {
  final Widget child;

  const RecordingOverlay({super.key, required this.child});

  @override
  State<RecordingOverlay> createState() => _RecordingOverlayState();
}

class _RecordingOverlayState extends State<RecordingOverlay> {
  static const int _notificationId = 9999; // ID для уведомления записи
  
  @override
  void initState() {
    super.initState();
    recordingService.addListener(_onServiceUpdate);
    _updateNotification();
  }

  @override
  void dispose() {
    recordingService.removeListener(_onServiceUpdate);
    // Удаляем уведомление при закрытии overlay
    notificationService.notifications.cancel(_notificationId);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) {
      setState(() {});
      _updateNotification();
    }
  }

  Future<void> _updateNotification() async {
    if (!recordingService.isRecording) {
      await notificationService.notifications.cancel(_notificationId);
      return;
    }

    final duration = recordingService.duration;
    final durationText = _formatDuration(duration);
    
    await notificationService.notifications.show(
      _notificationId,
      'Идёт запись...',
      durationText,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'recording',
          'Запись лекции',
          channelDescription: 'Уведомление о записи в фоне',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          showWhen: false,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: false,
          presentBadge: false,
          presentSound: false,
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isRecording = recordingService.isRecording;
    
    // We only show the overlay if recording is active.
    // Ideally, we hide it if we are ON the recording screen, 
    // but the overlay wrapper is outside of navigator, so we can't easily check route.
    // However, if the user taps it, they go to the recording screen.
    // If they are already there, it's fine, buttons act the same.
    // Or we can just let it float. For better UX, let it float.
    
    return Stack(
      children: [
        widget.child,
        if (isRecording)
          Positioned(
            left: 16,
            right: 16,
            bottom: 32, // Above typical FAB location or near bottom
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(28),
              color: Colors.red,
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: () {
                   Navigator.of(context).pushNamed(AppRoutes.recording);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.mic, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Идёт запись...',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _formatDuration(recordingService.duration),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white.withOpacity(0.9),
                                fontFeatures: [const FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          if (recordingService.isPaused) {
                            recordingService.resumeRecording();
                          } else {
                            recordingService.pauseRecording();
                          }
                        },
                        icon: Icon(
                          recordingService.isPaused ? Icons.play_arrow : Icons.pause,
                          color: Colors.white,
                        ),
                        tooltip: recordingService.isPaused ? 'Возобновить' : 'Пауза',
                      ),
                      IconButton(
                        onPressed: () async {
                          // Останавливаем запись и сохраняем
                          final path = await recordingService.stopRecording();
                          if (path != null) {
                            // Запись уже сохранена автоматически в _stopRecording
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Запись сохранена'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.stop, color: Colors.white),
                        tooltip: 'Остановить и сохранить',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
