import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/constants.dart';

/// Remote manifest (host on SMS portal — DNS already works).
/// Admin updates this file when publishing a new APK.
class AppUpdateInfo {
  AppUpdateInfo({
    required this.latestVersion,
    required this.latestBuild,
    required this.downloadUrl,
    this.message,
  });

  final String latestVersion;
  final int latestBuild;
  final String downloadUrl;
  final String? message;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      latestVersion: (json['latest_version'] ?? json['version'] ?? '').toString(),
      latestBuild: _parseInt(json['latest_build'] ?? json['build_number'] ?? json['build']),
      downloadUrl: (json['download_url'] ?? json['url'] ?? '').toString().trim(),
      message: json['message']?.toString(),
    );
  }

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

class AppUpdateService {
  AppUpdateService._();

  static const _dismissedBuildKey = 'app_update_dismissed_build';

  static Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      final uri = Uri.parse(ApiConstants.appUpdateManifestUrl);
      final res = await http.get(uri, headers: {'Accept': 'application/json'}).timeout(
        const Duration(seconds: 12),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return null;
      final remote = AppUpdateInfo.fromJson(Map<String, dynamic>.from(decoded));
      if (remote.latestBuild <= currentBuild || remote.downloadUrl.isEmpty) {
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getInt(_dismissedBuildKey) ?? 0;
      if (dismissed >= remote.latestBuild) {
        return null;
      }

      return remote;
    } catch (_) {
      return null;
    }
  }

  static Future<void> dismissForBuild(int build) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dismissedBuildKey, build);
  }
}
