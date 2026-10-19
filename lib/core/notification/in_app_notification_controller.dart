import 'package:flutter/material.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:toastification/toastification.dart';

part 'in_app_notification_controller.g.dart';

@Riverpod(keepAlive: true)
InAppNotificationController inAppNotificationController(Ref ref) {
  return InAppNotificationController();
}

enum NotificationType { info, error, success }

/// A button at the end of a toast, such as Undo. Pressing it also closes the toast.
typedef ToastAction = ({String label, VoidCallback onPressed});

class InAppNotificationController with AppLogger {
  ToastificationItem? _show(
    String message, {
    NotificationType type = NotificationType.info,
    Duration duration = const Duration(seconds: 3),
    bool replaceExisting = true,
    ToastAction? action,
  }) {
    // Notifications raised during bootstrap (before runApp) have no overlay to
    // attach to, and toastification throws when it cannot find one. Swallow
    // that so a notification can never abort startup or crash the app.
    try {
      if (replaceExisting) {
        toastification.dismissAll();
      }
      // toastification has no slot for a trailing button, so the action rides
      // in as the description row. Pressing it dismisses the toast, same as a
      // tap anywhere else on it.
      ToastificationItem? item;
      final content = action == null
          ? null
          : Builder(
              builder: (context) => Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () {
                    action.onPressed();
                    final shown = item;
                    if (shown != null) {
                      toastification.dismiss(shown, showRemoveAnimation: true);
                    }
                  },
                  child: Text(action.label),
                ),
              ),
            );
      item = toastification.show(
        title: Text(message),
        description: content,
        type: type._toastificationType,
        alignment: AlignmentDirectional.bottomCenter,
        margin: const EdgeInsets.only(bottom: 64 + 16, right: 16, left: 16),
        autoCloseDuration: action == null ? duration : duration + const Duration(seconds: 4),
        style: ToastificationStyle.fillColored,
        pauseOnHover: true,
        showProgressBar: false,
        dragToClose: true,
        closeOnClick: true,
        closeButtonShowType: CloseButtonShowType.onHover,
      );
      return item;
    } catch (e, stackTrace) {
      loggy.warning("failed to show notification, overlay may not be ready", e, stackTrace);
      return null;
    }
  }

  ToastificationItem? showErrorToast(String message) =>
      _show(message, type: NotificationType.error, duration: const Duration(seconds: 5));

  ToastificationItem? showSuccessToast(String message, {ToastAction? action}) =>
      _show(message, type: NotificationType.success, action: action);

  /// [replaceExisting] is false for toasts that belong to the same event and are
  /// meant to stack: dismissing the first to show the second would hide the first.
  ToastificationItem? showInfoToast(
    String message, {
    Duration duration = const Duration(seconds: 3),
    bool replaceExisting = true,
  }) => _show(message, duration: duration, replaceExisting: replaceExisting);
}

extension NotificationTypeX on NotificationType {
  ToastificationType get _toastificationType => switch (this) {
    NotificationType.success => ToastificationType.success,
    NotificationType.error => ToastificationType.error,
    NotificationType.info => ToastificationType.info,
  };
}
