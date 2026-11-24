import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Resultaat van het opschonen van een HTML-mail.
class SanitizedHtml {
  final String html;

  /// Aantal externe afbeeldingen dat is geblokkeerd (kan alsnog geladen worden).
  final int blockedImages;

  /// Aantal verwijderde trackers (pixels, beacons, scripts, ping-attributen...).
  final int removedTrackers;

  /// Aantal links waaruit tracking-parameters zijn verwijderd.
  final int cleanedLinks;

  const SanitizedHtml(this.html, this.blockedImages, this.removedTrackers, this.cleanedLinks);
}

/// Elementen die nooit in een mail thuishoren: actieve inhoud of externe bronnen.
const _forbiddenTags = {
  'script', 'noscript', 'iframe', 'frame', 'frameset', 'object', 'embed',
  'applet', 'form', 'input', 'button', 'select', 'textarea', 'link', 'meta',
  'base', 'audio', 'video', 'source', 'track', 'svg', 'math', 'portal',
  'title', 'head',
};

/// Attributen die externe verzoeken kunnen doen of code uitvoeren.
const _forbiddenAttrs = {
  'ping', 'background', 'srcset', 'lowsrc', 'dynsrc', 'longdesc', 'poster',
  'formaction', 'action', 'data', 'codebase', 'manifest', 'xmlns',
};

/// Bekende tracking-domeinen/paden voor open-pixels en beacons.
final _trackerPatterns = RegExp(
  r'(list-manage\.com/track|/track/open|/open\.php|/wf/open|'
  r'/e/o/|mandrillapp\.com/track|hubspot.*/e2t/|track\.hubspot|t\.hubspotemail|'
  r'hs-analytics|sparkpostmail\.com/q/|^https?://email\.mg\.[^/]+/o/|'
  r'/beacon|/pixel|//pixel\.|//tracking\.|/trk|/tr\?|/imp\?|'
  r'google-analytics\.com|doubleclick\.net|facebook\.com/tr|exacttarget\.com|'
  r'/oo/|cmail\d+\.com/t/|createsend|mailtrack\.io|getnotify|yesware|bananatag|'
  r'streak\.com|mixmax|superhuman\.com|mailsuite|readnotify|emltrk|klclick|'
  r'klaviyo.*/open|ct\.sendgrid|links\.\w+\.\w+/(open|o)/)',
  caseSensitive: false,
);

/// Query-parameters die alleen dienen om klikken te volgen.
final _trackingParams = RegExp(
  r'^(utm_\w+|fbclid|gclid|gclsrc|dclid|gbraid|wbraid|msclkid|yclid|twclid|'
  r'ttclid|li_fat_id|igshid|igsh|mc_cid|mc_eid|_hsenc|_hsmi|__hssc|__hstc|'
  r'__hsfp|hsctatracking|mkt_tok|vero_id|vero_conv|oly_anon_id|oly_enc_id|'
  r'rb_clickid|s_cid|ncid|cmpid|_ga|_gl|wickedid|ml_subscriber|ml_subscriber_hash|'
  r'trk|trkcampaign|sc_cid|ss_source|ss_campaign_id|elqtrackid|elqtrack|'
  r'elq|elqaid|elqat|elqcampaignid|spm|scm|ref_src|ref_url|si|epik)$',
  caseSensitive: false,
);

/// Parameters waarin doorstuurdiensten de echte bestemming zetten.
const _redirectParams = ['url', 'u', 'q', 'target', 'dest', 'destination', 'redirect',
    'redirect_url', 'redirect_uri', 'link', 'to', 'goto', 'r'];

/// Verwijdert tracking-parameters en pakt doorstuur-links uit.
String cleanUrl(String url) {
  var uri = Uri.tryParse(url.trim());
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) return url.trim();

  // Doorstuur-link (bijv. google.com/url?q=..., safelinks, tracking-redirects):
  // als een parameter zelf een volledige http(s)-URL is, gebruik die.
  for (var i = 0; i < 3; i++) {
    final params = uri!.queryParameters;
    String? inner;
    for (final p in _redirectParams) {
      final v = params[p];
      if (v != null && RegExp(r'^https?://', caseSensitive: false).hasMatch(v)) {
        inner = v;
        break;
      }
    }
    final next = inner == null ? null : Uri.tryParse(inner);
    if (next == null || next.host.isEmpty) break;
    uri = next;
  }

  final kept = <String, List<String>>{};
  uri!.queryParametersAll.forEach((k, v) {
    if (!_trackingParams.hasMatch(k)) kept[k] = v;
  });
  // Let op: queryParameters: null betekent "ongewijzigd", dus leeg = query: ''.
  final cleaned = kept.isEmpty ? uri.replace(query: '') : uri.replace(queryParameters: kept);
  var s = cleaned.toString();
  if (kept.isEmpty) s = s.replaceFirst(RegExp(r'\?(?=#|$)'), '');
  // Fragment-tracking zoals #utm_source=... ook weghalen
  if (cleaned.fragment.toLowerCase().startsWith('utm_')) {
    s = s.substring(0, s.indexOf('#'));
  }
  return s;
}

bool _isRemote(String? src) {
  if (src == null) return false;
  final s = src.trim().toLowerCase();
  return s.startsWith('http:') || s.startsWith('https:') || s.startsWith('//');
}

int? _px(String? v) => v == null ? null : int.tryParse(RegExp(r'\d+').firstMatch(v)?.group(0) ?? '');

/// Herkent onzichtbare/minuscule afbeeldingen (klassieke open-pixels).
bool _isPixel(Element img) {
  final w = _px(img.attributes['width']);
  final h = _px(img.attributes['height']);
  if ((w != null && w <= 3) || (h != null && h <= 3)) return true;
  final style = (img.attributes['style'] ?? '').toLowerCase().replaceAll(' ', '');
  if (style.contains('display:none') || style.contains('visibility:hidden') ||
      style.contains('opacity:0') || RegExp(r'(^|;)(width|height):[0-3]px').hasMatch(style) ||
      RegExp(r'max-(width|height):[0-3]px').hasMatch(style)) {
    return true;
  }
  return false;
}

/// Haalt `url(...)` (externe achtergronden, fonts) en `@import` uit CSS.
String _stripCssUrls(String css) => css
    .replaceAll(RegExp(r'@import[^;]*;?', caseSensitive: false), '')
    .replaceAll(RegExp(r'url\s*\([^)]*\)', caseSensitive: false), 'none')
    .replaceAll(RegExp(r'expression\s*\(', caseSensitive: false), '(')
    .replaceAll(RegExp(r'behavior\s*:', caseSensitive: false), 'x-removed:');

/// Schoont een HTML-mail op. Met [allowRemoteImages] worden gewone externe
/// afbeeldingen toegestaan; trackers worden altijd verwijderd.
SanitizedHtml sanitizeEmailHtml(String input, {bool allowRemoteImages = false}) {
  final doc = html_parser.parse(input);
  var blocked = 0, trackers = 0, cleanedLinks = 0;

  for (final tag in _forbiddenTags) {
    for (final el in doc.querySelectorAll(tag).toList()) {
      if (tag == 'script' || tag == 'iframe' || tag == 'link' || tag == 'meta') trackers++;
      el.remove();
    }
  }

  for (final el in doc.querySelectorAll('*')) {
    final attrs = el.attributes;
    for (final key in attrs.keys.toList()) {
      final name = key.toString().toLowerCase();
      final value = attrs[key] ?? '';
      if (name.startsWith('on') || _forbiddenAttrs.contains(name)) {
        if (name == 'ping' || name == 'background') trackers++;
        attrs.remove(key);
      } else if (name == 'style') {
        final stripped = _stripCssUrls(value);
        if (stripped != value) trackers++;
        attrs[key] = stripped;
      } else if ((name == 'href' || name == 'src') &&
          RegExp(r'^\s*(javascript|vbscript|data:text/html)', caseSensitive: false)
              .hasMatch(value)) {
        attrs.remove(key);
      }
    }
  }

  for (final style in doc.querySelectorAll('style')) {
    style.text = _stripCssUrls(style.text);
  }

  for (final img in doc.querySelectorAll('img').toList()) {
    final src = img.attributes['src'];
    if (_isPixel(img) || (src != null && _isRemote(src) && _trackerPatterns.hasMatch(src))) {
      trackers++;
      img.remove();
      continue;
    }
    if (src == null || src.trim().isEmpty) {
      img.remove();
    } else if (src.trim().toLowerCase().startsWith('cid:')) {
      // Ingesloten bijlage-afbeelding; wordt (nog) niet ondersteund.
      _replaceWithAlt(img);
    } else if (_isRemote(src) && !allowRemoteImages) {
      blocked++;
      _replaceWithAlt(img);
    }
  }

  for (final a in doc.querySelectorAll('a[href]')) {
    final href = a.attributes['href']!;
    final cleaned = cleanUrl(href);
    if (cleaned != href.trim()) cleanedLinks++;
    a.attributes['href'] = cleaned;
  }

  final body = doc.body?.innerHtml ?? doc.outerHtml;
  return SanitizedHtml(body, blocked, trackers, cleanedLinks);
}

void _replaceWithAlt(Element img) {
  final alt = img.attributes['alt']?.trim();
  if (alt != null && alt.isNotEmpty) {
    img.replaceWith(Text('[$alt]'));
  } else {
    img.remove();
  }
}

/// Zet platte tekst om in eenvoudige HTML met klikbare (opgeschoonde) links.
String plainTextToHtml(String text) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  final linkRe = RegExp(r'''(https?://[^\s<>"']+[^\s<>"'.,;:!?)\]])|([\w.+-]+@[\w-]+\.[\w.-]+\w)''');
  final out = StringBuffer();
  var last = 0;
  for (final m in linkRe.allMatches(text)) {
    out.write(esc(text.substring(last, m.start)));
    final s = m.group(0)!;
    if (m.group(1) != null) {
      out.write('<a href="${esc(cleanUrl(s))}">${esc(s)}</a>');
    } else {
      out.write('<a href="mailto:${esc(s)}">${esc(s)}</a>');
    }
    last = m.end;
  }
  out.write(esc(text.substring(last)));
  // Geciteerde regels (> ...) iets dimmen
  final lines = out.toString().split('\n').map((l) =>
      l.startsWith('&gt;') ? '<span style="color:#888888">$l</span>' : l);
  return '<div style="white-space:pre-wrap">${lines.join('<br>')}</div>';
}
