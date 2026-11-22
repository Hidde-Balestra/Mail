import 'package:flutter_test/flutter_test.dart';
import 'package:mail_client/screens/message_screen.dart';

void main() {
  test('htmlToText strips tags', () {
    expect(htmlToText('<p>Hallo<br>wereld</p>'), 'Hallo\nwereld');
  });
}
