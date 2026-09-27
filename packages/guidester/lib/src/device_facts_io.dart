import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'device_facts.dart';

/// Everywhere but the web: the platform's own device info. Null on platforms
/// the dashboard has no column for.
///
/// Platform channels can hang rather than throw when no implementation is
/// registered, so every call is bounded by [timeout].
Future<DeviceFacts?> readDeviceFacts(Duration timeout) async {
  final plugin = DeviceInfoPlugin();
  if (defaultTargetPlatform == TargetPlatform.android) {
    final a = await plugin.androidInfo.timeout(timeout);
    return DeviceFacts(
      model: a.model,
      osVersion: 'Android ${a.version.release} (SDK ${a.version.sdkInt})',
      manufacturer: a.manufacturer,
      isPhysicalDevice: a.isPhysicalDevice,
    );
  }
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    final i = await plugin.iosInfo.timeout(timeout);
    return DeviceFacts(
      model: i.utsname.machine,
      osVersion: '${i.systemName} ${i.systemVersion}',
      manufacturer: 'Apple',
      isPhysicalDevice: i.isPhysicalDevice,
    );
  }
  return null;
}
