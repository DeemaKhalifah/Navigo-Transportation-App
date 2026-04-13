import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class GeocodingService {
  /// Reverse-geocode a [LatLng] into a human-readable area / street name.
  ///
  /// Falls back to `"lat, lng"` if geocoding fails or returns nothing useful.
  static Future<String> reverseGeocodeLabel(LatLng location) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );

      if (placemarks.isNotEmpty) {
        final p = placemarks.first;

        // Build parts: street, sub-locality, locality, country
        final parts = <String>[
          if (p.street != null && p.street!.isNotEmpty) p.street!,
          if (p.subLocality != null && p.subLocality!.isNotEmpty)
            p.subLocality!,
          if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
        ];

        if (parts.isNotEmpty) return parts.join(', ');
      }
    } catch (_) {
      // Geocoding failed – fall back to coordinates
    }

    return '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}';
  }

  /// Geocode a text address into a [LatLng].
  ///
  /// Returns `null` if geocoding fails.
  static Future<LatLng?> geocodeAddress(String address) async {
    if (address.trim().isEmpty) return null;

    try {
      final locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        return LatLng(locations.first.latitude, locations.first.longitude);
      }
    } catch (_) {
      // Geocoding failed
    }
    return null;
  }
}
