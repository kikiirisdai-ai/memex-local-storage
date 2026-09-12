/// Icon type for tags
enum TagIconType {
  svg, // Remote SVG URL
  emoji, // Emoji or character string
  flutter_icon, // Flutter built-in icon
}

/// Represents a tag with name and optional icon
class TagModel {
  final String name;
  final String? icon; // Icon identifier (remote SVG URL or emoji)
  final TagIconType? iconType; // Type of icon from API

  TagModel({
    required this.name,
    this.icon,
    this.iconType,
  });

  factory TagModel.fromJson(Map<String, dynamic> json) {
    final iconStr = json['icon'] as String?;
    TagIconType? iconType;

    if (json['icon_type'] != null) {
      final typeStr = json['icon_type'] as String;
      iconType = TagIconType.values.firstWhere(
        (e) => e.name == typeStr,
        orElse: () => TagIconType.emoji,
      );
    }

    return TagModel(
      name: json['name'] as String,
      icon: iconStr,
      iconType: iconType,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (icon != null) 'icon': icon,
      if (iconType != null) 'icon_type': iconType!.name,
    };
  }
}
