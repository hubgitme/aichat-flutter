// نمایش بلوک کد در پیام‌های مارک‌داون — با دکمهٔ کپی و دانلود، و جمع‌شدنِ
// خودکارِ کدهای طولانی (همان رفتار نسخهٔ وب: ۱۲۰۰ کاراکتر یا ۳۰ خط).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../app_theme.dart';
import '../downloads.dart';
import '../utils.dart';

/// سازندهٔ سفارشی برای تگ `pre` در flutter_markdown.
class CodeBlockBuilder extends MarkdownElementBuilder {
  final void Function(String message) onNotice;

  CodeBlockBuilder({required this.onNotice});

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    var language = '';
    for (final child in element.children ?? <md.Node>[]) {
      if (child is md.Element && child.tag == 'code') {
        final cls = child.attributes['class'] ?? '';
        if (cls.startsWith('language-')) {
          language = cls.substring('language-'.length);
        }
        break;
      }
    }
    final code = element.textContent;
    return CodeBlockCard(
      code: code,
      language: language,
      onNotice: onNotice,
    );
  }
}

/// کارتِ بلوک کد: سربرگ (زبان + کپی + دانلود + باز/جمع‌کردن) و بدنهٔ کد.
class CodeBlockCard extends StatefulWidget {
  final String code;
  final String language;
  final void Function(String message) onNotice;

  const CodeBlockCard({
    super.key,
    required this.code,
    required this.language,
    required this.onNotice,
  });

  @override
  State<CodeBlockCard> createState() => _CodeBlockCardState();
}

class _CodeBlockCardState extends State<CodeBlockCard> {
  late bool _collapsed;

  @override
  void initState() {
    super.initState();
    _collapsed = isLongCode(widget.code);
  }

  int get _lineCount => '\n'.allMatches(widget.code).length + 1;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    widget.onNotice('کپی شد ✓');
  }

  Future<void> _download() async {
    try {
      final result = await saveTextToDownloads(
        text: widget.code,
        filename: filenameForLang(widget.language),
      );
      widget.onNotice(result.isPublic
          ? 'در پوشهٔ Downloads ذخیره شد: ${result.displayPath}'
          : 'ذخیره شد: ${result.displayPath}');
    } catch (e) {
      widget.onNotice('خطا در ذخیرهٔ فایل: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final codeStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      color: theme.colorScheme.onSurface,
      height: 1.5,
    );
    final codeText = SelectableText(
      widget.code,
      style: codeStyle,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    );
    final body = _collapsed
        ? SizedBox(
            height: 168,
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: codeText,
            ),
          )
        : codeText;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: codeToolbarBackground(theme.brightness),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Text(
                  widget.language.isEmpty
                      ? 'code'
                      : widget.language,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$_lineCount خط • ${widget.code.length} کاراکتر',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'کپی',
                  onPressed: _copy,
                ),
                IconButton(
                  icon: const Icon(Icons.download, size: 18),
                  tooltip: 'دانلود فایل',
                  onPressed: _download,
                ),
                if (isLongCode(widget.code))
                  TextButton(
                    onPressed: () =>
                        setState(() => _collapsed = !_collapsed),
                    child: Text(_collapsed ? 'نمایش کامل' : 'جمع کردن'),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            color: codeBlockBackground(theme.brightness),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}
