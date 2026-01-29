/// Just Now - ActionList Widget
/// Interactive list with deep link / API call actions.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ActionListWidget extends StatelessWidget {
  final Map<String, dynamic> json;

  const ActionListWidget({super.key, required this.json});

  @override
  Widget build(BuildContext context) {
    final widgetId = json['widget_id'] as String? ?? 'unknown';
    final title = json['title'] as String? ?? 'Actions';
    final items = (json['items'] as List<dynamic>?) ?? [];

    return Card(
      key: ValueKey(widgetId),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          // Item list
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: Colors.grey.shade200,
            ),
            itemBuilder: (context, index) {
              final item = items[index] as Map<String, dynamic>;
              return _ActionItemTile(item: item);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ActionItemTile extends StatelessWidget {
  final Map<String, dynamic> item;

  const _ActionItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final id = item['id'] as String? ?? '';
    final title = item['title'] as String? ?? 'Untitled';
    final subtitle = item['subtitle'] as String?;
    final action = item['action'] as Map<String, dynamic>?;

    return ListTile(
      key: ValueKey(id),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.directions_car,
          color: Colors.blue.shade600,
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 15,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            )
          : null,
      trailing: Icon(
        Icons.chevron_right,
        color: Colors.grey.shade400,
      ),
      onTap: () => _handleAction(context, action),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    Map<String, dynamic>? action,
  ) async {
    if (action == null) return;

    final type = action['type'] as String?;
    final url = action['url'] as String?;

    switch (type) {
      case 'deep_link':
        if (url != null) {
          await _launchDeepLink(context, url);
        }
        break;
      case 'api_call':
        // For demo: show a toast indicating API call would happen
        _showToast(context, 'API call triggered: ${action['payload']}');
        break;
      case 'toast':
        _showToast(context, url ?? 'Action completed');
        break;
      default:
        _showToast(context, 'Unknown action type: $type');
    }
  }

  Future<void> _launchDeepLink(BuildContext context, String url) async {
    final uri = Uri.parse(url);

    // Try to launch the deep link
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // App not installed - show fallback message
      if (context.mounted) {
        _showToast(
          context,
          'App not installed. Would open: $url',
        );
      }
    }
  }

  void _showToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
