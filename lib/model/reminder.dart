class Reminder {
  final int? id;
  final int recordId;
  final DateTime dueDate;
  final String text;
  final int status;
  final DateTime createdAt;
  final DateTime? completedAt;

  const Reminder({
    this.id,
    required this.recordId,
    required this.dueDate,
    required this.text,
    this.status = ReminderStatus.pending,
    required this.createdAt,
    this.completedAt,
  });

  bool get isPending => status == ReminderStatus.pending;

  bool get isCompleted => status == ReminderStatus.completed;

  bool get isCancelled => status == ReminderStatus.cancelled;

  bool get isDue {
    if (!isPending) return false;

    final now = DateTime.now();

    return !dueDate.isAfter(now);
  }

  Reminder copyWith({
    int? id,
    int? recordId,
    DateTime? dueDate,
    String? text,
    int? status,
    DateTime? createdAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    return Reminder(
      id: id ?? this.id,
      recordId: recordId ?? this.recordId,
      dueDate: dueDate ?? this.dueDate,
      text: text ?? this.text,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      completedAt: clearCompletedAt
          ? null
          : completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'record_id': recordId,
      'due_date': dueDate.toIso8601String(),
      'text': text,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
    };
  }

  factory Reminder.fromMap(Map<String, dynamic> map) {
    return Reminder(
      id: map['id'] as int?,
      recordId: map['record_id'] as int,
      dueDate: DateTime.parse(map['due_date'].toString()),
      text: map['text']?.toString() ?? '',
      status: (map['status'] as num?)?.toInt() ??
          ReminderStatus.pending,
      createdAt: DateTime.parse(
        map['created_at'].toString(),
      ),
      completedAt: map['completed_at'] == null
          ? null
          : DateTime.parse(
              map['completed_at'].toString(),
            ),
    );
  }
}

class ReminderStatus {
  ReminderStatus._();

  static const int pending = 0;
  static const int completed = 1;
  static const int cancelled = 2;
}