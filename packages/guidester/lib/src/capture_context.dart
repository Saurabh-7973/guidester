import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app_build.dart';
import 'app_build_web.dart' if (dart.library.io) 'app_build_io.dart';
import 'device_facts.dart';
import 'device_facts_web.dart' if (dart.library.io) 'device_facts_io.dart';
import 'version.dart';

/// Everything a developer needs to reproduce a report without asking.
///
/// Three fields become real columns; the long tail goes into the `context`
/// jsonb so adding a field later never needs a migration.
class CaptureContext {
  const CaptureContext({
    required this.deviceModel,
    required this.osVersion,
    required this.appVersion,
    required this.extra,
  });

  final String? deviceModel;
  final String? osVersion;
  final String? appVersion;

  /// Everything else, shipped as `context`.
  final Map<String, dynamic> extra;

  static DeviceFacts? _cachedDevice;
  static AppBuild? _cachedPackage;

  /// Collect everything. Display and locale values are read from [context] at
  /// tap time, not at init, because text scale and brightness change while
  /// the app is running and are exactly what closes UI bug reports.
  static Future<CaptureContext> collect(
    BuildContext context, {
    List<String> routeStack = const [],
    int screenResolverLayer = 0,
    String sdkVersion = guidesterSdkVersion,
  }) async {
    // Read everything context-bound FIRST, synchronously. These values change
    // while the app runs — text scale, brightness, orientation — so they must
    // reflect the moment of the tap, and the context must not be touched after
    // an await.
    final media = MediaQuery.maybeOf(context);
    final view = View.maybeOf(context);
    final locale = _locale(context);

    final device = await _device();
    final package = await _package();

    final textScale =
        media == null ? null : media.textScaler.scale(14.0) / 14.0;

    return CaptureContext(
      deviceModel: device?.model,
      osVersion: device?.osVersion,
      appVersion: package?.version,
      extra: <String, dynamic>{
        'route_stack': routeStack,
        'screen_resolver': screenResolverLayer,
        'package_name': package?.packageName,
        'build_number': package?.buildNumber,
        'manufacturer': device?.manufacturer,
        'is_physical_device': device?.isPhysicalDevice,
        'screen_w': media?.size.width,
        'screen_h': media?.size.height,
        'device_pixel_ratio': view?.devicePixelRatio ?? media?.devicePixelRatio,
        'text_scale_factor': textScale,
        'platform_brightness': media?.platformBrightness.name,
        'orientation': media?.orientation.name,
        'locale': locale,
        'timezone_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
        'sdk_version': sdkVersion,
      }..removeWhere((_, v) => v == null),
    );
  }

  /// Device and build facts alone, with no [BuildContext] and nothing that
  /// changes while the app runs.
  ///
  /// The launch ping needs a device model and an OS version and cannot have a
  /// context: it fires as the overlay mounts, before anything has been tapped.
  /// Everything in [collect] that reads MediaQuery is deliberately absent —
  /// text scale and brightness describe a moment, and a launch is not one.
  static Future<CaptureContext> collectDevice() async {
    final device = await _device();
    final package = await _package();
    return CaptureContext(
      deviceModel: device?.model,
      osVersion: device?.osVersion,
      appVersion: package?.version,
      extra: const <String, dynamic>{},
    );
  }

  static String? _locale(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context) ??
        WidgetsBinding.instance.platformDispatcher.locale;
    return locale.toLanguageTag();
  }

  static const Duration _pluginTimeout = Duration(milliseconds: 800);

  static Future<AppBuild?> _package() async {
    if (_cachedPackage != null) return _cachedPackage;
    try {
      // Platform channels can hang rather than throw when no implementation
      // is registered. Bound every one of them.
      return _cachedPackage = await readAppBuild().timeout(_pluginTimeout);
    } catch (_) {
      return null;
    }
  }

  /// Cached after the first read. Returns nulls on unsupported platforms
  /// rather than throwing — a missing device model must never lose a comment.
  static Future<DeviceFacts?> _device() async {
    if (_cachedDevice != null) return _cachedDevice;
    try {
      return _cachedDevice = await readDeviceFacts(_pluginTimeout);
    } catch (_) {
      return null;
    }
  }

  static void debugReset() {
    _cachedDevice = null;
    _cachedPackage = null;
  }
}
