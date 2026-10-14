import 'package:geolocator/geolocator.dart';

/// A position captured from the device.
class DeviceCoordinates {
  const DeviceCoordinates({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

/// Why a location fix is unavailable, phrased for the owner rather than for a
/// developer. Phase 2 requires a manual fallback, so every failure mode here has
/// to be something the UI can offer a "type it instead" button against.
enum LocationUnavailable {
  /// The user declined the permission prompt, or it is permanently denied.
  permissionDenied,

  /// Location services are switched off device-wide.
  servicesDisabled,

  /// No fix yet, or the plugin is not available on this platform.
  unavailable,
}

/// Device location access.
///
/// Isolated behind an interface so the UI can be tested without a GPS, and so a
/// desktop or web build that cannot geolocate degrades to the manual address
/// entry the spec already requires, rather than blocking setup.
abstract class LocationService {
  Future<DeviceCoordinates?> current();

  /// Null when a position was returned, otherwise the reason it was not.
  Future<LocationUnavailable?> lastFailure();
}

class GeolocatorLocationService implements LocationService {
  LocationUnavailable? _lastFailure;

  @override
  Future<LocationUnavailable?> lastFailure() async => _lastFailure;

  @override
  Future<DeviceCoordinates?> current() async {
    _lastFailure = null;

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _lastFailure = LocationUnavailable.servicesDisabled;
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _lastFailure = LocationUnavailable.permissionDenied;
        return null;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return DeviceCoordinates(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } on Object {
      // A plugin that throws (unsupported platform, timeout) is a missing fix,
      // not a crash: the owner can still type the address.
      _lastFailure = LocationUnavailable.unavailable;
      return null;
    }
  }
}
