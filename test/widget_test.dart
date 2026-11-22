import 'package:enough_mail/enough_mail.dart' show Mailbox, MailboxFlag;
import 'package:flutter_test/flutter_test.dart';
import 'package:mail_client/screens/message_screen.dart';
import 'package:mail_client/services/mail_service.dart';

MailFolder folder(String path, {String sep = '.', List<MailboxFlag> flags = const []}) =>
    MailFolder.fromMailbox(Mailbox(
      encodedName: path.split(sep).last,
      encodedPath: path,
      pathSeparator: sep,
      flags: [...flags],
    ));

void main() {
  test('htmlToText strips tags', () {
    expect(htmlToText('<p>Hallo<br>wereld</p>'), 'Hallo\nwereld');
  });

  group('MailFolder', () {
    test('herkent standaardmappen op naam (Roundcube/Dovecot)', () {
      expect(folder('INBOX').role, FolderRole.inbox);
      expect(folder('Sent').role, FolderRole.sent);
      expect(folder('INBOX.Sent').role, FolderRole.sent);
      expect(folder('INBOX.Trash').role, FolderRole.trash);
      expect(folder('Junk').role, FolderRole.junk);
      expect(folder('Drafts').role, FolderRole.drafts);
    });

    test('special-use vlag gaat voor naam', () {
      expect(folder('Verzonden items', sep: '/', flags: [MailboxFlag.sent]).role,
          FolderRole.sent);
    });

    test('eigen mappen en submappen', () {
      final werk = folder('INBOX.Werk');
      final klant = folder('INBOX.Werk.Klant A');
      expect(werk.role, FolderRole.other);
      expect(werk.displayName, 'Werk');
      expect(werk.depth, 0);
      expect(klant.depth, 1);
      expect(klant.displayName, 'Klant A');
      // Submap "Sent" onder een eigen map is geen standaardmap
      expect(folder('INBOX.Werk.Sent').role, FolderRole.other);
    });

    test('sortering: standaardmappen eerst, dan eigen mappen op pad', () {
      final list = [
        folder('INBOX.Werk.Klant'), folder('Trash'), folder('INBOX.Archief2'),
        folder('INBOX'), folder('Sent'), folder('INBOX.Werk'),
      ]..sort(MailFolder.compare);
      expect(list.map((f) => f.path).toList(), [
        'INBOX', 'Sent', 'Trash', 'INBOX.Archief2', 'INBOX.Werk', 'INBOX.Werk.Klant',
      ]);
    });
  });
}
