// صفحهٔ تنظیمات — تمیز و مرتب به سبک اپ‌های مدرن:
// بخش‌های گروه‌بندی‌شده با سربرگ مشخص، هر تنظیم یک ردیف با برچسب و راهنمای
// کوتاه زیرش، فاصله‌های مناسب و کارت/جداکننده بین گروه‌ها.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../settings.dart';
import '../sync_crypto.dart';

class SettingsPage extends StatefulWidget {
  final AppSettings settings;
  final VoidCallback onSettingsChanged;
  final Future<String> Function() onSyncNow;
  final VoidCallback onDisconnectSync;
  final String lastSyncText;

  const SettingsPage({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    required this.onSyncNow,
    required this.onDisconnectSync,
    required this.lastSyncText,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _backendCtrl;
  late final TextEditingController _chatUrlCtrl;
  late final TextEditingController _chatModelCtrl;
  late final TextEditingController _chatKeyCtrl;
  late final TextEditingController _imgUrlCtrl;
  late final TextEditingController _imgModelCtrl;
  late final TextEditingController _imgKeyCtrl;
  late final TextEditingController _imgPatternCtrl;
  late final TextEditingController _vidUrlCtrl;
  late final TextEditingController _vidModelCtrl;
  late final TextEditingController _vidKeyCtrl;
  late final TextEditingController _vidDurationCtrl;
  late final TextEditingController _vidPatternCtrl;
  late final TextEditingController _syncCodeCtrl;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _backendCtrl = TextEditingController(text: s.backendUrl);
    _chatUrlCtrl = TextEditingController(text: s.chatProviderUrl);
    _chatModelCtrl = TextEditingController(text: s.chatModel);
    _chatKeyCtrl = TextEditingController(text: s.chatApiKey);
    _imgUrlCtrl = TextEditingController(text: s.imageProviderUrl);
    _imgModelCtrl = TextEditingController(text: s.imageModel);
    _imgKeyCtrl = TextEditingController(text: s.imageApiKey);
    _imgPatternCtrl = TextEditingController(text: s.imageUrlPattern);
    _vidUrlCtrl = TextEditingController(text: s.videoProviderUrl);
    _vidModelCtrl = TextEditingController(text: s.videoModel);
    _vidKeyCtrl = TextEditingController(text: s.videoApiKey);
    _vidDurationCtrl = TextEditingController(text: s.videoDuration);
    _vidPatternCtrl = TextEditingController(text: s.videoUrlPattern);
    _syncCodeCtrl = TextEditingController(text: s.syncCode);
  }

  @override
  void dispose() {
    for (final c in [
      _backendCtrl,
      _chatUrlCtrl,
      _chatModelCtrl,
      _chatKeyCtrl,
      _imgUrlCtrl,
      _imgModelCtrl,
      _imgKeyCtrl,
      _imgPatternCtrl,
      _vidUrlCtrl,
      _vidModelCtrl,
      _vidKeyCtrl,
      _vidDurationCtrl,
      _vidPatternCtrl,
      _syncCodeCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed() => widget.onSettingsChanged();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _SectionHeader('اتصال'),
          _SectionCard(children: [
            _FieldRow(
              label: 'آدرس بک‌اند',
              hint: 'آدرس دیپلوی Flask روی Vercel؛ مثل https://xxx.vercel.app',
              controller: _backendCtrl,
              keyboardType: TextInputType.url,
              onChanged: (v) {
                widget.settings.backendUrl = v;
                _changed();
              },
            ),
          ]),
          const _SectionHeader('مدل چت'),
          _SectionCard(children: [
            _FieldRow(
              label: 'آدرس پروایدر',
              hint: 'آدرس پایهٔ سازگار با OpenAI که پروایدر داده است',
              controller: _chatUrlCtrl,
              keyboardType: TextInputType.url,
              onChanged: (v) {
                widget.settings.chatProviderUrl = v;
                _changed();
              },
            ),
            const _RowDivider(),
            _FieldRow(
              label: 'مدل',
              hint: 'نام دقیق مدل را از پروایدر بگیر',
              controller: _chatModelCtrl,
              onChanged: (v) {
                widget.settings.chatModel = v;
                _changed();
              },
            ),
            const _RowDivider(),
            _FieldRow(
              label: 'کلید API',
              hint: 'کلید فقط روی همین گوشی ذخیره می‌شود',
              controller: _chatKeyCtrl,
              obscure: true,
              onChanged: (v) {
                widget.settings.chatApiKey = v;
                _changed();
              },
            ),
          ]),
          const _SectionHeader('تصویر'),
          _SectionCard(children: [
            _FieldRow(
              label: 'آدرس پروایدر',
              hint: 'آدرس پایهٔ پروایدر تصویر',
              controller: _imgUrlCtrl,
              keyboardType: TextInputType.url,
              onChanged: (v) {
                widget.settings.imageProviderUrl = v;
                _changed();
              },
            ),
            const _RowDivider(),
            _FieldRow(
              label: 'مدل',
              hint: 'نام مدل تصویر',
              controller: _imgModelCtrl,
              onChanged: (v) {
                widget.settings.imageModel = v;
                _changed();
              },
            ),
            const _RowDivider(),
            _FieldRow(
              label: 'کلید API',
              hint: 'در حالت «ساده GET» لازم نیست',
              controller: _imgKeyCtrl,
              obscure: true,
              onChanged: (v) {
                widget.settings.imageApiKey = v;
                _changed();
              },
            ),
            const _RowDivider(),
            _DropdownRow(
              label: 'نوع اندپوینت',
              hint: 'ویرایش عکس نیاز به پیوست عکس دارد',
              value: widget.settings.imageEndpointType,
              onChanged: (v) {
                if (v == null) return;
                setState(() => widget.settings.imageEndpointType = v);
                _changed();
              },
            ),
            const _RowDivider(),
            _FieldRow(
              label: 'الگوی URL',
              hint: 'فقط برای حالت ساده GET؛ مثل /prompt/{prompt}?model={model}',
              controller: _imgPatternCtrl,
              onChanged: (v) {
                widget.settings.imageUrlPattern = v;
                _changed();
              },
            ),
          ]),
          const _SectionHeader('ویدیو'),
          _SectionCard(children: [
            _FieldRow(
              label: 'آدرس پروایدر',
              hint: 'آدرس پایهٔ پروایدر ویدیو',
              controller: _vidUrlCtrl,
              keyboardType: TextInputType.url,
              onChanged: (v) {
                widget.settings.videoProviderUrl = v;
                _changed();
              },
            ),
            const _RowDivider(),
            _FieldRow(
              label: 'مدل',
              hint: 'نام مدل ویدیو',
              controller: _vidModelCtrl,
              onChanged: (v) {
                widget.settings.videoModel = v;
                _changed();
              },
            ),
            const _RowDivider(),
            _FieldRow(
              label: 'کلید API',
              hint: 'در صورت نیاز پروایدر',
              controller: _vidKeyCtrl,
              obscure: true,
              onChanged: (v) {
                widget.settings.videoApiKey = v;
                _changed();
              },
            ),
            const _RowDivider(),
            _FieldRow(
              label: 'مدت (ثانیه)',
              hint: 'مدت ویدیوی ساخته‌شده؛ مثل 4 یا 5',
              controller: _vidDurationCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) {
                widget.settings.videoDuration = v;
                _changed();
              },
            ),
            const _RowDivider(),
            _FieldRow(
              label: 'الگوی URL',
              hint: 'مثل /video/{prompt}?model={model}&duration={duration}&key={key}',
              controller: _vidPatternCtrl,
              onChanged: (v) {
                widget.settings.videoUrlPattern = v;
                _changed();
              },
            ),
          ]),
          const _SectionHeader('سینک'),
          _SectionCard(children: [
            _FieldRow(
              label: 'کد همگام‌سازی',
              hint: '۲۰ حرف؛ کد را هیچ‌وقت برای کسی نفرست — هرکس آن را داشته باشد گفت‌وگوها را می‌خواند',
              controller: _syncCodeCtrl,
              onChanged: (v) {
                widget.settings.syncCode = v;
                _changed();
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('ساختن کد جدید'),
                    onPressed: () {
                      final code = generateSyncCode();
                      _syncCodeCtrl.text = code;
                      widget.settings.syncCode = code;
                      _changed();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('کد جدید ساخته شد — آن را جایی امن نگه دار')),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    icon: _syncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: const Text('همگام‌سازی الآن'),
                    onPressed: _syncing
                        ? null
                        : () async {
                            setState(() => _syncing = true);
                            final msg = await widget.onSyncNow();
                            if (mounted) {
                              setState(() => _syncing = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(msg)));
                            }
                          },
                  ),
                ),
              ],
            ),
            if (widget.settings.syncCode.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.link_off),
                label: const Text('قطع اتصال سینک'),
                onPressed: () {
                  _syncCodeCtrl.clear();
                  widget.settings.syncCode = '';
                  _changed();
                  widget.onDisconnectSync();
                },
              ),
            ],
            if (widget.lastSyncText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                widget.lastSyncText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ]),
          const _SectionHeader('رفتار'),
          _SectionCard(children: [
            _SwitchRow(
              label: 'همگام‌سازی خودکار',
              hint: 'هنگام باز شدن اپ، اگر کد سینک ثبت شده باشد',
              value: widget.settings.autoSync,
              onChanged: (v) {
                setState(() => widget.settings.autoSync = v);
                _changed();
              },
            ),
          ]),
          const SizedBox(height: 16),
          Text(
            'کلیدها و آدرس‌ها فقط روی همین گوشی ذخیره می‌شوند و به هیچ سروری جز پروایدرِ انتخابیِ خودت فرستاده نمی‌شوند.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// سربرگِ بخش — متن کوچک با رنگ اصلی تم.
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

/// کارتِ یک بخش — همهٔ ردیف‌های بخش داخل یک کارت با فاصلهٔ یکسان.
class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 24);
  }
}

/// یک ردیفِ تنظیمِ متنی: برچسب + راهنمای کوتاه + فیلد ورودی.
class _FieldRow extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscure;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final void Function(String) onChanged;

  const _FieldRow({
    required this.label,
    required this.hint,
    required this.controller,
    this.obscure = false,
    this.keyboardType,
    this.inputFormatters,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 2),
          Text(
            hint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// ردیفِ انتخاب از لیست (نوع اندپوینت تصویر).
class _DropdownRow extends StatelessWidget {
  final String label;
  final String hint;
  final ImageEndpointType value;
  final void Function(ImageEndpointType?) onChanged;

  const _DropdownRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 2),
          Text(
            hint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<ImageEndpointType>(
            value: value,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            items: ImageEndpointType.values
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(t.label,
                          style: theme.textTheme.bodyMedium),
                    ))
                .toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// ردیفِ سوییچ (روشن/خاموش).
class _SwitchRow extends StatelessWidget {
  final String label;
  final String hint;
  final bool value;
  final void Function(bool) onChanged;

  const _SwitchRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
