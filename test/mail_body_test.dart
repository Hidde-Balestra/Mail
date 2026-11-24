import 'package:enough_mail/enough_mail.dart' show MessageBuilder, MailAddress;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mail_client/widgets/mail_body.dart';

void main() {
  testWidgets('MailBody rendert HTML-mail en toont privacy-melding', (tester) async {
    final builder = MessageBuilder.prepareMultipartAlternativeMessage(
      plainText: 'Hallo',
      htmlText: '<h1>Nieuwsbrief</h1><p>Lees <a href="https://a.nl/?utm_source=x">meer</a></p>'
          '<img src="https://t.nl/open.php" width="1" height="1">'
          '<img src="https://cdn.nl/foto.jpg" alt="Foto">'
          '<table><tr><td>Cel</td></tr></table>',
    )
      ..from = [MailAddress('A', 'a@a.nl')]
      ..to = [MailAddress('B', 'b@b.nl')]
      ..subject = 'Test';
    final msg = builder.buildMimeMessage();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: MailBody(message: msg, onMailto: (_) {}))),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nieuwsbrief', findRichText: true), findsOneWidget);
    expect(find.textContaining('tracker(s) verwijderd'), findsOneWidget);
    expect(find.text('Afbeeldingen laden'), findsOneWidget);

    await tester.tap(find.text('Afbeeldingen laden'));
    await tester.pump();
    expect(find.text('Afbeeldingen laden'), findsNothing);
  });
}
