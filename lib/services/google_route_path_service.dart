import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'schedule_slot_repository.dart';

class RoutePathInfo {
  const RoutePathInfo({
    required this.startLocation,
    required this.endLocation,
    required this.path,
    required this.etaMinutes,
    required this.etaText,
    required this.distanceMeters,
    required this.distanceText,
    required this.encodedPolyline,
    required this.provider,
  });

  final LatLng startLocation;
  final LatLng endLocation;
  final List<LatLng> path;
  final int etaMinutes;
  final String etaText;
  final int distanceMeters;
  final String distanceText;
  final String encodedPolyline;
  final String provider;

  double get distanceKm => distanceMeters / 1000;

  Map<String, dynamic> toRouteModuleMap() {
    return {
      'etaMinutes': etaMinutes,
      'etaText': etaText,
      'distanceMeters': distanceMeters,
      'distanceKm': distanceKm,
      'distanceText': distanceText,
      'provider': provider,
      'updatedAt': Timestamp.now(),
    };
  }

  Map<String, dynamic> toFirestoreRouteMap() {
    return {
      'startLocation': {
        'lat': startLocation.latitude,
        'lng': startLocation.longitude,
      },
      'endLocation': {
        'lat': endLocation.latitude,
        'lng': endLocation.longitude,
      },
      'routePolyline': encodedPolyline,
      'etaMinutes': etaMinutes,
      'etaText': etaText,
      'estimatedTime': etaMinutes,
      'distanceMeters': distanceMeters,
      'distanceKm': distanceKm,
      'distanceText': distanceText,
      'routeModule': toRouteModuleMap(),
      'routePathProvider': provider,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

class GoogleRoutePathService {
  GoogleRoutePathService({FirebaseFirestore? firestore, http.Client? client})
    : _db = firestore ?? FirebaseFirestore.instance,
      _client = client ?? http.Client();

  final FirebaseFirestore _db;
  final http.Client _client;
  static final Map<String, RoutePathInfo> _memoryCache = {};
  static final Map<String, Future<RoutePathInfo>> _inflight = {};

  static const String _apiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );
  static const LatLng _fixedStart = LatLng(31.903, 35.206);
  static const LatLng _fixedEnd = LatLng(31.9582684, 35.1801401);

  static String _coordsKey(LatLng start, LatLng end) =>
      '${start.latitude.toStringAsFixed(6)},${start.longitude.toStringAsFixed(6)}->${end.latitude.toStringAsFixed(6)},${end.longitude.toStringAsFixed(6)}';

  Future<RoutePathInfo> getOrFetchRoutePathForRoute({
    required String routeId,
    required String startPoint,
    required String endPoint,
    String? tripId,
  }) async {
    final safeRouteId = routeId.trim();
    final safeTripId = tripId?.trim() ?? '';
    final cacheKey = safeTripId.isEmpty
        ? 'route:$safeRouteId'
        : 'route:$safeRouteId:trip:$safeTripId';
    final cached = _memoryCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final inflight = _inflight[cacheKey];
    if (inflight != null) {
      return inflight;
    }

    final future = _resolveRoutePathForRoute(
      routeId: safeRouteId,
      startPoint: startPoint,
      endPoint: endPoint,
      cacheKey: cacheKey,
    );
    _inflight[cacheKey] = future;
    try {
      final resolved = await future;
      _memoryCache[cacheKey] = resolved;
      return resolved;
    } finally {
      _inflight.remove(cacheKey);
    }
  }

  Future<RoutePathInfo> _resolveRoutePathForRoute({
    required String routeId,
    required String startPoint,
    required String endPoint,
    required String cacheKey,
  }) async {
    if (routeId.isNotEmpty) {
      final doc = await _db.collection('route').doc(routeId).get();
      final data = doc.data();
      if (doc.exists && data != null) {
        final encoded = (data['routePolyline'] ?? '').toString().trim();
        if (encoded.isNotEmpty) {
          final start = _fixedStart;
          final end = _fixedEnd;
          debugPrint(
            '[Directions] using Firebase routePolyline routeId=$routeId',
          );
          final distanceMeters = (data['distanceMeters'] as num?)?.toInt() ??
              _estimateMeters(start, end);
          final etaMinutes = (data['etaMinutes'] as num?)?.toInt() ??
              math.max(1, (_estimateSeconds(start, end) / 60).ceil());
          final info = RoutePathInfo(
            startLocation: start,
            endLocation: end,
            path: decodePolyline(encoded),
            etaMinutes: etaMinutes,
            etaText: data['etaText']?.toString() ?? _formatEta(etaMinutes),
            distanceMeters: distanceMeters,
            distanceText: data['distanceText']?.toString() ??
                _formatDistance(distanceMeters),
            encodedPolyline: encoded,
            provider: 'firebase_cached',
          );
          _memoryCache[cacheKey] = info;
          return info;
        }
      }
    }

    debugPrint('[Directions] API call for routeId=$routeId');
    final info = await fetchRoutePath(startPoint: startPoint, endPoint: endPoint);
    if (routeId.isNotEmpty) {
      await saveRoutePath(routeId: routeId, info: info);
    }
    return info;
  }

  Future<RoutePathInfo> fetchRoutePath({
    required String startPoint,
    required String endPoint,
  }) async {
    return fetchRoutePathByCoordinates(start: _fixedStart, end: _fixedEnd);
  }

  Future<RoutePathInfo> fetchRoutePathByCoordinates({
    required LatLng start,
    required LatLng end,
  }) async {
    final fixedStart = _fixedStart;
    final fixedEnd = _fixedEnd;
    final key = 'coords:${_coordsKey(fixedStart, fixedEnd)}';
    final cached = _memoryCache[key];
    if (cached != null) return cached;

    final inflight = _inflight[key];
    if (inflight != null) return inflight;

    final future = _fetchRoutePathByCoordinatesInternal(
      start: fixedStart,
      end: fixedEnd,
    );
    _inflight[key] = future;
    try {
      final resolved = await future;
      _memoryCache[key] = resolved;
      return resolved;
    } finally {
      _inflight.remove(key);
    }
  }

  Future<RoutePathInfo> _fetchRoutePathByCoordinatesInternal({
    required LatLng start,
    required LatLng end,
  }) async {
    if (_apiKey.trim().isEmpty) {
      throw Exception(
        'Missing GOOGLE_MAPS_API_KEY. Pass it with --dart-define=GOOGLE_MAPS_API_KEY=YOUR_KEY',
      );
    }
    debugPrint('[Directions] API call for coordinates ${_coordsKey(start, end)}');

    final fromRoutesApi = await _fetchFromRoutesApi(start, end);
    if (fromRoutesApi != null) return fromRoutesApi;

    final fromDirectionsApi = await _fetchFromDirectionsApi(start, end);
    if (fromDirectionsApi != null) return fromDirectionsApi;

    final fromDistanceMatrix = await _fetchFromDistanceMatrix(start, end);
    if (fromDistanceMatrix != null) return fromDistanceMatrix;

    throw Exception('Could not calculate route ETA.');
  }

  Future<RoutePathInfo> syncRoutePathForRoute({
    required String routeId,
    required String startPoint,
    required String endPoint,
  }) async {
    final safeRouteId = routeId.trim();
    if (safeRouteId.isEmpty) {
      throw Exception('Route ID is missing.');
    }

    final info = await fetchRoutePath(
      startPoint: startPoint,
      endPoint: endPoint,
    );
    await saveRoutePath(routeId: safeRouteId, info: info);
    return info;
  }

  Future<void> saveRoutePath({
    required String routeId,
    required RoutePathInfo info,
  }) async {
    final routeRef = _db.collection('route').doc(routeId);

    await _db.runTransaction((txn) async {
      final snap = await txn.get(routeRef);
      if (!snap.exists) {
        throw Exception('Route not found.');
      }

      final data = snap.data() ?? {};
      final slots = ScheduleSlotRepository.parseSlotList(data['scheduleSlots']);
      final enrichedSlots = slots.map((slot) {
        final m = Map<String, dynamic>.from(slot);
        _applyRouteModuleToSlot(m, info);
        return m;
      }).toList();

      txn.update(routeRef, {
        ...info.toFirestoreRouteMap(),
        'scheduleSlots': enrichedSlots,
      });
    });
  }

  Future<RoutePathInfo?> _fetchFromRoutesApi(LatLng start, LatLng end) async {
    final uri = Uri.parse(
      'https://routes.googleapis.com/directions/v2:computeRoutes',
    );

    try {
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask':
              'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline',
        },
        body: jsonEncode({
          'origin': {
            'location': {
              'latLng': {
                'latitude': start.latitude,
                'longitude': start.longitude,
              },
            },
          },
          'destination': {
            'location': {
              'latLng': {'latitude': end.latitude, 'longitude': end.longitude},
            },
          },
          'travelMode': 'DRIVE',
          'routingPreference': 'TRAFFIC_AWARE',
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty) return null;

      final route = Map<String, dynamic>.from(routes.first as Map);
      final polyline = route['polyline'];
      final encoded = polyline is Map
          ? (polyline['encodedPolyline'] ?? '').toString()
          : '';
      final distance = (route['distanceMeters'] as num?)?.toInt() ?? 0;
      final seconds = _parseDurationSeconds(route['duration']);

      return _buildInfo(
        start: start,
        end: end,
        encodedPolyline: encoded,
        distanceMeters: distance,
        seconds: seconds,
        provider: 'google_routes',
      );
    } catch (_) {
      return null;
    }
  }

  Future<RoutePathInfo?> _fetchFromDirectionsApi(
    LatLng start,
    LatLng end,
  ) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
      'origin': '${start.latitude},${start.longitude}',
      'destination': '${end.latitude},${end.longitude}',
      'mode': 'driving',
      'departure_time': 'now',
      'key': _apiKey,
    });

    try {
      final response = await _client.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['status'] != 'OK') return null;

      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty) return null;
      final route = Map<String, dynamic>.from(routes.first as Map);
      final legs = route['legs'];
      if (legs is! List || legs.isEmpty) return null;

      final leg = Map<String, dynamic>.from(legs.first as Map);
      final durationMap = leg['duration_in_traffic'] ?? leg['duration'];
      final distanceMap = leg['distance'];
      final seconds = durationMap is Map
          ? (durationMap['value'] as num?)?.toInt()
          : null;
      final distance = distanceMap is Map
          ? (distanceMap['value'] as num?)?.toInt() ?? 0
          : 0;
      final overview = route['overview_polyline'];
      final encoded = overview is Map
          ? (overview['points'] ?? '').toString()
          : '';

      return _buildInfo(
        start: start,
        end: end,
        encodedPolyline: encoded,
        distanceMeters: distance,
        seconds: seconds,
        provider: 'google_directions',
      );
    } catch (_) {
      return null;
    }
  }

  Future<RoutePathInfo?> _fetchFromDistanceMatrix(
    LatLng start,
    LatLng end,
  ) async {
    final uri =
        Uri.https('maps.googleapis.com', '/maps/api/distancematrix/json', {
          'origins': '${start.latitude},${start.longitude}',
          'destinations': '${end.latitude},${end.longitude}',
          'mode': 'driving',
          'departure_time': 'now',
          'key': _apiKey,
        });

    try {
      final response = await _client.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['status'] != 'OK') return null;
      final rows = decoded['rows'];
      if (rows is! List || rows.isEmpty) return null;
      final elements = (rows.first as Map)['elements'];
      if (elements is! List || elements.isEmpty) return null;

      final element = Map<String, dynamic>.from(elements.first as Map);
      if (element['status'] != 'OK') return null;

      final durationMap = element['duration_in_traffic'] ?? element['duration'];
      final distanceMap = element['distance'];
      final seconds = durationMap is Map
          ? (durationMap['value'] as num?)?.toInt()
          : null;
      final distance = distanceMap is Map
          ? (distanceMap['value'] as num?)?.toInt() ?? 0
          : 0;

      return _buildInfo(
        start: start,
        end: end,
        encodedPolyline: '',
        distanceMeters: distance,
        seconds: seconds,
        provider: 'google_distance_matrix',
      );
    } catch (_) {
      return null;
    }
  }

  RoutePathInfo _buildInfo({
    required LatLng start,
    required LatLng end,
    required String encodedPolyline,
    required int distanceMeters,
    required int? seconds,
    required String provider,
  }) {
    final safeSeconds = seconds ?? _estimateSeconds(start, end);
    final etaMinutes = math.max(1, (safeSeconds / 60).ceil());
    final path = encodedPolyline.isEmpty
        ? [start, end]
        : _decodePolyline(encodedPolyline);

    return RoutePathInfo(
      startLocation: start,
      endLocation: end,
      path: path.isEmpty ? [start, end] : path,
      etaMinutes: etaMinutes,
      etaText: _formatEta(etaMinutes),
      distanceMeters: distanceMeters > 0
          ? distanceMeters
          : _estimateMeters(start, end),
      distanceText: _formatDistance(
        distanceMeters > 0 ? distanceMeters : _estimateMeters(start, end),
      ),
      encodedPolyline: encodedPolyline,
      provider: provider,
    );
  }

  static void _applyRouteModuleToSlot(
    Map<String, dynamic> slot,
    RoutePathInfo info,
  ) {
    final module = info.toRouteModuleMap();

    slot['etaMinutes'] = info.etaMinutes;
    slot['etaText'] = info.etaText;
    slot['distanceMeters'] = info.distanceMeters;
    slot['distanceKm'] = info.distanceKm;
    slot['distanceText'] = info.distanceText;
    slot['routePolyline'] = info.encodedPolyline;
    slot['routeModule'] = module;
    slot['estimatedArrivalAt'] = _estimatedArrival(slot, info.etaMinutes);
  }

  static Timestamp? _estimatedArrival(
    Map<String, dynamic> slot,
    int etaMinutes,
  ) {
    final rawDeparture = slot['departureAt'];
    DateTime? departure;
    if (rawDeparture is Timestamp) {
      departure = rawDeparture.toDate();
    } else if (rawDeparture is DateTime) {
      departure = rawDeparture;
    } else if (rawDeparture is String) {
      departure = DateTime.tryParse(rawDeparture);
    }

    if (departure == null) return null;
    return Timestamp.fromDate(departure.add(Duration(minutes: etaMinutes)));
  }

  static int? _parseDurationSeconds(dynamic raw) {
    if (raw is num) return raw.toInt();
    if (raw is String) {
      if (raw.endsWith('s')) {
        return int.tryParse(raw.substring(0, raw.length - 1));
      }
      return int.tryParse(raw);
    }
    return null;
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

  static List<LatLng> _decodePolyline(String encoded) => decodePolyline(encoded);
}
