import 'package:enough_mail/enough_mail.dart' hide MailAccount, ServerConfig;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/html_sanitizer.dart';

/// Toont de inhoud van een mail: opgeschoonde HTML of platte tekst met
/// klikbare links. Trackers worden altijd verwijderd; externe afbeeldingen
/// alleen geladen na een tik op "Afbeeldingen laden".
class MailBody extends StatefulWidget {
  final MimeMessage message;

  /// Wordt aangeroepen bij een tik op een mailto:-link.
  final void Function(String address) onMailto;

  const MailBody({super.key, required this.message, required this.onMailto});

  @override
  State<MailBody> createState() => _MailBodyState();
}

class _MailBodyState extends State<MailBody> {
  bool _loadImages = false;
  late final String? _rawHtml = widget.message.decodeTextHtmlPart();
  late final String? _plain = widget.message.decodeTextPlainPart();
  SanitizedHtml? _sanitized;

  bool get _isHtml => _rawHtml != null && _rawHtml.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _sanitize();
  }

  void _sanitize() {
    _sanitized = _isHtml
        ? sanitizeEmailHtml(_rawHtml!, allowRemoteImages: _loadImages)
        : SanitizedHtml(plainTextToHtml((_plain ?? '').trim()), 0, 0, 0);
  }

  Future<bool> _onTapUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return true;
    if (uri.isScheme('mailto')) {
      widget.onMailto(uri.path);
      return true;
    }
    if (!(uri.isScheme('http') || uri.isScheme('https') || uri.isScheme('tel'))) {
      return true; // andere schema's negeren
    }
    final cleaned = cleanUrl(url);
    if (!mounted) return true;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Link openen?', style: Theme.of(c).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(Uri.parse(cleaned).host,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              SelectableText(cleaned,
                  maxLines: 4, style: Theme.of(c).textTheme.bodySmall),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: cleaned));
                        Navigator.pop(c);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link gekopieerd')));
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Kopiëren'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(c);
                        launchUrl(Uri.parse(cleaned), mode: LaunchMode.externalApplication);
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Openen'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final s = _sanitized!;
    final theme = Theme.of(context);
    final html = HtmlWidget(
      s.html,
      onTapUrl: _onTapUrl,
      renderMode: RenderMode.column,
      // HTML-mails gaan uit van een witte achtergrond; platte tekst volgt het thema.
      textStyle: _isHtml
          ? const TextStyle(color: Colors.black87, fontSize: 15)
          : theme.textTheme.bodyLarge,
      customStylesBuilder: (el) =>
          el.localName == 'a' && !_isHtml ? {'color': _hex(theme.colorScheme.primary)} : null,
      onErrorBuilder: (context, el, err) => const SizedBox.shrink(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.blockedImages > 0 || s.removedTrackers > 0 || s.cleanedLinks > 0)
          _PrivacyBanner(
            result: s,
            imagesLoaded: _loadImages,
            onLoadImages: () => setState(() {
              _loadImages = true;
              _sanitize();
            }),
          ),
        if (_isHtml)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: SelectionArea(child: html),
            ),
          )
        else
          SelectionArea(child: html),
      ],
    );
  }

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

class _PrivacyBanner extends StatelessWidget {
  final SanitizedHtml result;
  final bool imagesLoaded;
  final VoidCallback onLoadImages;

  const _PrivacyBanner(
      {required this.result, required this.imagesLoaded, required this.onLoadImages});

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (result.removedTrackers > 0) '${result.removedTrackers} tracker(s) verwijderd',
      if (result.cleanedLinks > 0) '${result.cleanedLinks} link(s) opgeschoond',
      if (result.blockedImages > 0) '${result.blockedImages} externe afbeelding(en) geblokkeerd',
    ];
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.shield_outlined, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(parts.join(' · '),
                  style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 13)),
            ),
            if (result.blockedImages > 0 && !imagesLoaded)
              TextButton(onPressed: onLoadImages, child: const Text('Afbeeldingen laden')),
          ],
        ),
      ),
    );
  }
}
