import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/session.dart';
import '../core/theme.dart';

// ---------------------------------------------------------------- awning

/// The red-and-white striped market-stall awning used across DigiStall.
class Awning extends StatelessWidget {
  const Awning({super.key, this.height = 14, this.stripe = 20, this.scallop = 0, this.radius = 0});

  final double height;
  final double stripe;

  /// Height of the scalloped edge hanging below the stripes (0 for none).
  final double scallop;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
      child: SizedBox(
        height: height + scallop,
        width: double.infinity,
        child: CustomPaint(painter: _AwningPainter(height, stripe, scallop)),
      ),
    );
  }
}

class _AwningPainter extends CustomPainter {
  _AwningPainter(this.h, this.stripe, this.scallop);
  final double h, stripe, scallop;

  @override
  void paint(Canvas canvas, Size size) {
    final red = Paint()..color = DS.awning;
    final white = Paint()..color = Colors.white;
    var i = 0;
    for (double x = 0; x < size.width; x += stripe, i++) {
      final p = i.isEven ? red : white;
      canvas.drawRect(Rect.fromLTWH(x, 0, stripe, h), p);
      if (scallop > 0) {
        canvas.drawArc(Rect.fromLTWH(x, h - scallop, stripe, scallop * 2), 0, 3.14159, true, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AwningPainter old) => old.h != h || old.stripe != stripe || old.scallop != scallop;
}

/// "DS" mark with a tiny awning, followed by the DigiStall wordmark.
class DsLogo extends StatelessWidget {
  const DsLogo({super.key, this.light = false, this.size = 24});
  final bool light;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: size * 1.55,
        height: size * 1.55,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * 0.42),
          border: light ? null : Border.all(color: DS.ink, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          Positioned(top: 0, left: 0, right: 0, child: Awning(height: size * 0.36, stripe: size * 0.25)),
          Center(child: Padding(padding: EdgeInsets.only(top: size * 0.3), child: Text('DS', style: DS.h(size * 0.6, color: DS.teal)))),
        ]),
      ),
      SizedBox(width: size * 0.42),
      Text('DigiStall', style: DS.h(size, color: light ? Colors.white : DS.ink)),
    ]);
  }
}

// --------------------------------------------------------------- buttons

enum DsVariant { primary, sun, ghost, lite, danger, soft }

/// Chunky pressable button with the hard bottom shadow from the website.
class DsButton extends StatefulWidget {
  const DsButton({
    super.key,
    required this.label,
    required this.onTap,
    this.variant = DsVariant.primary,
    this.icon,
    this.small = false,
    this.block = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onTap;
  final DsVariant variant;
  final IconData? icon;
  final bool small;
  final bool block;
  final bool loading;

  @override
  State<DsButton> createState() => _DsButtonState();
}

class _DsButtonState extends State<DsButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null && !widget.loading;
    final (bg, fg, shadow, border) = switch (widget.variant) {
      DsVariant.primary => (DS.ink, Colors.white, DS.inkShadow, null),
      DsVariant.sun => (DS.marigold, DS.ink, DS.marigoldShadow, null),
      DsVariant.ghost => (Colors.white, DS.ink, null, DS.ink),
      DsVariant.lite => (Colors.white.withValues(alpha: 0.14), Colors.white, null, null),
      DsVariant.danger => (const Color(0xFFFFF0F0), DS.red, null, const Color(0xFFFFCDD2)),
      DsVariant.soft => (DS.tealSoft, DS.teal, null, null),
    };
    final hasShadow = shadow != null;
    final press = hasShadow && _down ? 3.0 : 0.0;
    final pad = widget.small ? const EdgeInsets.symmetric(horizontal: 14, vertical: 9) : const EdgeInsets.symmetric(horizontal: 20, vertical: 13);
    final radius = widget.small ? 11.0 : 14.0;
    final fontSize = widget.small ? 14.5 : 16.0;

    Widget content = Row(
      mainAxisSize: widget.block ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          SizedBox(width: fontSize, height: fontSize, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
        else if (widget.icon != null)
          Icon(widget.icon, size: fontSize + 3, color: fg),
        if (widget.loading || widget.icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: DS.t(fontSize, color: fg, weight: FontWeight.w600, height: 1.2),
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              }
            : null,
        child: Opacity(
          opacity: enabled || widget.loading ? 1 : 0.45,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            transform: Matrix4.translationValues(0, press, 0),
            padding: pad,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(radius),
              border: border == null ? null : Border.all(color: border, width: widget.variant == DsVariant.ghost ? 2 : 1.5),
              boxShadow: hasShadow ? [BoxShadow(color: shadow, offset: Offset(0, _down ? 2 : 5))] : null,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

class DsIconButton extends StatelessWidget {
  const DsIconButton({super.key, required this.icon, required this.onTap, this.tooltip, this.size = 44, this.color = DS.ink});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(size * 0.32), side: const BorderSide(color: DS.ink, width: 2)),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(size * 0.32)),
          onTap: onTap,
          child: SizedBox(width: size, height: size, child: Icon(icon, size: size * 0.5, color: color)),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- cards

class DsCard extends StatelessWidget {
  const DsCard({super.key, required this.child, this.flat = false, this.padding = const EdgeInsets.all(18), this.color = Colors.white, this.onTap, this.radius = 22});
  final Widget child;
  final bool flat;
  final EdgeInsetsGeometry padding;
  final Color color;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: flat ? DS.line : DS.ink, width: flat ? 1.5 : 2),
    );
    return Material(
      color: color,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? Padding(padding: padding, child: child) : InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Numbered section box used in onboarding and the product form.
class DsSection extends StatelessWidget {
  const DsSection({super.key, required this.step, required this.title, this.subtitle, required this.child, this.trailing});
  final String step;
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: DS.paper, borderRadius: BorderRadius.circular(18), border: Border.all(color: DS.line, width: 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: DS.teal, borderRadius: BorderRadius.circular(8)),
            child: Text(step, style: DS.t(14, color: Colors.white, weight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: DS.h(18))),
          if (trailing != null) trailing!,
        ]),
        if (subtitle != null) ...[const SizedBox(height: 6), Text(subtitle!, style: DS.mutedText(14))],
        const SizedBox(height: 14),
        child,
      ]),
    );
  }
}

// ---------------------------------------------------------------- inputs

class DsField extends StatelessWidget {
  const DsField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.keyboardType,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.prefixText,
    this.suffix,
    this.onChanged,
    this.inputFormatters,
    this.enabled = true,
    this.textCapitalization = TextCapitalization.sentences,
    this.autofocus = false,
    this.errorText,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final TextInputType? keyboardType;
  final int? maxLength;
  final int maxLines;
  final int? minLines;
  final String? prefixText;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;
  final TextCapitalization textCapitalization;
  final bool autofocus;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (label.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(label, style: DS.t(15, weight: FontWeight.w600))),
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLength: maxLength,
        maxLines: maxLines,
        minLines: minLines,
        onChanged: onChanged,
        enabled: enabled,
        autofocus: autofocus,
        inputFormatters: inputFormatters,
        textCapitalization: textCapitalization,
        style: DS.t(17, weight: FontWeight.w500),
        decoration: dsInputDecoration(hint: hint, prefixText: prefixText, suffix: suffix, errorText: errorText),
      ),
    ]);
  }
}

InputDecoration dsInputDecoration({String? hint, String? prefixText, Widget? suffix, String? errorText, Widget? prefixIcon}) {
  OutlineInputBorder b(Color c) => OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide(color: c, width: 2));
  return InputDecoration(
    hintText: hint,
    hintStyle: DS.t(16, color: const Color(0xFF8AA5A3)),
    prefixText: prefixText,
    prefixStyle: DS.t(17, weight: FontWeight.w600),
    prefixIcon: prefixIcon,
    suffixIcon: suffix,
    errorText: errorText,
    counterText: '',
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
    border: b(DS.line),
    enabledBorder: b(DS.line),
    disabledBorder: b(DS.line),
    focusedBorder: b(DS.teal),
    errorBorder: b(DS.awning),
    focusedErrorBorder: b(DS.awning),
  );
}

/// Dropdown styled like the inputs.
class DsSelect<T> extends StatelessWidget {
  const DsSelect({super.key, required this.label, required this.value, required this.items, required this.onChanged, this.hint});
  final String label;
  final T? value;
  final List<(T, String)> items;
  final ValueChanged<T?> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (label.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(label, style: DS.t(15, weight: FontWeight.w600))),
      DropdownButtonFormField<T>(
        initialValue: items.any((i) => i.$1 == value) ? value : null,
        isExpanded: true,
        hint: hint == null ? null : Text(hint!, style: DS.t(16, color: const Color(0xFF8AA5A3))),
        items: items.map((i) => DropdownMenuItem<T>(value: i.$1, child: Text(i.$2, style: DS.t(16, weight: FontWeight.w500)))).toList(),
        onChanged: onChanged,
        decoration: dsInputDecoration(),
        borderRadius: BorderRadius.circular(14),
        dropdownColor: Colors.white,
      ),
    ]);
  }
}

class DsChip extends StatelessWidget {
  const DsChip({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DS.teal : Colors.white,
      shape: StadiumBorder(side: BorderSide(color: selected ? DS.teal : DS.line, width: 2)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(label, style: DS.t(15, color: selected ? Colors.white : DS.ink, weight: FontWeight.w500)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- sheets

/// Paper bottom sheet with the ink border and grab handle.
class DsSheetFrame extends StatelessWidget {
  const DsSheetFrame({super.key, required this.child, this.title});
  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        decoration: const BoxDecoration(
          color: DS.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: DS.ink, width: 2), left: BorderSide(color: DS.ink, width: 2), right: BorderSide(color: DS.ink, width: 2)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: DS.line, borderRadius: BorderRadius.circular(9)))),
              const SizedBox(height: 14),
              if (title != null) ...[Text(title!, style: DS.h(24)), const SizedBox(height: 14)],
              child,
            ]),
          ),
        ),
      ),
    );
  }
}

Future<T?> showDsSheet<T>(BuildContext context, {String? title, required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: DS.ink.withValues(alpha: 0.55),
    builder: (ctx) => DsSheetFrame(title: title, child: builder(ctx)),
  );
}

class DsQuickAction extends StatelessWidget {
  const DsQuickAction({super.key, required this.icon, required this.title, this.subtitle, required this.onTap, this.bg = DS.tealSoft, this.fg = DS.teal});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DsCard(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: onTap,
        child: Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: fg, size: 22)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: DS.t(17, weight: FontWeight.w600)),
              if (subtitle != null) Text(subtitle!, style: DS.mutedText(14)),
            ]),
          ),
        ]),
      ),
    );
  }
}

Future<bool> confirmDialog(BuildContext context, {required String title, required String message, String? confirmLabel, bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Row(children: [
          Expanded(child: DsButton(label: tr('Cancel', 'रद्द करें'), variant: DsVariant.ghost, small: true, block: true, onTap: () => Navigator.pop(ctx, false))),
          const SizedBox(width: 10),
          Expanded(
            child: DsButton(
              label: confirmLabel ?? tr('Yes', 'हाँ'),
              variant: danger ? DsVariant.danger : DsVariant.primary,
              small: true,
              block: true,
              onTap: () => Navigator.pop(ctx, true),
            ),
          ),
        ]),
      ],
    ),
  );
  return ok ?? false;
}

void toast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? const Color(0xFFB3261E) : DS.ink,
      duration: Duration(milliseconds: error ? 4000 : 2600),
    ));
}

// ---------------------------------------------------------- page chrome

class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: DS.h(28)),
            if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle!, style: DS.mutedText(15))],
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ]),
    );
  }
}

class BackLink extends StatelessWidget {
  const BackLink({super.key, required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: DS.muted, padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4)),
        onPressed: onTap ?? () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.chevron_left, size: 22),
        label: Text(label, style: DS.t(15.5, color: DS.muted, weight: FontWeight.w600)),
      ),
    );
  }
}

/// Row tile: coloured thumbnail, title, subtitle, chevron.
class DsTile extends StatelessWidget {
  const DsTile({super.key, required this.title, this.subtitle, required this.thumb, this.onTap, this.trailing, this.flat = false});
  final String title;
  final String? subtitle;
  final Widget thumb;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DsCard(
        flat: flat,
        radius: 20,
        padding: const EdgeInsets.all(12),
        onTap: onTap,
        child: Row(children: [
          thumb,
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: DS.h(18)),
              if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: DS.mutedText(14.5))],
            ]),
          ),
          trailing ?? (onTap != null ? const Icon(Icons.chevron_right, color: DS.muted) : const SizedBox.shrink()),
        ]),
      ),
    );
  }
}

class DsThumb extends StatelessWidget {
  const DsThumb({super.key, this.image = '', this.label = '', this.icon, this.bg = DS.tintYellow, this.fg = DS.ink, this.size = 62, this.radius = 15});
  final String image;
  final String label;
  final IconData? icon;
  final Color bg;
  final Color fg;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: icon != null ? Icon(icon, color: fg, size: size * 0.45) : Text(label, style: DS.h(size * 0.42, color: fg)),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
      clipBehavior: Clip.antiAlias,
      child: image.isEmpty ? fallback : Image.network(image, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
    );
  }
}

class EmptyStall extends StatelessWidget {
  const EmptyStall({super.key, required this.emoji, required this.title, required this.message, this.action});
  final String emoji;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 22, 10, 10),
      child: Column(children: [
        SizedBox(
          width: 130,
          child: Column(children: [
            Container(
              height: 28,
              decoration: BoxDecoration(border: Border.all(color: DS.ink, width: 2), borderRadius: const BorderRadius.vertical(top: Radius.circular(10))),
              child: const ClipRRect(borderRadius: BorderRadius.vertical(top: Radius.circular(8)), child: Awning(height: 24, stripe: 16)),
            ),
            Container(
              height: 70,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: DS.tealSoft,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
                border: Border(left: BorderSide(color: DS.ink, width: 2), right: BorderSide(color: DS.ink, width: 2), bottom: BorderSide(color: DS.ink, width: 2)),
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 32)),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Text(title, textAlign: TextAlign.center, style: DS.h(22)),
        const SizedBox(height: 6),
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 300), child: Text(message, textAlign: TextAlign.center, style: DS.mutedText(15))),
        if (action != null) ...[const SizedBox(height: 14), action!],
      ]),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.bg = DS.tintYellow, this.fg = DS.ink, this.border});
  final String label;
  final Color bg;
  final Color fg;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99), border: border == null ? null : Border.all(color: border!, width: 1.5)),
      child: Text(label, style: DS.t(12.5, color: fg, weight: FontWeight.w700, height: 1.3)),
    );
  }
}

/// English / हिंदी segmented toggle.
class LangToggle extends StatelessWidget {
  const LangToggle({super.key, this.onDark = false});
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final s = Session.instance;
    Widget btn(String code, String label) {
      final on = s.lang == code;
      return GestureDetector(
        onTap: () => s.setLang(code),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(color: on ? (onDark ? DS.marigold : DS.ink) : Colors.transparent, borderRadius: BorderRadius.circular(99)),
          child: Text(label, style: DS.t(14, weight: FontWeight.w600, color: on ? (onDark ? DS.ink : Colors.white) : (onDark ? Colors.white : DS.muted))),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.18) : Colors.white,
        borderRadius: BorderRadius.circular(99),
        border: onDark ? null : Border.all(color: DS.line, width: 1.5),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [btn('en', 'English'), btn('hi', 'हिंदी')]),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: const Color(0xFFFDE8E6), borderRadius: BorderRadius.circular(14), border: Border.all(color: DS.awning, width: 2)),
      child: Row(children: [
        const Icon(Icons.error_outline, color: Color(0xFFC5221F)),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: DS.t(14.5, color: const Color(0xFFC5221F), weight: FontWeight.w600))),
      ]),
    );
  }
}

/// Rebuilds [State] whenever the [Session] changes (data or language).
mixin SessionAware<T extends StatefulWidget> on State<T> {
  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    Session.instance.addListener(_onSession);
  }

  @override
  void dispose() {
    Session.instance.removeListener(_onSession);
    super.dispose();
  }
}
