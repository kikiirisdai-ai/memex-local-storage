import 'timeline_card_model.dart';
import 'card_detail_model.dart';

class RelatedCardModel {
  final String id;
  final String? html; // HTML content for HTML cards, null for native cards
  final int createdAt;
  final List<UiConfig> uiConfigs;
  final String? title;
  final List<String> tags;
  final String status;
  final List<AssetData>? assets;
  final String? rawText;

  RelatedCardModel({
    required this.id,
    this.html,
    required this.createdAt,
    required this.uiConfigs,
    this.title,
    this.tags = const [],
    this.status = 'completed',
    this.assets,
    this.rawText,
  });

  factory RelatedCardModel.fromJson(Map<String, dynamic> json) {
    List<UiConfig> configs = [];
    if (json['ui_configs'] != null) {
      configs = (json['ui_configs'] as List)
          .map((e) => UiConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return RelatedCardModel(
      id: json['id'] as String? ?? '',
      html: json['html'] as String?,
      createdAt: json['created_at'] as int? ?? 0,
      uiConfigs: configs,
      title: json['title'] as String?,
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((tag) => tag.toString())
          .toList(),
      status: json['status'] as String? ?? 'completed',
      assets: (json['assets'] as List<dynamic>? ?? const [])
          .where((asset) => asset != null && asset is Map<String, dynamic>)
          .map((asset) => AssetData.fromJson(asset as Map<String, dynamic>))
          .toList(),
      rawText: json['raw_text'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (html != null) 'html': html,
      'created_at': createdAt,
      'ui_configs': uiConfigs.map((c) => c.toJson()).toList(),
      if (title != null) 'title': title,
      if (tags.isNotEmpty) 'tags': tags,
      'status': status,
      if (assets != null && assets!.isNotEmpty)
        'assets': assets!.map((a) => a.toJson()).toList(),
      if (rawText != null) 'raw_text': rawText,
    };
  }
}

class InsightMetadataModel {
  final String id;
  final String title;
  final String icon;
  final String type; // 'default' | 'alert' | etc.

  InsightMetadataModel({
    required this.id,
    required this.title,
    required this.icon,
    required this.type,
  });

  factory InsightMetadataModel.fromJson(Map<String, dynamic> json) {
    return InsightMetadataModel(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      type: json['type'] as String? ?? 'default',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'icon': icon,
      'type': type,
    };
  }
}

class InsightDetailModel {
  final InsightMetadataModel insight;
  final String content;
  final String analysis; // HTML content
  final List<RelatedCardModel> relatedCards;
  final String? widgetType;
  final String? widgetTemplate;
  final Map<String, dynamic>? widgetData;

  InsightDetailModel({
    required this.insight,
    required this.content,
    required this.analysis,
    required this.relatedCards,
    this.widgetType,
    this.widgetTemplate,
    this.widgetData,
  });

  factory InsightDetailModel.fromJson(Map<String, dynamic> json) {
    final insightJson =
        json['insight'] != null && json['insight'] is Map<String, dynamic>
            ? json['insight'] as Map<String, dynamic>
            : <String, dynamic>{};
    final relatedCardsJson = json['related_cards'] as List<dynamic>? ?? [];

    return InsightDetailModel(
      insight: InsightMetadataModel.fromJson(insightJson),
      content: json['content'] as String? ?? '',
      analysis: json['analysis'] as String? ?? '',
      relatedCards: relatedCardsJson
          .where((item) => item != null && item is Map<String, dynamic>)
          .map(
              (item) => RelatedCardModel.fromJson(item as Map<String, dynamic>))
          .toList(),
      widgetType: json['widget_type'] as String?,
      widgetTemplate: json['widget_template'] as String?,
      widgetData: json['widget_data'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'insight': insight.toJson(),
      'content': content,
      'analysis': analysis,
      'related_cards': relatedCards.map((c) => c.toJson()).toList(),
      if (widgetType != null) 'widget_type': widgetType,
      if (widgetTemplate != null) 'widget_template': widgetTemplate,
      if (widgetData != null) 'widget_data': widgetData,
    };
  }
}
