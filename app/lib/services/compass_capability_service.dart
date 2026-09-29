import 'package:flutter/services.dart';

/// Native capability check kept separate from the compass event plugin.
///
/// Some Android devices emit a stationary pseudo-heading even when they have
/// no magnetometer. The UI must therefore verify the physical sensor before it
/// treats any heading as a real direction.
class CompassCapabilityService {
  static const MethodChannel _channel = MethodChannel(
    'kz.dauam/compass_capability',
  );

  static Future<bool?> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isCompassAvailable');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
