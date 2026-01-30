/// Just Now - MapView Widget
/// Real OpenStreetMap integration using flutter_map package.

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

    final lat = (center?['lat'] as num?)?.toDouble() ?? _defaultLat;
    final lng = (center?['lng'] as num?)?.toDouble() ?? _defaultLng;
    final centerLatLng = LatLng(lat, lng);

    // Build marker list from JSON data
    final markerWidgets = _buildMarkers(markers, centerLatLng);

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
                  // Markers layer
                  MarkerLayer(markers: markerWidgets),
                ],
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
    for (final markerJson in markersJson) {
      if (markerJson is Map<String, dynamic>) {
        final markerLat = (markerJson['lat'] as num?)?.toDouble();
        final markerLng = (markerJson['lng'] as num?)?.toDouble();
        final label = markerJson['label'] as String?;

        if (markerLat != null && markerLng != null) {
          markers.add(
            Marker(
              point: LatLng(markerLat, markerLng),
              width: 100,
              height: 50,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.place,
                    color: Colors.blue.shade700,
                    size: 30,
                  ),
                  if (label != null)
                    Container(
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
                        label,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
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
