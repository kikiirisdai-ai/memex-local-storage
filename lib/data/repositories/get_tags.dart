import 'package:memex/domain/models/tag_model.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/data/services/file_system_service.dart';

final _logger = getLogger('GetTagsEndpoint');

/// Get all tags
/// Maps to backend GET /tags
Future<List<TagModel>> getTags() async {
  _logger.info('getTags called');

  try {
    final userId = await UserStorage.getUserId();
    if (userId == null) {
      _logger.warning('No user ID found, returning empty tags list');
      return [];
    }

    final fileSystemService = FileSystemService.instance;

    // Ensure tags file is initialized
    await fileSystemService.ensureTagsFileInitialized(userId);

    // Read tag definitions (name, icon, icon_type)
    final tagDefinitions = await fileSystemService.readTagsFile(userId);

    // Build TagModel list
    return tagDefinitions.map((tagDef) {
      final iconTypeStr = tagDef['icon_type'] as String? ?? 'emoji';
      TagIconType? iconType;
      if (iconTypeStr == 'svg') {
        iconType = TagIconType.svg;
      } else if (iconTypeStr == 'flutter_icon') {
        iconType = TagIconType.flutter_icon;
      } else {
        iconType = TagIconType.emoji;
      }

      return TagModel(
        name: tagDef['name'] as String,
        icon: tagDef['icon'] as String?,
        iconType: iconType,
      );
    }).toList();
  } catch (e) {
    _logger.severe('Failed to fetch tags: $e');
    return [];
  }
}
