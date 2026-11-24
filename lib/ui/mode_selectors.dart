// دراپ‌داون‌های مشترکِ انتخاب پروایدر/مدل و کلید (مثل نسخهٔ وب):
// یکی در نوار بالای صفحهٔ اصلی و همان‌ها در بخش‌های تنظیمات استفاده می‌شوند.

import 'package:flutter/material.dart';

import '../settings.dart';

/// دراپ‌داونِ «پروایدر — مدل»: مقدار «providerId|model»، برچسب «نام (مدل)».
/// اگر مقدارِ ذخیره‌شده دیگر در لیست نباشد، چیزی انتخاب نمی‌شود.
class ProviderModelDropdown extends StatelessWidget {
  final AppSettings settings;
  final String? value;
  final void Function(String?) onChanged;
  final InputDecoration? decoration;
  final String? hintText;
  final bool dense;

  const ProviderModelDropdown({
    super.key,
    required this.settings,
    required this.value,
    required this.onChanged,
    this.decoration,
    this.hintText,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final options = settings.providerModelOptions;
    final effective = (value != null &&
            value!.isNotEmpty &&
            options.any((o) => o.value == value))
        ? value
        : null;
    return DropdownButtonFormField<String>(
      value: effective,
      isExpanded: true,
      isDense: dense,
      decoration: decoration ??
          const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
      hint: hintText != null
          ? Text(hintText!, overflow: TextOverflow.ellipsis)
          : null,
      items: options
          .map((o) => DropdownMenuItem<String>(
                value: o.value,
                child: Text(o.label, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }
}

/// دراپ‌داونِ کلید API: مقدار = خودِ کلید، برچسب = برچسبِ ثبت‌شده.
class ApiKeyDropdown extends StatelessWidget {
  final AppSettings settings;
  final String? value;
  final void Function(String?) onChanged;
  final InputDecoration? decoration;
  final String? hintText;
  final bool dense;

  const ApiKeyDropdown({
    super.key,
    required this.settings,
    required this.value,
    required this.onChanged,
    this.decoration,
    this.hintText,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final keys = settings.apiKeys;
    final effective = (value != null &&
            value!.isNotEmpty &&
            keys.any((k) => k.key == value))
        ? value
        : null;
    return DropdownButtonFormField<String>(
      value: effective,
      isExpanded: true,
      isDense: dense,
      decoration: decoration ??
          const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
      hint: hintText != null
          ? Text(hintText!, overflow: TextOverflow.ellipsis)
          : null,
      items: keys
          .map((k) => DropdownMenuItem<String>(
                value: k.key,
                child: Text(k.label, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }
}
