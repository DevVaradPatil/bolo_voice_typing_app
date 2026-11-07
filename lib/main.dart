import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const channel = MethodChannel('bolo');

/// Design tokens (see brand/BRAND.md). Monochrome base; saffron only where the voice is.
class P {
  const P._(this.bg, this.surface, this.surface2, this.line, this.ink, this.ink2, this.saffron, this.leaf);
  final Color bg, surface, surface2, line, ink, ink2, saffron, leaf;

  static const light = P._(Color(0xFFF7F5F1), Color(0xFFFFFFFF), Color(0xFFF0EDE7), Color(0xFFE7E3DB),
      Color(0xFF17171C), Color(0xFF6A6973), Color(0xFFFF6A3D), Color(0xFF1F9D6B));
  static const dark = P._(Color(0xFF0F0F12), Color(0xFF18181D), Color(0xFF222228), Color(0xFF2B2B32),
      Color(0xFFF4F2EE), Color(0xFFA09FA8), Color(0xFFFF7A50), Color(0xFF3CC48D));

  static P of(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? dark : light;
}

/// Sarvam saaras:v4 language codes: (own-script name, English name).
const languages = {
  'unknown': ('Auto-detect', 'Any language'),
  'en-IN': ('English', 'English'),
  'hi-IN': ('हिन्दी', 'Hindi'),
  'mr-IN': ('मराठी', 'Marathi'),
  'bn-IN': ('বাংলা', 'Bengali'),
  'gu-IN': ('ગુજરાતી', 'Gujarati'),
  'pa-IN': ('ਪੰਜਾਬੀ', 'Punjabi'),
  'ta-IN': ('தமிழ்', 'Tamil'),
  'te-IN': ('తెలుగు', 'Telugu'),
  'kn-IN': ('ಕನ್ನಡ', 'Kannada'),
  'ml-IN': ('മലയാളം', 'Malayalam'),
  'od-IN': ('ଓଡ଼ିଆ', 'Odia'),
  'as-IN': ('অসমীয়া', 'Assamese'),
  'ur-IN': ('اردو', 'Urdu'),
  'ne-IN': ('नेपाली', 'Nepali'),
  'kok-IN': ('कोंकणी', 'Konkani'),
  'mai-IN': ('मैथिली', 'Maithili'),
  'doi-IN': ('डोगरी', 'Dogri'),
  'brx-IN': ('बड़ो', 'Bodo'),
  'sa-IN': ('संस्कृतम्', 'Sanskrit'),
  'sd-IN': ('سنڌي', 'Sindhi'),
  'ks-IN': ('کٲشُر', 'Kashmiri'),
  'sat-IN': ('ᱥᱟᱱᱛᱟᱲᱤ', 'Santali'),
  'mni-IN': ('ꯃꯤꯇꯩꯂꯣꯟ', 'Manipuri'),
};

/// Sarvam output modes: (label, example of "see you tomorrow" spoken in Hindi).
const modes = {
  'transcribe': ('Own script', 'कल मिलते हैं'),
  'translit': ('Roman', 'kal milte hain'),
  'codemix': ('Mixed', 'कल meeting है'),
  'translate': ('English', 'See you tomorrow'),
};

ThemeData theme(Brightness b) {
  final p = b == Brightness.dark ? P.dark : P.light;
  return ThemeData(
    brightness: b,
    fontFamily: 'Figtree',
    scaffoldBackgroundColor: p.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: p.saffron, brightness: b).copyWith(
      primary: p.ink, onPrimary: p.bg, surface: p.surface, onSurface: p.ink, outline: p.line),
    textSelectionTheme: TextSelectionThemeData(cursorColor: p.saffron, selectionHandleColor: p.saffron),
  );
}

void main() => runApp(MaterialApp(
      title: 'Bolo',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const Home(),
    ));

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  Map status = {};
  List history = [];
  Timer? poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    // Dictations land in native prefs; pick them up while the app is open (e.g. from "Try it here").
    poll = Timer.periodic(const Duration(seconds: 2), (_) => load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    poll?.cancel();
    super.dispose();
  }

  // Permissions are granted in system screens; re-read when we come back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) load();
  }

  Future<void> load() async {
    final s = await channel.invokeMethod<Map>('status');
    final h = jsonDecode(await channel.invokeMethod<String>('history') ?? '[]') as List;
    if (mounted) setState(() { status = s ?? {}; history = h; });
  }

  Future<void> set(String key, String value) async {
    await channel.invokeMethod('set', {'key': key, 'value': value});
    load();
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final mic = status['mic'] == true, service = status['service'] == true;
    final lang = languages[status['lang'] ?? 'unknown']!;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Row(children: [
              const BoloMark(size: 36),
              const SizedBox(width: 10),
              Text('Bolo', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: p.ink)),
            ]),
            const SizedBox(height: 28),
            Text('Speak in your language.\nBolo types it, anywhere.',
                style: TextStyle(fontSize: 30, height: 1.12, fontWeight: FontWeight.w800, letterSpacing: -0.9, color: p.ink)),
            const SizedBox(height: 24),
            if (!(mic && service)) ...[
              _Setup(mic: mic, service: service),
              const SizedBox(height: 12),
            ],
            _HowItWorks(ready: mic && service),
            const _Label('Language'),
            _Tile(
              onTap: () => pickLanguage(context),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(lang.$1, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: p.ink)),
                    const SizedBox(height: 2),
                    Text(status['lang'] == 'unknown' || status['lang'] == null ? 'Bolo works out what you\'re speaking' : lang.$2,
                        style: TextStyle(fontSize: 14, color: p.ink2)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: p.ink2),
              ]),
            ),
            const _Label('Write as'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.9,
              children: [
                for (final m in modes.entries)
                  _ModeCard(
                    label: m.value.$1,
                    example: m.value.$2,
                    selected: (status['mode'] ?? 'transcribe') == m.key,
                    onTap: () => set('mode', m.key),
                  ),
              ],
            ),
            const _Label('Try it here'),
            TextField(
              minLines: 3,
              maxLines: 6,
              style: TextStyle(fontSize: 17, height: 1.4, color: p.ink),
              decoration: InputDecoration(
                hintText: 'Tap here, then hold the bubble and speak…',
                hintStyle: TextStyle(color: p.ink2),
                filled: true,
                fillColor: p.surface,
                contentPadding: const EdgeInsets.all(18),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: p.line)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: p.ink, width: 1.5)),
              ),
            ),
            if (history.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 28, 0, 4),
                child: Row(children: [
                  Text('Recent', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink2)),
                  const Spacer(),
                  TextButton(
                    onPressed: () async { await channel.invokeMethod('clearHistory'); load(); },
                    style: TextButton.styleFrom(foregroundColor: p.ink2),
                    child: const Text('Clear'),
                  ),
                ]),
              ),
              _Tile(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final (i, h) in history.indexed) ...[
                    if (i > 0) Divider(height: 1, indent: 18, endIndent: 18, color: p.line),
                    _RecentItem(text: h['text'], at: DateTime.fromMillisecondsSinceEpoch(h['t'])),
                  ],
                ]),
              ),
            ],
            const SizedBox(height: 28),
            Center(child: Text('Speech by Sarvam AI', style: TextStyle(fontSize: 13, color: p.ink2))),
          ],
        ),
      ),
    );
  }

  Future<void> pickLanguage(BuildContext context) async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: P.of(context).surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _LanguageSheet(selected: status['lang'] ?? 'unknown'),
    );
    if (code != null) set('lang', code);
  }
}

class _Setup extends StatelessWidget {
  const _Setup({required this.mic, required this.service});
  final bool mic, service;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final done = (mic ? 1 : 0) + (service ? 1 : 0);
    return _Tile(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Get set up', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.ink)),
          const Spacer(),
          Text('$done of 2', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink2)),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: done / 2, minHeight: 6, backgroundColor: p.surface2, color: p.leaf),
        ),
        const SizedBox(height: 8),
        _Step(
          done: mic,
          title: 'Allow the microphone',
          body: 'So Bolo can hear you.',
          action: 'Allow',
          onTap: () => channel.invokeMethod('askMic'),
        ),
        Divider(height: 1, color: p.line),
        _Step(
          done: service,
          title: 'Turn on the Bolo bubble',
          body: 'In Accessibility, open Bolo bubble and switch it on. If Android says "Restricted setting", '
              'go to App info → ⋮ → Allow restricted settings first.',
          action: 'Turn on',
          onTap: () => channel.invokeMethod('openAccessibility'),
        ),
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.done, required this.title, required this.body, required this.action, required this.onTap});
  final bool done;
  final String title, body, action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? p.leaf : Colors.transparent,
            border: Border.all(color: done ? p.leaf : p.line, width: 2),
          ),
          child: done ? Icon(Icons.check_rounded, size: 16, color: p.surface) : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: done ? p.ink2 : p.ink, decoration: done ? TextDecoration.lineThrough : null)),
            if (!done) ...[
              const SizedBox(height: 4),
              Text(body, style: TextStyle(fontSize: 14, height: 1.4, color: p.ink2)),
            ],
          ]),
        ),
        if (!done) ...[
          const SizedBox(width: 12),
          FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: p.ink,
              foregroundColor: p.bg,
              textStyle: const TextStyle(fontFamily: 'Figtree', fontWeight: FontWeight.w700, fontSize: 14),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            child: Text(action),
          ),
        ],
      ]),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks({required this.ready});
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    Widget row(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 20, color: p.ink),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink)),
                Text(body, style: TextStyle(fontSize: 13.5, color: p.ink2)),
              ]),
            ),
          ]),
        );
    return _Tile(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (ready) ...[
            Container(width: 8, height: 8, decoration: BoxDecoration(color: p.leaf, shape: BoxShape.circle)),
            const SizedBox(width: 8),
          ],
          Text(ready ? 'Ready in every app' : 'How it works',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.ink)),
        ]),
        const SizedBox(height: 2),
        Text('The bubble appears whenever your keyboard does.', style: TextStyle(fontSize: 14, color: p.ink2)),
        row(Icons.touch_app_outlined, 'Hold to talk', 'Let go and your words are typed in.'),
        row(Icons.lock_outline_rounded, 'Slide up to lock', 'For long messages. Talk hands-free.'),
        row(Icons.stop_rounded, 'Tap stop to finish', 'When you\'re locked in.'),
      ]),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.label, required this.example, required this.selected, required this.onTap});
  final String label, example;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? p.ink : p.line, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Expanded(child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.ink))),
              if (selected) Icon(Icons.check_circle_rounded, size: 18, color: p.ink),
            ]),
            Text(example, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: p.ink2)),
          ]),
        ),
      ),
    );
  }
}

class _LanguageSheet extends StatefulWidget {
  const _LanguageSheet({required this.selected});
  final String selected;
  @override
  State<_LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends State<_LanguageSheet> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final items = languages.entries
        .where((e) => q.isEmpty || '${e.value.$1} ${e.value.$2}'.toLowerCase().contains(q.toLowerCase()))
        .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(children: [
        const SizedBox(height: 10),
        Container(width: 36, height: 4, decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('I speak', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: p.ink)),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => setState(() => q = v),
              decoration: InputDecoration(
                hintText: 'Search languages',
                prefixIcon: Icon(Icons.search_rounded, color: p.ink2),
                filled: true,
                fillColor: p.surface2,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final e = items[i];
              final sel = e.key == widget.selected;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: Text(e.value.$1, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.ink)),
                subtitle: e.value.$1 == e.value.$2 ? null : Text(e.value.$2, style: TextStyle(color: p.ink2)),
                trailing: sel ? Icon(Icons.check_rounded, color: p.ink) : null,
                onTap: () => Navigator.pop(context, e.key),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.child, this.onTap, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: p.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _RecentItem extends StatelessWidget {
  const _RecentItem({required this.text, required this.at});
  final String text;
  final DateTime at;

  String get ago {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Copied'), behavior: SnackBarBehavior.floating, duration: Duration(seconds: 1)));
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, height: 1.35, color: p.ink)),
              const SizedBox(height: 4),
              Text(ago, style: TextStyle(fontSize: 13, color: p.ink2)),
            ]),
          ),
          const SizedBox(width: 10),
          Icon(Icons.copy_rounded, size: 18, color: p.ink2),
        ]),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 28, 4, 10),
        child: Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: P.of(context).ink2)),
      );
}

/// The Bolo mark, drawn from the same geometry as brand/logo.svg (108-unit square).
class BoloMark extends StatelessWidget {
  const BoloMark({super.key, this.size = 48});
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _MarkPainter());
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.scale(s.width / 108);
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 108, 108), const Radius.circular(26)),
        Paint()..color = P.light.ink);
    final white = Paint()..color = Colors.white;
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(35, 29, 9, 50), const Radius.circular(4.5)), white);
    c.drawCircle(const Offset(56.5, 63), 12, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8);
    c.drawCircle(const Offset(56.5, 63), 4.5, Paint()..color = P.light.saffron);
  }

  @override
  bool shouldRepaint(_) => false;
}
