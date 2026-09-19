import 'dart:convert';

enum SyncRole { master, client }

enum SyncStatus { disconnected, connecting, syncing, connected, error }

class SyncChange {
  final int id;
  final String changeId;
  final String deviceId;
  final String entityType;
  final String entityId;
  final String operation;
  final Map<String, dynamic> payload;
  final String createdAt;

  const SyncChange({
    required this.id,
    required this.changeId,
    required this.deviceId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.createdAt,
  });

  factory SyncChange.fromMap(Map<String, dynamic> map) {
    final rawPayload = map['payload'];
    return SyncChange(
      id: (map['id'] as num?)?.toInt() ?? 0,
      changeId: map['change_id']?.toString() ?? '',
      deviceId: map['device_id']?.toString() ?? '',
      entityType: map['entity_type']?.toString() ?? '',
      entityId: map['entity_id']?.toString() ?? '',
      operation: map['operation']?.toString() ?? '',
      payload: rawPayload is String
          ? Map<String, dynamic>.from(jsonDecode(rawPayload) as Map)
          : Map<String, dynamic>.from((rawPayload as Map?) ?? const {}),
      createdAt: map['created_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'change_id': changeId,
        'device_id': deviceId,
        'entity_type': entityType,
        'entity_id': entityId,
        'operation': operation,
        'payload': payload,
        'created_at': createdAt,
      };
}
