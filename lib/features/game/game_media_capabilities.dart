import 'package:flutter/services.dart';
import '../../domain/game/game_models.dart';

abstract interface class GameMediaCapabilityReader {
  Future<Set<MediaCapability>> read();
}

/// The game describes media made with the device's camera application.
/// Query native capture support; a missing bridge/camera never grants a capability.
final class PlatformGameMediaCapabilities implements GameMediaCapabilityReader {
  const PlatformGameMediaCapabilities();
  static const channel = MethodChannel('couple_cards/media_capabilities');
  @override
  Future<Set<MediaCapability>> read() async {
    try {
      final values = await channel.invokeListMethod<String>(
        'captureCapabilities',
      );
      return {
        for (final capability in MediaCapability.values)
          if ((capability == MediaCapability.PHOTO_CAPTURE ||
                  capability == MediaCapability.RECORDED_VIDEO) &&
              values?.contains(capability.name) == true)
            capability,
      };
    } on MissingPluginException {
      return {};
    } on PlatformException {
      return {};
    }
  }
}
