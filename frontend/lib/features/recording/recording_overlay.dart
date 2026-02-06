import 'dart:ui';
import 'package:flutter/material.dart';
import '../../data/recording_service.dart';
import '../../app/routes.dart';

class RecordingOverlay extends StatefulWidget {
  final Widget child;

  const RecordingOverlay({super.key, required this.child});

  @override
  State<RecordingOverlay> createState() => _RecordingOverlayState();
}

class _RecordingOverlayState extends State<RecordingOverlay> {
  @override
  void initState() {
    super.initState();
    recordingService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    recordingService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
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
