// صفحهٔ تنظیمات — تمیز و مرتب به سبک اپ‌های مدرن و مثل نسخهٔ وب:
// بخش‌های گروه‌بندی‌شده با سربرگ مشخص، هر تنظیم یک ردیف با برچسب و راهنمای
// کوتاه زیرش، فاصله‌های مناسب و کارت/جداکننده بین گروه‌ها.
// پروایدرها و کلیدها در رجیستری ثبت می‌شوند (مثل js/config.js نسخهٔ وب) و
// برای هر حالت فقط «کدام پروایدر|مدل» و «کدام کلید» انتخاب می‌شود.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../settings.dart';
import '../sync_crypto.dart';
import 'mode_selectors.dart';

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
  late final TextEditingController _provNameCtrl;
  late final TextEditingController _provUrlCtrl;
  late final TextEditingController _provModelsCtrl;
  late final TextEditingController _keyLabelCtrl;
  late final TextEditingController _keyValueCtrl;
  late final TextEditingController _editUrlCtrl;
  late final TextEditingController _imgPatternCtrl;
  late final TextEditingController _vidDurationCtrl;
  late final TextEditingController _vidPatternCtrl;
  late final TextEditingController _syncCodeCtrl;
  String? _editProviderId;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _backendCtrl = TextEditingController(text: s.backendUrl);
    _provNameCtrl = TextEditingController();
    _provUrlCtrl = TextEditingController();
    _provModelsCtrl = TextEditingController();
    _keyLabelCtrl = TextEditingController();
    _keyValueCtrl = TextEditingController();
    _editUrlCtrl = TextEditingController();
    _imgPatternCtrl = TextEditingController(text: s.imageUrlPattern);
    _vidDurationCtrl = TextEditingController(text: s.videoDuration);
    _vidPatternCtrl = TextEditingController(text: s.videoUrlPattern);
    _syncCodeCtrl = TextEditingController(text: s.syncCode);
  }

  @override
  void dispose() {
    for (final c in [
      _backendCtrl,
      _provNameCtrl,
      _provUrlCtrl,
      _provModelsCtrl,
      _keyLabelCtrl,
      _keyValueCtrl,
      _editUrlCtrl,
      _imgPatternCtrl,
      _vidDurationCtrl,
      _vidPatternCtrl,
      _syncCodeCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed() => widget.onSettingsChanged();

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _confirm(String title, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _addProvider() {
    final name = _provNameCtrl.text.trim();
    final url = _provUrlCtrl.text.trim();
    final models = _provModelsCtrl.text
        .split(',')
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .toList();
    if (name.isEmpty || url.isEmpty || models.isEmpty) {
      _snack('لطفاً نام پروایدر، آدرس و حداقل یک مدل را پر کن.');
      return;
    }
    if (!url.toLowerCase().startsWith('https://')) {
      _snack('آدرس پروایدر باید با https:// شروع شود.');
      return;
    }
    final entry = widget.settings.addProvider(name, url, models);
    _provNameCtrl.clear();
    _provUrlCtrl.clear();
    _provModelsCtrl.clear();
    _changed();
    setState(() {});
    _snack(models.length > 1
        ? '${models.length} مدل به «${entry.name}» اضافه شد.'
        : 'پروایدر «${entry.name}» اضافه شد.');
  }

  void _addApiKey() {
    final label = _keyLabelCtrl.text.trim();
    final key = _keyValueCtrl.text.trim();
    if (label.isEmpty || key.isEmpty) {
      _snack('لطفاً برچسب کلید و خود کلید را وارد کن.');
      return;
    }
    widget.settings.addApiKey(label, key);
    _keyLabelCtrl.clear();
    _keyValueCtrl.clear();
    _changed();
    setState(() {});
    _snack('کلید «$label» ثبت شد.');
  }

  Future<void> _deleteApiKey(ApiKeyEntry entry) async {
    final ok = await _confirm(
        'حذف کلید', 'کلید «${entry.label}» حذف شود؟');
    if (!ok) return;
    widget.settings.deleteApiKey(entry.key);
    _changed();
    setState(() {});
  }

  Future<void> _deleteModel(String providerId, String model) async {
    final ok = await _confirm('حذف مدل', 'مدل «$model» حذف شود؟');
    if (!ok) return;
    widget.settings.deleteModel(providerId, model);
    if (widget.settings.providerById(providerId) == null) {
      _editProviderId = null;
    }
    _changed();
    setState(() {});
  }

  Future<void> _deleteProvider(String providerId, String name) async {
    final ok = await _confirm('حذف پروایدر',
        'کل پروایدر «$name» به همراه همه‌ی مدل‌هایش حذف شود؟ این عمل قابل بازگشت نیست.');
    if (!ok) return;
    widget.settings.deleteProvider(providerId);
    if (_editProviderId == providerId) _editProviderId = null;
    _changed();
    setState(() {});
  }

  void _updateProviderUrl() {
    final id = _editProviderId;
    if (id == null) return;
    final ok = widget.settings.updateProviderUrl(id, _editUrlCtrl.text);
    if (!ok) {
      _snack('آدرس پروایدر باید با https:// شروع شود.');
      return;
    }
    _changed();
    setState(() {});
    _snack('آدرس پروایدر بروزرسانی شد.');
  }

  Future<void> _showExportDialog() async {
    final json = widget.settings.exportConfigJson();
    final ctrl = TextEditingController(text: json);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('پشتیبان پروایدرها و کلیدها'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: ctrl,
            readOnly: true,
            maxLines: 10,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('بستن'),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              _snack('کپی شد ✓');
            },
            child: const Text('کپی'),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }

  Future<void> _showImportDialog() async {
    final ctrl = TextEditingController();
    var failed = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('بازیابی پروایدرها و کلیدها'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ctrl,
                  maxLines: 10,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  decoration: const InputDecoration(
                    hintText: 'متن JSON پشتیبان را اینجا بچسبانید…',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (failed)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'ساختار فایل نامعتبر است.',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('لغو'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  widget.settings.importConfigJson(ctrl.text);
                } catch (_) {
                  setDialogState(() => failed = true);
                  return;
                }
                _changed();
                setState(() {});
                Navigator.of(ctx).pop();
                _snack('پروایدرها و کلیدها بازیابی شدند.');
              },
              child: const Text('بازیابی'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }

  String _maskedKey(String key) {
    if (key.length <= 8) return '••••••';
    return '••••${key.substring(key.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final editProvider = _editProviderId == null
        ? null
        : s.providerById(_editProviderId!);
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
          const _SectionHeader('ثبت پروایدر و مدل جدید'),
          _SectionCard(children: [
            _FieldRow(
              label: 'نام پروایدر',
              hint: 'مثلاً: OpenRouter',
              controller: _provNameCtrl,
              onChanged: (_) {},
            ),
            const _RowDivider(),
            _FieldRow(
              label: 'آدرس پایه (Base URL)',
              hint: 'مثلاً https://openrouter.ai/api/v1',
              controller: _provUrlCtrl,
              keyboardType: TextInputType.url,
              onChanged: (_) {},
            ),
            const _RowDivider(),
            _FieldRow(
              label: 'نام مدل',
              hint: 'چند مدل را با کاما جدا کن',
              controller: _provModelsCtrl,
              onChanged: (_) {},
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('افزودن پروایدر'),
              onPressed: _addProvider,
            ),
          ]),
          const _SectionHeader('ثبت و مدیریت کلیدهای API'),
          _SectionCard(children: [
            _FieldRow(
              label: 'برچسب کلید',
              hint: 'مثلاً: openrouter1',
              controller: _keyLabelCtrl,
              onChanged: (_) {},
            ),
            const _RowDivider(),
            _FieldRow(
              label: 'کلید API',
              hint: 'کلید فقط روی همین گوشی ذخیره می‌شود',
              controller: _keyValueCtrl,
              obscure: true,
              onChanged: (_) {},
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.key),
              label: const Text('ثبت کلید'),
              onPressed: _addApiKey,
            ),
            if (s.apiKeys.isNotEmpty) ...[
              const _RowDivider(),
              for (final entry in s.apiKeys)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.label,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium),
                            Text(
                              _maskedKey(entry.key),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                              textDirection: TextDirection.ltr,
                              textAlign: TextAlign.left,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'حذف کلید',
                        onPressed: () => _deleteApiKey(entry),
                      ),
                    ],
                  ),
                ),
            ],
          ]),
          const _SectionHeader('ویرایش / حذف پروایدر و مدل'),
          _SectionCard(children: [
            const _HintText(
                'یک پروایدرِ ثبت‌شده را انتخاب کن تا آدرسش را ویرایش کنی، مدل‌های تکی‌اش را حذف کنی، یا کل پروایدر را (با همه‌ی مدل‌هایش) یک‌جا پاک کنی.'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: editProvider == null ? null : _editProviderId,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              hint: const Text('-- انتخاب پروایدر --'),
              items: s.providers
                  .map((p) => DropdownMenuItem<String>(
                        value: p.id,
                        child: Text(p.name,
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _editProviderId = v;
                  final p = v == null ? null : s.providerById(v);
                  _editUrlCtrl.text = p?.baseUrl ?? '';
                });
              },
            ),
            if (editProvider != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _editUrlCtrl,
                      keyboardType: TextInputType.url,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _updateProviderUrl,
                    child: const Text('بروزرسانی آدرس'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const _HintText('مدل‌های ثبت‌شده:'),
              const SizedBox(height: 4),
              for (final model in editProvider.models)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          model,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.left,
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            _deleteModel(editProvider.id, model),
                        child: const Text('حذف'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('حذف کل این پروایدر'),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).colorScheme.error,
                  foregroundColor:
                      Theme.of(context).colorScheme.onError,
                ),
                onPressed: () =>
                    _deleteProvider(editProvider.id, editProvider.name),
              ),
            ],
          ]),
          const _SectionHeader('مدل چت'),
          _SectionCard(children: [
            _SelectRow(
              label: 'پروایدر / مدل',
              hint: 'از پروایدرهای ثبت‌شده انتخاب کن',
              child: ProviderModelDropdown(
                settings: s,
                value: s.chatProviderModel,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => s.chatProviderModel = v);
                  _changed();
                },
              ),
            ),
            const _RowDivider(),
            _SelectRow(
              label: 'کلید API',
              hint: 'از کلیدهای ثبت‌شده انتخاب کن',
              child: ApiKeyDropdown(
                settings: s,
                value: s.chatKey,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => s.chatKey = v);
                  _changed();
                },
              ),
            ),
          ]),
          const _SectionHeader('تصویر'),
          _SectionCard(children: [
            _SelectRow(
              label: 'پروایدر / مدل تصویر',
              hint: 'از پروایدرهای ثبت‌شده انتخاب کن',
              child: ProviderModelDropdown(
                settings: s,
                value: s.imageProviderModel,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => s.imageProviderModel = v);
                  _changed();
                },
              ),
            ),
            const _RowDivider(),
            _SelectRow(
              label: 'کلید API',
              hint: 'در حالت «ساده GET» لازم نیست',
              child: ApiKeyDropdown(
                settings: s,
                value: s.imageKey,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => s.imageKey = v);
                  _changed();
                },
              ),
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
            _SelectRow(
              label: 'پروایدر / مدل ویدیو',
              hint: 'از پروایدرهای ثبت‌شده انتخاب کن',
              child: ProviderModelDropdown(
                settings: s,
                value: s.videoProviderModel,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => s.videoProviderModel = v);
                  _changed();
                },
              ),
            ),
            const _RowDivider(),
            _SelectRow(
              label: 'کلید API',
              hint: 'در صورت نیاز پروایدر',
              child: ApiKeyDropdown(
                settings: s,
                value: s.videoKey,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => s.videoKey = v);
                  _changed();
                },
              ),
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
          const _SectionHeader('پشتیبان‌گیری از پروایدرها و کلیدها'),
          _SectionCard(children: [
            const _HintText(
                'کلیدهای API و پروایدرها فقط روی همین گوشی ذخیره می‌شوند. این بخش فقط همین‌ها را پشتیبان می‌گیرد — تاریخچه‌ی گفت‌وگوها را از منوی کناری صفحهٔ اصلی مدیریت کن.'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.upload, size: 18),
                    label: const Text('پشتیبان‌گیری'),
                    onPressed: _showExportDialog,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('بازیابی'),
                    onPressed: _showImportDialog,
                  ),
                ),
              ],
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
                            final messenger = ScaffoldMessenger.of(context);
                            setState(() => _syncing = true);
                            final msg = await widget.onSyncNow();
                            if (mounted) {
                              setState(() => _syncing = false);
                              messenger.showSnackBar(
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

/// متن راهنمای کوتاه داخل کارت.
class _HintText extends StatelessWidget {
  final String text;
  const _HintText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
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

/// یک ردیفِ انتخاب از لیست: برچسب + راهنما + ویجتِ انتخاب.
class _SelectRow extends StatelessWidget {
  final String label;
  final String hint;
  final Widget child;

  const _SelectRow({
    required this.label,
    required this.hint,
    required this.child,
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
          child,
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
