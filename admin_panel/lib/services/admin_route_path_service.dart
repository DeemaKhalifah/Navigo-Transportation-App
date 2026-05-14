import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class AdminRoutePathInfo {
  const AdminRoutePathInfo({
    required this.encodedPolyline,
    required this.decodedPoints,
    required this.distanceMeters,
    required this.distanceText,
    required this.etaMinutes,
    required this.etaText,
    required this.provider,
  });

  final String encodedPolyline;
  final List<LatLng> decodedPoints;
  final int distanceMeters;
  final String distanceText;
  final int etaMinutes;
  final String etaText;
  final String provider;
}

class AdminRoutePathService {
  AdminRoutePathService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _routePolylineFunctionUrl =
      'https://us-central1-navigo-c89a0.cloudfunctions.net/fetchRoutePolyline';

  Future<AdminRoutePathInfo> fetchRoutePathByCoordinates({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
  }) async {
    final start = LatLng(startLatitude, startLongitude);
    final end = LatLng(endLatitude, endLongitude);
    final uri = Uri.parse(_routePolylineFunctionUrl);
    final requestBody = {
      'startLatitude': startLatitude,
      'startLongitude': startLongitude,
      'endLatitude': endLatitude,
      'endLongitude': endLongitude,
    };

    debugPrint('[AdminRouteCreate] startLocation=${_fmt(start)}');
    debugPrint('[AdminRouteCreate] endLocation=${_fmt(end)}');
    debugPrint('[AdminRouteCreate] request URL=$uri');
    debugPrint('[AdminRouteCreate] request body=${jsonEncode(requestBody)}');

    http.Response response;
    try {
      response = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );
    } catch (e) {
      debugPrint('[AdminRouteCreate] fetchRoutePolyline request failed: $e');
      throw Exception(
        'Could not generate route polyline: could not reach fetchRoutePolyline. '
        'Deploy it from the main Navigo project folder with: '
        'firebase deploy --only functions:fetchRoutePolyline',
      );
    }

    debugPrint('[AdminRouteCreate] response status code=${response.statusCode}');
    debugPrint('[AdminRouteCreate] response body=${response.body}');

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw Exception('Could not generate route polyline: invalid function response');
    }

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Could not generate route polyline: invalid function response');
    }

    if (response.statusCode != 200 || decoded['success'] != true) {
      final details =
          (decoded['details'] ?? decoded['error'] ?? 'request failed').toString();
      throw Exception('Could not generate route polyline: $details');
    }

    final data = decoded['data'];
    if (data is! Map) {
      throw Exception('Could not generate route polyline: missing data');
    }

    final polyline = (data['polyline'] ?? '').toString().trim();
    debugPrint('[AdminRouteCreate] extracted polyline length=${polyline.length}');
    if (polyline.isEmpty) {
      throw Exception('Could not generate route polyline: missing polyline');
    }

    final decodedPoints = decodePolyline(polyline);
    debugPrint(
      '[AdminRouteCreate] decoded polyline points count=${decodedPoints.length}',
    );
    if (decodedPoints.length < 2) {
      throw Exception('Could not generate route polyline: invalid polyline');
    }

    final distanceMeters =
        (data['distanceMeters'] as num?)?.toInt() ?? _estimateMeters(start, end);
    final etaMinutes =
        (data['etaMinutes'] as num?)?.toInt() ??
        math.max(1, (_estimateSeconds(start, end) / 60).ceil());

    return AdminRoutePathInfo(
      encodedPolyline: polyline,
      decodedPoints: decodedPoints,
      distanceMeters: distanceMeters,
      distanceText: (data['distanceText'] ?? _formatDistance(distanceMeters))
          .toString(),
      etaMinutes: etaMinutes,
      etaText: (data['etaText'] ?? _formatEta(etaMinutes)).toString(),
      provider: (data['provider'] ?? 'fetchRoutePolyline').toString(),
    );
  }

  static List<LatLng> decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20 && index < encoded.length);
      lat += (result & 1) != 0 ? ~(result >> 1) : result >> 1;

      shift = 0;
      result = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20 && index < encoded.length);
      lng += (result & 1) != 0 ? ~(result >> 1) : result >> 1;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return points;
  }

  static int _estimateSeconds(LatLng start, LatLng end) {
    final meters = _estimateMeters(start, end);
    return math.max(60, (meters / 1000 / 35 * 3600).round());
  }

  static int _estimateMeters(LatLng start, LatLng end) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(end.latitude - start.latitude);
    final dLng = _toRadians(end.longitude - start.longitude);
    final lat1 = _toRadians(start.latitude);
    final lat2 = _toRadians(end.latitude);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return (earthRadius * c).round();
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  static String _formatEta(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (rest == 0) return '${hours}h';
    return '${hours}h ${rest}m';
  }

  static String _formatDistance(int meters) {
    if (meters < 1000) return '$meters m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  static String _fmt(LatLng point) =>
      '${point.latitude.toStringAsFixed(7)},${point.longitude.toStringAsFixed(7)}';
}
