/// What the device says about itself: sent with every comment and the launch
/// ping. Any field may be null; a missing model must never lose a comment.
class DeviceFacts {
  const DeviceFacts({
    this.model,
    this.osVersion,
    this.manufacturer,
    this.isPhysicalDevice,
  });

  final String? model;
  final String? osVersion;
  final String? manufacturer;
  final bool? isPhysicalDevice;
}
