import 'dart:io';
import 'dart:convert';
import 'package:exif/exif.dart';
import 'package:http/http.dart' as http;
import 'package:memex/utils/logger.dart';
import 'package:intl/intl.dart';

/// EXIF data extraction and geocoding utilities
class ExifUtils {
  static final _logger = getLogger('ExifUtils');

  // simple in-memory cache to avoid repeated queries for same coordinates
  static final Map<String, String> _geocodeCache = {};

  /// Extract EXIF data from image file
  ///
  /// Returns map with:
  ///   - datetime_original: capture time (DateTime)
  ///   - datetime_original_str: capture time (string)
  ///   - gps_latitude: GPS latitude (double)
  ///   - gps_longitude: GPS longitude (double)
  ///   - gps_coordinates: [latitude, longitude]
  static Future<Map<String, dynamic>> extractExifData(String imagePath) async {
    final result = <String, dynamic>{};

    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        _logger.warning("File not found: $imagePath");
        return result;
      }

      final fileBytes = await file.readAsBytes();
      final data = await readExifFromBytes(fileBytes);

      if (data.isEmpty) {
        _logger.fine("No EXIF data found in $imagePath");
        return result;
      }

      // extract capture time
      DateTime? datetimeOriginal;
      String? datetimeOriginalStr;

      // try multiple possible field names
      const dateFields = [
        'Image DateTime',
        'EXIF DateTimeOriginal',
        'EXIF DateTimeDigitized'
      ];
      for (final fieldName in dateFields) {
        if (data.containsKey(fieldName)) {
          try {
            final dtTag = data[fieldName];
            final dtStr = dtTag?.printable;
            // EXIF date format is usually "YYYY:MM:DD HH:MM:SS"
            if (dtStr != null && dtStr.contains(':')) {
              // Note: DateFormat("yyyy:MM:dd HH:mm:ss") matches the standard EXIF format
              // but sometimes there are extra spaces or nulls, basic cleanup might be needed.
              // Taking the first 19 chars usually works for standard format.
              final cleanStr = dtStr.trim();
              if (cleanStr.length >= 19) {
                // Replace colons in date part with hyphens for standard ISO parsing if needed,
                // or just use specific format.
                // EXIF: 2023:12:30 14:00:00
                try {
                  final format = DateFormat("yyyy:MM:dd HH:mm:ss");
                  datetimeOriginal = format.parse(cleanStr.substring(0, 19));
                  datetimeOriginalStr = DateFormat("yyyy-MM-dd HH:mm:ss")
                      .format(datetimeOriginal);
                  break;
                } catch (e) {
                  _logger.fine("DateFormat parse failed for $cleanStr: $e");
                }
              }
            }
          } catch (e) {
            _logger.fine("Failed to parse datetime from $fieldName: $e");
            continue;
          }
        }
      }

      if (datetimeOriginal != null) {
        result['datetime_original'] = datetimeOriginal;
        result['datetime_original_str'] = datetimeOriginalStr;
      }

      // extract GPS info
      if (data.containsKey('GPS GPSLatitude') &&
          data.containsKey('GPS GPSLatitudeRef') &&
          data.containsKey('GPS GPSLongitude') &&
          data.containsKey('GPS GPSLongitudeRef')) {
        final latTag = data['GPS GPSLatitude'];
        final latRefTag = data['GPS GPSLatitudeRef'];
        final lonTag = data['GPS GPSLongitude'];
        final lonRefTag = data['GPS GPSLongitudeRef'];

        if (latTag != null &&
            latRefTag != null &&
            lonTag != null &&
            lonRefTag != null) {
          final latRef = latRefTag.printable.trim().toUpperCase();
          final lonRef = lonRefTag.printable.trim().toUpperCase();

          final lat = _convertToDegrees(latTag.values.toList());
          final lon = _convertToDegrees(lonTag.values.toList());

          if (lat != null && lon != null) {
            double latitude = lat;
            double longitude = lon;

            if (latRef == 'S') latitude = -latitude;
            if (lonRef == 'W') longitude = -longitude;

            // only save valid GPS coordinates
            if (latitude >= -90 &&
                latitude <= 90 &&
                longitude >= -180 &&
                longitude <= 180 &&
                !(latitude.abs() < 0.0001 && longitude.abs() < 0.0001)) {
              result['gps_latitude'] = latitude;
              result['gps_longitude'] = longitude;
              result['gps_coordinates'] = [latitude, longitude];
              _logger.info(
                  "Extracted GPS coordinates from $imagePath: ($latitude, $longitude)");
            }
          }
        }
      } else {
        _logger.fine("No GPS info found in $imagePath");
      }
    } catch (e) {
      _logger.severe("Failed to extract EXIF data from $imagePath: $e");
    }

    return result;
  }

  /// Convert EXIF GPS coordinates to decimal degrees
  static double? _convertToDegrees(List<dynamic> values) {
    if (values.length != 3) return null;

    try {
      double toDouble(dynamic value) {
        if (value is num) {
          return value.toDouble();
        }

        // Try to handle Ratio/IfdRational dynamically without importing the specific type
        try {
          // Check for numerator/denominator properties (common in Ratio classes)
          final val = value as dynamic;
          // Use noSuchMethod check implicitly via try-catch or just access
          final n = val.numerator;
          final d = val.denominator;
          if (n is num && d is num) {
            if (d == 0) return 0.0;
            return n / d;
          }
        } catch (_) {}

        // Try standard toDouble if available
        try {
          return (value as dynamic).toDouble();
        } catch (_) {}

        return 0.0;
      }

      final degrees = toDouble(values[0]);
      final minutes = toDouble(values[1]);
      final seconds = toDouble(values[2]);

      // all zeros treated as invalid
      if (degrees == 0 && minutes == 0 && seconds == 0) return null;

      return degrees + (minutes / 60.0) + (seconds / 3600.0);
    } catch (e) {
      _logger.warning("Error converting GPS coordinates: $e");
      return null;
    }
  }

  /// Convert GPS coordinates to address (reverse geocoding)
  /// Uses OpenStreetMap Nominatim API
  static Future<String?> reverseGeocode(double latitude, double longitude,
      {int timeoutSeconds = 10, bool useCache = true}) async {
    final cacheKey =
        "${latitude.toStringAsFixed(4)}_${longitude.toStringAsFixed(4)}";

    if (useCache && _geocodeCache.containsKey(cacheKey)) {
      _logger.fine("Using cached address for ($latitude, $longitude)");
      return _geocodeCache[cacheKey];
    }

    // OpenStreetMap Nominatim (free, no API key required)
    try {
      final uri = Uri.parse("https://nominatim.openstreetmap.org/reverse")
          .replace(queryParameters: {
        "lat": latitude.toString(),
        "lon": longitude.toString(),
        "format": "json",
        "accept-language": "zh",
      });

      // Nominatim requires User-Agent header
      final response = await http.get(uri, headers: {
        'User-Agent': 'memex_app'
      }).timeout(Duration(seconds: timeoutSeconds));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final address = data["display_name"] as String?;

        if (address != null && address.isNotEmpty) {
          if (useCache) {
            _geocodeCache[cacheKey] = address;
          }
          _logger.info(
              "Nominatim reverse geocoded ($latitude, $longitude) to: $address");
          return address;
        } else {
          _logger.warning(
              "No address found for coordinates ($latitude, $longitude) via Nominatim");
        }
      }
    } catch (e) {
      _logger.severe(
          "Failed to reverse geocode ($latitude, $longitude) via Nominatim: $e");
    }

    return null;
  }

  /// Format EXIF info as text
  static Future<String> formatExifInfo(Map<String, dynamic> exifData,
      {bool includeAddress = true}) async {
    final hasDatetime = exifData.containsKey('datetime_original_str');
    final hasGps = exifData.containsKey('gps_coordinates');

    if (!hasDatetime && !hasGps) return "";

    final buffer = StringBuffer();
    buffer.writeln("Image metadata:");

    if (hasDatetime) {
      buffer.writeln("- Capture time: ${exifData['datetime_original_str']}");
    }

    if (hasGps) {
      // gps_coordinates is [lat, lon]
      final coords = exifData['gps_coordinates'] as List;
      final lat = coords[0] as double;
      final lon = coords[1] as double;

      if (includeAddress) {
        final address = await reverseGeocode(lat, lon);
        if (address != null) {
          buffer.writeln("- Capture location: $address");
        } else {
          buffer.writeln("- Capture location: Address unavailable");
        }
      }
    }

    return buffer.toString().trim();
  }
}
