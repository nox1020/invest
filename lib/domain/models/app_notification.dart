import 'package:invest/domain/services/notification_service.dart';

/// In-app notification inbox item (device-local history).
class AppNotification {
  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    required this.createdAt,
    this.read = false,
  });

  final String id;
  final String title;
  final String body;
  final NotificationKind kind;
  final DateTime createdAt;
  bool read;

  String get kindLabel => switch (kind) {
        NotificationKind.trades => 'معاملات',
        NotificationKind.withdrawals => 'برداشت',
        NotificationKind.prices => 'قیمت',
        NotificationKind.general => 'عمومی',
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'kind': kind.name,
        'created_at': createdAt.toIso8601String(),
        'read': read,
      };

  factory AppNotification.fromJson(Map<String, dynamic> m) {
    final kindName = '${m['kind'] ?? 'general'}';
    final kind = NotificationKind.values.firstWhere(
      (e) => e.name == kindName,
      orElse: () => NotificationKind.general,
    );
    return AppNotification(
      id: '${m['id'] ?? ''}',
      title: '${m['title'] ?? ''}',
      body: '${m['body'] ?? ''}',
      kind: kind,
      createdAt: DateTime.tryParse('${m['created_at'] ?? ''}') ?? DateTime.now(),
      read: m['read'] == true,
    );
  }
}
