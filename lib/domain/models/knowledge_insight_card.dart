class KnowledgeInsightCard {
  final String id;
  final String? title;
  final String? insight;
  final String html;
  final int createdAt; // Unix timestamp
  final bool isPinned;
  final int sortOrder; // For manual sorting
  final List<String> tags; // For organization
  final List<String> relatedFactIds;
  final String widgetType; // 'html' or 'native'
  final String? widgetTemplate; // e.g., 'map_card'
  final Map<String, dynamic>? widgetData;

  KnowledgeInsightCard({
    required this.id,
    this.title,
    this.insight,
    required this.html,
    required this.createdAt,
    this.isPinned = false,
    this.sortOrder = 0,
    this.tags = const [],
    this.relatedFactIds = const [],
    this.widgetType = 'html',
    this.widgetTemplate,
    this.widgetData,
  });

  factory KnowledgeInsightCard.fromJson(Map<String, dynamic> json) {
    return KnowledgeInsightCard(
      id: json['id'] as String,
      title: json['title'] as String?,
      insight: json['insight'] as String?,
      html: json['html'] as String? ?? '',
      createdAt: json['created_at'] as int,
      isPinned: json['is_pinned'] as bool? ?? false,
      sortOrder: (json['sort_order'] as num? ?? 0).toInt(),
      tags: (json['tags'] as List?)?.cast<String>() ?? const [],
      relatedFactIds:
          (json['related_facts'] as List?)?.cast<String>() ?? const [],
      widgetType: json['widget_type'] as String? ?? 'html',
      widgetTemplate: json['widget_template'] as String?,
      widgetData: json['widget_data'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'insight': insight,
      'html': html,
      'created_at': createdAt,
      'is_pinned': isPinned,
      'sort_order': sortOrder,
      'tags': tags,
      'related_facts': relatedFactIds,
      'widget_type': widgetType,
      'widget_template': widgetTemplate,
      'widget_data': widgetData,
    };
  }

  KnowledgeInsightCard copyWith({
    String? id,
    String? title,
    String? insight,
    String? html,
    int? createdAt,
    bool? isPinned,
    int? sortOrder,
    List<String>? tags,
    List<String>? relatedFactIds,
    String? widgetType,
    String? widgetTemplate,
    Map<String, dynamic>? widgetData,
  }) {
    return KnowledgeInsightCard(
      id: id ?? this.id,
      title: title ?? this.title,
      insight: insight ?? this.insight,
      html: html ?? this.html,
      createdAt: createdAt ?? this.createdAt,
      isPinned: isPinned ?? this.isPinned,
      sortOrder: sortOrder ?? this.sortOrder,
      tags: tags ?? this.tags,
      relatedFactIds: relatedFactIds ?? this.relatedFactIds,
      widgetType: widgetType ?? this.widgetType,
      widgetTemplate: widgetTemplate ?? this.widgetTemplate,
      widgetData: widgetData ?? this.widgetData,
    );
  }

  Map<String, dynamic> get mergedWidgetData {
    final data = Map<String, dynamic>.from(widgetData ?? {});
    if (title != null) data['title'] = title;
    if (insight != null) data['insight'] = insight;
    if (relatedFactIds.isNotEmpty) data['related_fact_ids'] = relatedFactIds;
    if (tags.isNotEmpty) data['tags'] = tags;
    return data;
  }
}
