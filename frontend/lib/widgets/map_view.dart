/// Just Now - MapView Widget
/// CRITICAL: Wrapped in SizedBox with screen-ratio height per LLD design notes.
/// For PoC: Uses a static map placeholder (no Google Maps API key required).

import 'package:flutter/material.dart';

class MapViewWidget extends StatelessWidget {
  final Map<String, dynamic> json;

  const MapViewWidget({super.key, required this.json});

  @override
  Widget build(BuildContext context) {
    final widgetId = json['widget_id'] as String? ?? 'unknown';
    final center = json['center'] as Map<String, dynamic>?;
    final zoom = (json['zoom'] as num?)?.toDouble() ?? 14.0;
    final markers = (json['markers'] as List<dynamic>?) ?? [];

    final lat = (center?['lat'] as num?)?.toDouble() ?? 0.0;
    final lng = (center?['lng'] as num?)?.toDouble() ?? 0.0;

    // CRITICAL: Calculate height based on screen ratio to avoid layout errors
    // Using 35% of screen height as per common map UI patterns
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
              // Map placeholder background
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.blue.shade100,
                      Colors.blue.shade50,
                      Colors.green.shade50,
                    ],
                  ),
                ),
                child: CustomPaint(
                  painter: _MapGridPainter(),
                  child: const SizedBox.expand(),
                ),
              ),
              // Center marker
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_on,
                      color: Colors.red.shade600,
                      size: 40,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        '${lat.toStringAsFixed(2)}, ${lng.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Marker indicators (if any)
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
              // Zoom level indicator
              Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.zoom_in, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'Zoom: ${zoom.toStringAsFixed(1)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
              // PoC indicator
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Map Preview (PoC)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom painter for map grid lines (PoC visual)
class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withOpacity(0.15)
      ..strokeWidth = 1;

    // Draw grid lines
    const spacing = 30.0;

    // Vertical lines
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Horizontal lines
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
