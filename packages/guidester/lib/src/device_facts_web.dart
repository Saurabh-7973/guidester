import 'dart:js_interop';

import 'device_facts.dart';

@JS('navigator.userAgent')
external String get _userAgent;

@JS('navigator.platform')
external String? get _platform;

@JS('navigator.vendor')
external String? get _vendor;

/// On the web, read straight from the browser. device_info_plus would bring
/// dart:io into web builds, which stops the package compiling to WebAssembly.
///
/// The model is the browser's name and the OS field is the platform
/// ("Web · MacIntel"), never the whole user-agent string, which reads as noise
/// on the dashboard.
Future<DeviceFacts?> readDeviceFacts(Duration timeout) async {
  final ua = _userAgent;
  final browser = ua.contains('Edg/')
      ? 'edge'
      : ua.contains('OPR/')
          ? 'opera'
          : ua.contains('Firefox/')
              ? 'firefox'
              : ua.contains('Chrome/')
                  ? 'chrome'
                  : ua.contains('Safari/')
                      ? 'safari'
                      : 'browser';
  final platform = _platform;
  return DeviceFacts(
    model: browser,
    osVersion:
        'Web${platform == null || platform.isEmpty ? '' : ' · $platform'}',
    manufacturer: _vendor,
    isPhysicalDevice: true,
  );
}
