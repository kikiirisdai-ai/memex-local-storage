class CharacterMemoryBlock {
  final String label;
  final String value;
  final String description;

  CharacterMemoryBlock({
    required this.label,
    required this.value,
    this.description = '',
  });

  factory CharacterMemoryBlock.fromJson(Map<String, dynamic> json) {
    return CharacterMemoryBlock(
      label: json['label'] as String? ?? 'unknown',
      value: json['value'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'value': value,
      'description': description,
    };
  }

  CharacterMemoryBlock copyWith({
    String? label,
    String? value,
    String? description,
  }) {
    return CharacterMemoryBlock(
      label: label ?? this.label,
      value: value ?? this.value,
      description: description ?? this.description,
    );
  }
}
