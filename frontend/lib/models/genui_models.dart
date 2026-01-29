/// Just Now - GenUI Data Models
/// Mirrors backend Pydantic schemas for type-safe JSON parsing.

class LatLng {
  final double lat;
  final double lng;

  LatLng({required this.lat, required this.lng});

  factory LatLng.fromJson(Map<String, dynamic> json) {
    return LatLng(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
    );
  }
}

class Marker extends LatLng {
  final String? title;

  Marker({required double lat, required double lng, this.title})
      : super(lat: lat, lng: lng);

  factory Marker.fromJson(Map<String, dynamic> json) {
    return Marker(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      title: json['title'] as String?,
    );
  }
}

class ActionModel {
  final String type; // deep_link, api_call, toast
  final String? url;
  final Map<String, dynamic>? payload;

  ActionModel({required this.type, this.url, this.payload});

  factory ActionModel.fromJson(Map<String, dynamic> json) {
    return ActionModel(
      type: json['type'] as String,
      url: json['url'] as String?,
      payload: json['payload'] as Map<String, dynamic>?,
    );
  }
}

class ActionItem {
  final String id;
  final String title;
  final String? subtitle;
  final ActionModel action;

  ActionItem({
    required this.id,
    required this.title,
    this.subtitle,
    required this.action,
  });

  factory ActionItem.fromJson(Map<String, dynamic> json) {
    return ActionItem(
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String?,
      action: ActionModel.fromJson(json['action'] as Map<String, dynamic>),
    );
  }
}

class UIPayload {
  final List<Map<String, dynamic>> components;

  UIPayload({required this.components});

  factory UIPayload.fromJson(Map<String, dynamic> json) {
    final componentsList = json['components'] as List<dynamic>;
    return UIPayload(
      components: componentsList
          .map((c) => Map<String, dynamic>.from(c as Map))
          .toList(),
    );
  }
}

class GenUIResponse {
  final String intentId;
  final String category;
  final String uiSchemaVersion;
  final Map<String, dynamic> slots;
  final UIPayload uiPayload;

  GenUIResponse({
    required this.intentId,
    required this.category,
    required this.uiSchemaVersion,
    required this.slots,
    required this.uiPayload,
  });

  factory GenUIResponse.fromJson(Map<String, dynamic> json) {
    return GenUIResponse(
      intentId: json['intent_id'] as String,
      category: json['category'] as String? ?? 'SERVICE',
      uiSchemaVersion: json['ui_schema_version'] as String? ?? '1.0',
      slots: Map<String, dynamic>.from(json['slots'] as Map? ?? {}),
      uiPayload: UIPayload.fromJson(json['ui_payload'] as Map<String, dynamic>),
    );
  }
}
