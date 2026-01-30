/// Just Now - MapView Widget
/// Real OpenStreetMap integration using flutter_map package.
/// Now supports drawing route polylines for navigation.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapViewWidget extends StatelessWidget {
  final Map<String, dynamic> json;

  const MapViewWidget({super.key, required this.json});

  // Default location: Nanjing, China
  static const double _defaultLat = 32.0603;
  static const double _defaultLng = 118.7969;
  static const double _defaultZoom = 14.0;

  @override
  Widget build(BuildContext context) {
    final widgetId = json['widget_id'] as String? ?? 'unknown';
    final center = json['center'] as Map<String, dynamic>?;
    final zoom = (json['zoom'] as num?)?.toDouble() ?? _defaultZoom;
    final markers = (json['markers'] as List<dynamic>?) ?? [];
    final routePolyline = json['route_polyline'] as List<dynamic>?;

    final lat = (center?['lat'] as num?)?.toDouble() ?? _defaultLat;
    final lng = (center?['lng'] as num?)?.toDouble() ?? _defaultLng;
    final centerLatLng = LatLng(lat, lng);

    // Build marker list from JSON data
    final markerWidgets = _buildMarkers(markers, centerLatLng);

    // Build route polyline if available
    final polylinePoints = _buildPolylinePoints(routePolyline);

    // Calculate height based on screen ratio
    final screenHeight = MediaQuery.of(context).size.height;
    final mapHeight = screenHeight * 0.35;

    return Container(
      key: ValueKey(widgetId),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: mapHeight,
          width: double.infinity,
          child: Stack(
            children: [
              // Real FlutterMap with OpenStreetMap tiles
              FlutterMap(
                options: MapOptions(
                  initialCenter: centerLatLng,
                  initialZoom: zoom,
                  minZoom: 3,
                  maxZoom: 18,
                ),
                children: [
                  // OpenStreetMap tile layer
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.justnow.app',
                  ),
                  // Route polyline layer (drawn before markers so markers appear on top)
                  if (polylinePoints.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: polylinePoints,
                          color: Colors.blue.shade600,
                          strokeWidth: 4.0,
                          borderColor: Colors.blue.shade900,
                          borderStrokeWidth: 1.0,
                        ),
                      ],
                    ),
                  // Markers layer
                  MarkerLayer(markers: markerWidgets),
                ],
              ),
              // Route info badge (if route is present)
              if (polylinePoints.isNotEmpty)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade600,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.directions,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${polylinePoints.length} points',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Marker count indicator (if any)
              if (markers.isNotEmpty)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.place, size: 14, color: Colors.red.shade600),
                        const SizedBox(width: 4),
                        Text(
                          '${markers.length} marker${markers.length > 1 ? 's' : ''}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              // Attribution badge
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '© OpenStreetMap',
                    style: TextStyle(fontSize: 9, color: Colors.black54),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build polyline points from JSON data
  List<LatLng> _buildPolylinePoints(List<dynamic>? routePolyline) {
    if (routePolyline == null || routePolyline.isEmpty) {
      return [];
    }

    final points = <LatLng>[];

    for (final point in routePolyline) {
      if (point is List && point.length >= 2) {
        // Format: [lat, lng]
        final lat = (point[0] as num?)?.toDouble();
        final lng = (point[1] as num?)?.toDouble();
        if (lat != null && lng != null) {
          points.add(LatLng(lat, lng));
        }
      } else if (point is Map<String, dynamic>) {
        // Alternative format: {"lat": ..., "lng": ...}
        final lat = (point['lat'] as num?)?.toDouble();
        final lng = (point['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          points.add(LatLng(lat, lng));
        }
      }
    }

    return points;
  }

  /// Build markers from JSON data, always including center marker
  List<Marker> _buildMarkers(List<dynamic> markersJson, LatLng center) {
    final markers = <Marker>[];

    // Add center marker (user's destination or main location)
    markers.add(
      Marker(
        point: center,
        width: 40,
        height: 40,
        child: const Icon(
          Icons.location_on,
          color: Colors.red,
          size: 40,
        ),
      ),
    );

    // Add additional markers from JSON
    for (int i = 0; i < markersJson.length; i++) {
      final markerJson = markersJson[i];
      if (markerJson is Map<String, dynamic>) {
        final markerLat = (markerJson['lat'] as num?)?.toDouble();
        final markerLng = (markerJson['lng'] as num?)?.toDouble();
        final title = markerJson['title'] as String?;

        if (markerLat != null && markerLng != null) {
          // Check if this is the user's location marker (usually first in list with "我的位置" or "My Location")
          final isUserLocation = title != null &&
              (title.contains('我的位置') || title.toLowerCase().contains('my location'));

          markers.add(
            Marker(
              point: LatLng(markerLat, markerLng),
              width: 100,
              height: 60,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isUserLocation ? Colors.green : Colors.blue.shade700,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Icon(
                      isUserLocation ? Icons.my_location : Icons.place,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  if (title != null)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                      child: Text(
                        title.length > 12 ? '${title.substring(0, 12)}...' : title,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                          color: isUserLocation ? Colors.green.shade700 : Colors.blue.shade700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          );
        }
      }
    }

    return markers;
  }
}
