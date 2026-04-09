class ErrorLog {
  final String title;
  final String description;
  final DateTime createdAt;

  ErrorLog({
    required this.title,
    required this.description,
    required this.createdAt,
  });

  // Konversi ke Map untuk disimpan/dikirim
  Map<String, dynamic> toMap() => {
    'title': title,
    'description': description,
    'createdAt': createdAt.toIso8601String(),
  };

  // Buat ErrorLog dari Map (dari SharedPreferences)
  factory ErrorLog.fromMap(Map<String, dynamic> map) => ErrorLog(
    title: map['title'] as String,
    description: map['description'] as String,
    createdAt: DateTime.parse(map['createdAt'] as String),
  );

  @override
  String toString() => 'ErrorLog(title: $title, createdAt: $createdAt)';
}
