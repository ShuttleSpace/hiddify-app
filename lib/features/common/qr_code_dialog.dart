import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrCodeDialog extends ConsumerWidget {
  const QrCodeDialog(this.data, {super.key, this.message, this.width = 268, this.backgroundColor = Colors.white});

  final String data;
  final String? message;
  final double width;
  final Color backgroundColor;

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final t = ref.read(translationsProvider).requireValue;
    try {
      final painter = QrPainter(
        data: data,
        version: QrVersions.auto,
        gapless: true,
        eyeStyle: const QrEyeStyle(color: Colors.black),
        dataModuleStyle: QrDataModuleStyle(color: backgroundColor),
      );
      final image = await painter.toImage(width);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null) return;
      final name = message ?? 'qr-${DateTime.now().toIso8601String()}';
      final path = await FilePicker.platform.saveFile(
        fileName: '$name.png',
        type: FileType.custom,
        allowedExtensions: ['png'],
        bytes: bytes,
      );
      if (path == null) return;
      final file = File(path.endsWith('.png') ? path : '$path.png');
      if (!await file.parent.exists()) await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } on Exception catch (e) {
      ref.read(inAppNotificationControllerProvider).showErrorToast(t.common.msg.qrCode.save.failure(error: e));
      return;
    }
    ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.qrCode.save.success);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: width,
            child: QrImageView(data: data, backgroundColor: backgroundColor),
          ),
          if (message != null)
            SizedBox(
              width: width,
              child: Material(
                color: theme.colorScheme.surface,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        message!,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: theme.colorScheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton.icon(
              onPressed: () => _save(context, ref),
              icon: const Icon(Icons.save_alt_rounded),
              label: Text(ref.watch(translationsProvider).requireValue.common.save),
            ),
          ),
        ],
      ),
    );
  }
}
