/// Just Now - InfoCard Widget
/// Displays content with Markdown rendering support.
/// Styles: standard, highlight, warning

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class InfoCardWidget extends StatelessWidget {
  final Map<String, dynamic> json;

  const InfoCardWidget({super.key, required this.json});

  @override
  Widget build(BuildContext context) {
    final widgetId = json['widget_id'] as String? ?? 'unknown';
    final title = json['title'] as String? ?? 'Untitled';
    final contentMd = json['content_md'] as String? ?? '';
    final style = json['style'] as String? ?? 'standard';

    // Style configuration based on type
    final styleConfig = _getStyleConfig(style);

    return Card(
      key: ValueKey(widgetId),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      color: styleConfig.backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: styleConfig.borderColor, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row with optional icon
            Row(
              children: [
                if (styleConfig.icon != null) ...[
                  Icon(styleConfig.icon, color: styleConfig.iconColor, size: 20),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: styleConfig.titleColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Markdown content
            MarkdownBody(
              data: contentMd,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(fontSize: 14, color: styleConfig.textColor),
                code: TextStyle(
                  backgroundColor: Colors.grey.shade200,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
                codeblockDecoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(8),
                ),
                codeblockPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _StyleConfig _getStyleConfig(String style) {
    switch (style) {
      case 'highlight':
        return _StyleConfig(
          backgroundColor: Colors.blue.shade50,
          borderColor: Colors.blue.shade200,
          titleColor: Colors.blue.shade900,
          textColor: Colors.blue.shade800,
          icon: Icons.lightbulb_outline,
          iconColor: Colors.blue.shade600,
        );
      case 'warning':
        return _StyleConfig(
          backgroundColor: Colors.orange.shade50,
          borderColor: Colors.orange.shade200,
          titleColor: Colors.orange.shade900,
          textColor: Colors.orange.shade800,
          icon: Icons.warning_amber_outlined,
          iconColor: Colors.orange.shade600,
        );
      case 'standard':
      default:
        return _StyleConfig(
          backgroundColor: Colors.white,
          borderColor: Colors.grey.shade200,
          titleColor: Colors.grey.shade900,
          textColor: Colors.grey.shade700,
          icon: null,
          iconColor: null,
        );
    }
  }
}

class _StyleConfig {
  final Color backgroundColor;
  final Color borderColor;
  final Color titleColor;
  final Color textColor;
  final IconData? icon;
  final Color? iconColor;

  _StyleConfig({
    required this.backgroundColor,
    required this.borderColor,
    required this.titleColor,
    required this.textColor,
    this.icon,
    this.iconColor,
  });
}
