import 'package:flutter/material.dart';
import '../utils/error_handler.dart';

/// Mixin for StatefulWidgets to safely execute async operations
/// with built-in loading state management and error handling.
mixin SafeExecutionMixin<T extends StatefulWidget> on State<T> {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Executes an async operation [future] with safety guards.
  /// 
  /// - Automatically sets [isLoading] to true before execution and false after.
  /// - Catches exceptions and shows a SnackBar with the error message.
  /// - [onSuccess] is called if the operation completes successfully.
  /// - [onError] can be used for custom error handling.
  Future<void> safeExecute(
    Future<void> Function() action, {
    VoidCallback? onSuccess,
    void Function(Object error)? onError,
    bool showLoading = true,
  }) async {
    if (!mounted) return;

    if (showLoading) {
      setState(() => _isLoading = true);
    }

    try {
      await action();
      if (mounted && onSuccess != null) {
        onSuccess();
      }
    } catch (e) {
      if (mounted) {
        if (onError != null) {
          onError(e);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка: ${ErrorHandler.getMessage(e)}'),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } finally {
      if (mounted && showLoading) {
        setState(() => _isLoading = false);
      }
    }
  }
}
