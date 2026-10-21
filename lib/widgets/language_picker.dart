import 'package:flutter/material.dart';

import '../core/languages_data.dart';
import '../core/session.dart';
import '../core/theme.dart';
import 'ds.dart';

/// Website's "Select your language" sheet: all 22 scheduled Indian languages
/// plus English, searchable by name, script or region.
Future<void> showLanguagePicker(BuildContext context) {
  return showDsSheet(context, title: st('selectLanguage'), builder: (_) => const _LanguageList());
}

class _LanguageList extends StatefulWidget {
  const _LanguageList();

  @override
  State<_LanguageList> createState() => _LanguageListState();
}

class _LanguageListState extends State<_LanguageList> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final list = appLanguages
        .where((l) => q.isEmpty || l.name.toLowerCase().contains(q) || l.native.toLowerCase().contains(q) || l.region.toLowerCase().contains(q) || l.code == q)
        .toList();
    final current = Session.instance.lang;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(st('selectLangSub'), style: DS.mutedText(14.5)),
      const SizedBox(height: 12),
      TextField(
        controller: _q,
        onChanged: (_) => setState(() {}),
        style: DS.t(16),
        decoration: dsInputDecoration(hint: st('searchLangPlaceholder'), prefixIcon: const Icon(Icons.search, color: DS.muted)),
      ),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.1,
        children: [
          for (final l in list)
            Material(
              color: l.code == current ? DS.tealSoft : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: l.code == current ? DS.teal : DS.line, width: l.code == current ? 2.5 : 1.5),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  Session.instance.setLang(l.code);
                  Navigator.pop(context);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          l.native,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: l.rtl ? TextDirection.rtl : TextDirection.ltr,
                          style: DS.t(17, weight: FontWeight.w700, color: l.code == current ? DS.teal : DS.ink),
                        ),
                      ),
                      if (l.code == current) const Icon(Icons.check_circle, size: 18, color: DS.teal),
                    ]),
                    Text('${l.name} • ${l.region}', maxLines: 1, overflow: TextOverflow.ellipsis, style: DS.mutedText(12)),
                  ]),
                ),
              ),
            ),
        ],
      ),
    ]);
  }
}

/// Globe button showing the current language; opens the picker.
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key, this.onDark = false});
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : DS.ink;
    return Material(
      color: onDark ? Colors.white.withValues(alpha: 0.18) : Colors.white,
      shape: StadiumBorder(side: onDark ? BorderSide.none : const BorderSide(color: DS.ink, width: 2)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => showLanguagePicker(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.language, size: 18, color: fg),
            const SizedBox(width: 6),
            Text(currentLanguage.native, style: DS.t(14, weight: FontWeight.w700, color: fg)),
            Icon(Icons.expand_more, size: 18, color: fg),
          ]),
        ),
      ),
    );
  }
}
