import 'package:flutter_test/flutter_test.dart';
import 'package:mail_client/services/html_sanitizer.dart';

void main() {
  group('cleanUrl', () {
    test('verwijdert tracking-parameters, behoudt de rest', () {
      expect(
        cleanUrl('https://shop.nl/p/123?id=5&utm_source=nb&utm_medium=email&fbclid=abc&gclid=x'),
        'https://shop.nl/p/123?id=5',
      );
      expect(cleanUrl('https://a.nl/?mc_cid=1&mc_eid=2'), 'https://a.nl/');
      expect(cleanUrl('https://a.nl/x?_hsenc=p&_hsmi=9&page=2'), 'https://a.nl/x?page=2');
    });

    test('pakt doorstuur-links uit', () {
      expect(
        cleanUrl('https://www.google.com/url?q=https://example.nl/a?utm_source=g&sa=D'),
        'https://example.nl/a',
      );
      expect(
        cleanUrl('https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fexample.nl%2Fpagina&data=xyz'),
        'https://example.nl/pagina',
      );
    });

    test('laat niet-http links met rust', () {
      expect(cleanUrl('mailto:a@b.nl'), 'mailto:a@b.nl');
    });
  });

  group('sanitizeEmailHtml', () {
    test('verwijdert scripts, iframes, formulieren en event-handlers', () {
      final r = sanitizeEmailHtml(
        '<p onclick="steal()">Hoi</p><script>alert(1)</script>'
        '<iframe src="https://evil"></iframe><form action="x"><input></form>'
        '<a href="javascript:alert(1)">x</a>',
      );
      expect(r.html, isNot(contains('script')));
      expect(r.html, isNot(contains('iframe')));
      expect(r.html, isNot(contains('form')));
      expect(r.html, isNot(contains('onclick')));
      expect(r.html, isNot(contains('javascript:')));
      expect(r.html, contains('Hoi'));
    });

    test('verwijdert tracking-pixels, ook als afbeeldingen geladen mogen worden', () {
      final r = sanitizeEmailHtml(
        '<p>Tekst</p>'
        '<img src="https://x.list-manage.com/track/open.php?u=1" width="1" height="1">'
        '<img src="https://cdn.nl/spacer.gif" style="display:none">'
        '<img src="https://t.sendgrid.net/wf/open?upn=abc">'
        '<img src="https://cdn.nl/logo.png" alt="Logo" width="200">',
        allowRemoteImages: true,
      );
      expect(r.removedTrackers, 3);
      expect(r.html, isNot(contains('list-manage')));
      expect(r.html, isNot(contains('spacer.gif')));
      expect(r.html, isNot(contains('wf/open')));
      expect(r.html, contains('logo.png'));
    });

    test('blokkeert externe afbeeldingen standaard en toont alt-tekst', () {
      final r = sanitizeEmailHtml('<img src="https://cdn.nl/logo.png" alt="Logo" width="200">');
      expect(r.blockedImages, 1);
      expect(r.html, isNot(contains('cdn.nl')));
      expect(r.html, contains('[Logo]'));
    });

    test('haalt externe CSS (url(), @import), ping en background weg', () {
      final r = sanitizeEmailHtml(
        '<style>@import url(https://t.nl/a.css); .x{background:url(https://t.nl/p.gif)}</style>'
        '<div style="background-image:url(https://t.nl/o.gif)" background="https://t.nl/b.gif">'
        '<a href="https://a.nl" ping="https://t.nl/ping">link</a></div>',
      );
      expect(r.html, isNot(contains('t.nl')));
      expect(r.html, contains('href="https://a.nl"'));
    });

    test('schoont links op', () {
      final r = sanitizeEmailHtml('<a href="https://a.nl/?utm_campaign=x&id=1">a</a>');
      expect(r.cleanedLinks, 1);
      expect(r.html, contains('href="https://a.nl/?id=1"'));
    });
  });

  test('plainTextToHtml maakt links klikbaar en escapet HTML', () {
    final h = plainTextToHtml('Zie https://a.nl/x?utm_source=y. Mail info@a.nl <b>');
    expect(h, contains('<a href="https://a.nl/x">https://a.nl/x?utm_source=y</a>.'));
    expect(h, contains('href="mailto:info@a.nl"'));
    expect(h, contains('&lt;b&gt;'));
  });
}
