/// Just Now - Widget Registry & GenUI Renderer
/// Implements the Server-Driven UI pattern from LLD Section 4.2.

import 'package:flutter/material.dart';
import '../widgets/info_card.dart';
import '../widgets/action_list.dart';
import '../widgets/map_view.dart';

/// Widget Registry: Maps component types to widget builders.
/// Key must match backend PascalCase type names exactly.
class WidgetRegistry {
  static final Map<String, Widget Function(Map<String, dynamic>)> _builders = {
    'InfoCard': (json) => InfoCardWidget(json: json),
    'ActionList': (json) => ActionListWidget(json: json),
    'MapView': (json) => MapViewWidget(json: json),
  };

  /// Build a widget from component JSON.
  /// Returns a fallback widget if type is unknown.
  static Widget build(Map<String, dynamic> componentJson) {
    final type = componentJson['type'] as String?;

    if (type == null) {
      return _buildFallback('Missing type field');
    }

    final builder = _builders[type];
    if (builder == null) {
      return _buildFallback('Unsupported component type: $type');
    }

    // Pass entire JSON to widget for internal field extraction
    return builder(componentJson);
  }

  /// Fallback widget for unknown or invalid components.
  static Widget _buildFallback(String message) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Fallback: $message',
              style: TextStyle(color: Colors.red.shade900),
            ),
          ),
        ],
      ),
    );
  }
}

/// GenUI Renderer: Renders a complete UI payload to a widget tree.
class GenUIRenderer {
  /// Render a list of components from UIPayload.
  static Widget render(List<Map<String, dynamic>> components) {
    if (components.isEmpty) {
      return const Center(
        child: Text('No components to display'),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: components.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: WidgetRegistry.build(components[index]),
        );
      },
    );
  }
}
