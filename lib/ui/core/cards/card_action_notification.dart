import 'package:flutter/widgets.dart';

/// Notification for custom actions emitted by native cards
class CardActionNotification extends Notification {
  final Map<String, dynamic> action;

  const CardActionNotification(this.action);
}
