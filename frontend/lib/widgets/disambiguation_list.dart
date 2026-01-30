/// Just Now - DisambiguationList Widget
/// Displays a list of locations for user to select when multiple matches found.

import 'package:flutter/material.dart';

class DisambiguationListWidget extends StatelessWidget {
  final Map<String, dynamic> json;

  const DisambiguationListWidget({super.key, required this.json});

  @override
  Widget build(BuildContext context) {
    final widgetId = json['widget_id'] as String? ?? 'unknown';
    final title = json['title'] as String? ?? 'Select Location';
    final message = json['message'] as String? ?? 'Multiple locations found. Please select:';
    final items = (json['items'] as List<dynamic>?) ?? [];

    return Container(
      key: ValueKey(widgetId),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.help_outline,
                        color: Colors.orange.shade700,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
            ),
            // Divider
            Divider(height: 1, color: Colors.grey.shade200),
            // Items list
            ...items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value as Map<String, dynamic>;
              final isLast = index == items.length - 1;
              return _buildItem(context, item, isLast);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, Map<String, dynamic> item, bool isLast) {
    final name = item['name'] as String? ?? 'Unknown';
    final address = item['address'] as String? ?? '';
    final lat = item['lat'] as num?;
    final lng = item['lng'] as num?;
    final distanceMeters = item['distance_meters'] as num?;

    // Format distance
    String distanceStr = '';
    if (distanceMeters != null) {
      if (distanceMeters < 1000) {
        distanceStr = '${distanceMeters.toInt()}m';
      } else {
        distanceStr = '${(distanceMeters / 1000).toStringAsFixed(1)}km';
      }
    }

    return InkWell(
      onTap: () {
        // Show confirmation and handle selection
        _handleSelection(context, name, lat, lng);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(color: Colors.grey.shade200),
                ),
        ),
        child: Row(
          children: [
            // Location icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.place,
                color: Colors.blue.shade600,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (address.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        address,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            // Distance badge
            if (distanceStr.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  distanceStr,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            // Arrow
            Icon(
              Icons.chevron_right,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  void _handleSelection(BuildContext context, String name, num? lat, num? lng) {
    // Show a snackbar with selection info
    // In a full implementation, this would trigger a new request with the selected location
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Selected: $name'),
        backgroundColor: Colors.blue.shade600,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Navigate',
          textColor: Colors.white,
          onPressed: () {
            // In a real app, this would re-submit the intent with the selected location
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Navigating to $name...'),
                backgroundColor: Colors.green.shade600,
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
      ),
    );
  }
}
