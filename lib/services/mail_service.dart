import 'dart:io';

import 'package:enough_mail/enough_mail.dart' hide MailAccount, ServerConfig;

import '../models/mail_account.dart';

/// TLS-certificaat van de server werd geweigerd.
class CertificateProblem implements Exception {
  final String host;

  /// Hostnaam waarvoor het certificaat wél is uitgegeven (indien bekend).
  final String? certificateHost;
  final bool hostnameMismatch;
  final String details;

  CertificateProblem({
    required this.host,
    required this.certificateHost,
    required this.hostnameMismatch,
    required this.details,
  });

  /// Een bruikbare alternatieve hostnaam, als die anders is dan [host].
  String? get suggestedHost {
    final c = certificateHost;
    if (c == null || c.startsWith('*') || c.toLowerCase() == host.toLowerCase()) {
      return null;
    }
    return c;
  }

  @override
  String toString() => 'CertificateProblem($host, cert=$certificateHost): $details';
}

/// Server weigerde gebruikersnaam/wachtwoord.
class LoginFailed implements Exception {
  final String protocol; // 'SMTP' of 'IMAP'
  final String username;
  final String serverMessage;

  LoginFailed(this.protocol, this.username, this.serverMessage);

  @override
  String toString() => 'LoginFailed($protocol, $username): $serverMessage';
}

/// Haalt de CN uit een X509-subject als "/CN=example.nl" of "CN=example.nl, O=..".
String? _commonName(X509Certificate? cert) =>
    cert == null ? null : RegExp(r'CN=([^/,]+)').firstMatch(cert.subject)?.group(1)?.trim();

/// Voert [connect] uit en zet TLS-fouten om in een [CertificateProblem].
Future<T> _withCertCheck<T>(
    String host, X509Certificate? Function() badCert, Future<T> Function() connect) async {
  try {
    return await connect();
  } on HandshakeException catch (e) {
    final msg = '${e.message} ${e.osError?.message ?? ''}';
    throw CertificateProblem(
      host: host,
      certificateHost: _commonName(badCert()),
      hostnameMismatch: msg.toLowerCase().contains('hostname mismatch') ||
          msg.contains('HOSTNAME') ||
          (_commonName(badCert()) != null &&
              _commonName(badCert())!.toLowerCase() != host.toLowerCase()),
      details: msg.trim(),
    );
  }
}

/// Wrapper rond enough_mail voor SMTP (versturen) en IMAP (ontvangen).
class MailService {
  static const _timeout = Duration(seconds: 20);

  // ---------------------------------------------------------------- SMTP

  Future<SmtpClient> _connectSmtp(MailAccount account) async {
    final cfg = account.smtp;
    // EHLO-naam: een adres-literal zoals Thunderbird gebruikt. Het domein van
    // de afzender hier opgeven ("ehlo gmail.com") klopt niet met het IP van
    // de telefoon en wordt door spamfilters (o.a. SpamAssassin) bestraft.
    X509Certificate? badCert;
    final client = SmtpClient('[127.0.0.1]', isLogEnabled: false,
        onBadCertificate: (c) {
      badCert = c;
      return false; // nooit ongeldige certificaten accepteren
    });
    try {
      await _withCertCheck(cfg.host, () => badCert, () async {
        await client.connectToServer(
          cfg.host,
          cfg.port,
          isSecure: cfg.security == ConnectionSecurity.ssl,
          timeout: _timeout,
        );
        await client.ehlo();
        if (cfg.security == ConnectionSecurity.starttls) {
          await client.startTls();
        }
      });
      if (cfg.username.isNotEmpty) {
        // Voorkeur voor PLAIN, val terug op LOGIN als de server alleen dat kent.
        final mechanism = client.serverInfo.supportsAuth(AuthMechanism.plain) ||
                !client.serverInfo.supportsAuth(AuthMechanism.login)
            ? AuthMechanism.plain
            : AuthMechanism.login;
        try {
          await client.authenticate(cfg.username, cfg.password, mechanism);
        } on SmtpException catch (e) {
          throw LoginFailed('SMTP', cfg.username, e.message ?? '');
        }
      }
    } catch (_) {
      await client.disconnect().catchError((_) {});
      rethrow;
    }
    return client;
  }

  /// Test de SMTP-verbinding + login. Gooit een exception bij een fout.
  Future<void> testSmtp(MailAccount account) async {
    final client = await _connectSmtp(account);
    await _safeQuit(client);
  }

  Future<void> send({
    required MailAccount account,
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    required String body,
    MimeMessage? replyTo,
  }) async {
    final name = account.displayName.trim();
    final from = MailAddress(name.isEmpty ? null : name, account.email);
    final builder = replyTo != null
        ? MessageBuilder.prepareReplyToMessage(replyTo, from, replyAll: false)
        : MessageBuilder();
    // Bcc bewust NIET in de headers: alleen in de SMTP-envelope hieronder.
    // Anders ziet elke ontvanger de Bcc-lijst, en dat staat ook verdacht.
    builder
      ..from = [from]
      ..to = to.map((e) => MailAddress(null, e)).toList()
      ..cc = cc.map((e) => MailAddress(null, e)).toList()
      ..bcc = null
      ..subject = subject
      ..text = body;

    final message = builder.buildMimeMessage();
    final client = await _connectSmtp(account);
    try {
      await client.sendMessage(
        message,
        from: from,
        recipients: [...to, ...cc, ...bcc]
            .map((e) => MailAddress(null, e))
            .toList(),
      );
    } finally {
      await _safeQuit(client);
    }
    if (account.imap != null) await appendToSent(account.imap!, message);
  }

  Future<void> _safeQuit(SmtpClient client) async {
    try {
      await client.quit();
    } catch (_) {}
  }

  // ---------------------------------------------------------------- IMAP

  Future<ImapClient> _connectImap(ServerConfig cfg) async {
    X509Certificate? badCert;
    final client = ImapClient(isLogEnabled: false, onBadCertificate: (c) {
      badCert = c;
      return false;
    });
    try {
      await _withCertCheck(cfg.host, () => badCert, () async {
        await client.connectToServer(
          cfg.host,
          cfg.port,
          isSecure: cfg.security == ConnectionSecurity.ssl,
          timeout: _timeout,
        );
        if (cfg.security == ConnectionSecurity.starttls) {
          await client.startTls();
        }
      });
      try {
        await client.login(cfg.username, cfg.password);
      } on ImapException catch (e) {
        throw LoginFailed('IMAP', cfg.username, e.message ?? '');
      }
    } catch (_) {
      // Verbinding sluiten bij een mislukte login, anders blijft de socket open.
      await client.disconnect().catchError((_) {});
      rethrow;
    }
    return client;
  }

  Future<void> testImap(ServerConfig cfg) async {
    final client = await _connectImap(cfg);
    await _safeLogout(client);
  }

  /// Voert [action] uit op een verse IMAP-verbinding en logt daarna uit.
  Future<T> _withImap<T>(
      ServerConfig cfg, Future<T> Function(ImapClient c) action) async {
    final client = await _connectImap(cfg);
    try {
      return await action(client);
    } finally {
      await _safeLogout(client);
    }
  }

  /// Alle mappen op de server (incl. zelfgemaakte mappen uit bijv. Roundcube),
  /// met het aantal ongelezen berichten.
  Future<List<MailFolder>> listFolders(ServerConfig cfg) => _withImap(cfg, (c) async {
        final boxes = await c.listMailboxes(recursive: true);
        final folders = <MailFolder>[];
        for (final box in boxes) {
          if (box.isNotSelectable) continue;
          var unseen = 0;
          try {
            unseen = (await c.statusMailbox(box, [StatusFlags.unseen])).messagesUnseen;
          } catch (_) {}
          folders.add(MailFolder.fromMailbox(box, unseen: unseen));
        }
        folders.sort(MailFolder.compare);
        return folders;
      });

  /// Haalt de nieuwste [count] berichten uit een map op (alleen headers).
  Future<List<MimeMessage>> fetchFolder(ServerConfig cfg, String encodedPath,
          {int count = 50}) =>
      _withImap(cfg, (c) async {
        final box = await c.selectMailboxByPath(encodedPath);
        if (box.messagesExists == 0) return <MimeMessage>[];
        final result = await c.fetchRecentMessages(
          messageCount: count,
          criteria: '(UID FLAGS ENVELOPE)',
        );
        return result.messages
          ..sort((a, b) => (b.sequenceId ?? 0).compareTo(a.sequenceId ?? 0));
      });

  /// Haalt het volledige bericht op via UID (markeert het als gelezen).
  Future<MimeMessage?> fetchFull(ServerConfig cfg, String encodedPath, int uid) =>
      _withImap(cfg, (c) async {
        await c.selectMailboxByPath(encodedPath);
        final result = await c.uidFetchMessage(uid, '(UID FLAGS BODY[])');
        return result.messages.isEmpty ? null : result.messages.first;
      });

  /// Verplaatst naar een andere map.
  Future<void> moveMessage(
          ServerConfig cfg, String fromPath, int uid, String toPath) =>
      _withImap(cfg, (c) async {
        final boxes = await c.listMailboxes(recursive: true);
        final target = boxes.firstWhere((b) => b.encodedPath == toPath);
        await c.selectMailboxByPath(fromPath);
        final seq = MessageSequence.fromId(uid, isUid: true);
        if (c.serverInfo.supportsMove) {
          await c.uidMove(seq, targetMailbox: target);
        } else {
          await c.uidCopy(seq, targetMailbox: target);
          await c.uidMarkDeleted(seq);
          await c.uidExpunge(seq);
        }
      });

  /// Verwijdert een bericht: naar de Prullenbak, of definitief als het al
  /// in de Prullenbak staat (of er geen Prullenbak is).
  /// Geeft `true` terug als het naar de Prullenbak is verplaatst.
  Future<bool> deleteMessage(ServerConfig cfg, String encodedPath, int uid) =>
      _withImap(cfg, (c) async {
        final boxes = await c.listMailboxes(recursive: true);
        final trash = boxes
            .map((b) => (b, MailFolder.fromMailbox(b)))
            .where((e) => e.$2.role == FolderRole.trash)
            .firstOrNull;
        await c.selectMailboxByPath(encodedPath);
        final seq = MessageSequence.fromId(uid, isUid: true);
        if (trash != null && trash.$1.encodedPath != encodedPath) {
          if (c.serverInfo.supportsMove) {
            await c.uidMove(seq, targetMailbox: trash.$1);
          } else {
            await c.uidCopy(seq, targetMailbox: trash.$1);
            await c.uidMarkDeleted(seq);
            await c.uidExpunge(seq);
          }
          return true;
        }
        await c.uidMarkDeleted(seq);
        await c.uidExpunge(seq);
        return false;
      });

  /// Slaat een verzonden bericht op in de map Verzonden op de server
  /// (zoals Roundcube dat ook doet). Fouten worden genegeerd.
  Future<void> appendToSent(ServerConfig cfg, MimeMessage message) async {
    try {
      await _withImap(cfg, (c) async {
        final boxes = await c.listMailboxes(recursive: true);
        final sent = boxes
            .where((b) => MailFolder.fromMailbox(b).role == FolderRole.sent)
            .firstOrNull;
        if (sent == null) return;
        await c.appendMessage(message,
            targetMailbox: sent, flags: [MessageFlags.seen]);
      });
    } catch (_) {}
  }

  Future<void> _safeLogout(ImapClient client) async {
    try {
      await client.logout();
    } catch (_) {}
    await client.disconnect().catchError((_) {});
  }
}

/// Rol van een map, op basis van IMAP special-use vlaggen of de naam.
enum FolderRole { inbox, drafts, sent, archive, junk, trash, other }

class MailFolder {
  final String encodedPath;
  final String path;
  final String name;
  final String separator;
  final FolderRole role;
  final int unseen;

  const MailFolder({
    required this.encodedPath,
    required this.path,
    required this.name,
    required this.separator,
    required this.role,
    this.unseen = 0,
  });

  factory MailFolder.fromMailbox(Mailbox b, {int unseen = 0}) => MailFolder(
        encodedPath: b.encodedPath,
        path: b.path,
        name: b.name,
        separator: b.pathSeparator,
        role: _roleOf(b),
        unseen: unseen,
      );

  static const _names = {
    FolderRole.drafts: ['drafts', 'draft', 'concepten'],
    FolderRole.sent: ['sent', 'sent items', 'sent messages', 'sent mail', 'verzonden', 'verzonden items'],
    FolderRole.archive: ['archive', 'archief'],
    FolderRole.junk: ['junk', 'spam', 'ongewenste e-mail', 'junk e-mail'],
    FolderRole.trash: ['trash', 'deleted items', 'deleted messages', 'prullenbak', 'verwijderde items'],
  };

  static FolderRole _roleOf(Mailbox b) {
    if (b.isInbox || b.path.toUpperCase() == 'INBOX') return FolderRole.inbox;
    if (b.isDrafts) return FolderRole.drafts;
    if (b.isSent) return FolderRole.sent;
    if (b.isArchive) return FolderRole.archive;
    if (b.isJunk) return FolderRole.junk;
    if (b.isTrash) return FolderRole.trash;
    // Geen special-use vlag: herken standaardmappen op naam, maar alleen op
    // het hoogste niveau (of direct onder INBOX bij Dovecot "INBOX."-prefix).
    if (_depthOf(b.path, b.pathSeparator) == 0) {
      final lower = b.name.toLowerCase();
      for (final e in _names.entries) {
        if (e.value.contains(lower)) return e.key;
      }
    }
    return FolderRole.other;
  }

  static int _depthOf(String path, String sep) {
    var parts = path.split(sep);
    if (parts.length > 1 && parts.first.toUpperCase() == 'INBOX') {
      parts = parts.sublist(1); // "INBOX.Werk" telt als hoofdmap
    }
    return parts.length - 1;
  }

  /// Inspringniveau voor weergave van submappen.
  int get depth => role == FolderRole.inbox ? 0 : _depthOf(path, separator);

  String get displayName => switch (role) {
        FolderRole.inbox => 'Inbox',
        FolderRole.drafts => 'Concepten',
        FolderRole.sent => 'Verzonden',
        FolderRole.archive => 'Archief',
        FolderRole.junk => 'Spam',
        FolderRole.trash => 'Prullenbak',
        FolderRole.other => name,
      };

  /// Standaardmappen eerst (vaste volgorde), daarna eigen mappen op pad.
  static int compare(MailFolder a, MailFolder b) {
    final r = a.role.index.compareTo(b.role.index);
    if (r != 0) return r;
    return a.path.toLowerCase().compareTo(b.path.toLowerCase());
  }
}

/// Maakt van een exception een leesbare foutmelding.
String describeMailError(Object e) {
  if (e is LoginFailed) {
    final hint = e.username.contains('@')
        ? 'Controleer het wachtwoord.'
        : 'Gebruik je volledige e-mailadres als gebruikersnaam.';
    return '${e.protocol}-inloggen geweigerd voor "${e.username}". $hint';
  }
  if (e is CertificateProblem) {
    final suggestion = e.suggestedHost;
    if (suggestion != null) {
      return 'Het certificaat van de server is uitgegeven voor "$suggestion", '
          'niet voor "${e.host}". Vul "$suggestion" in als server.';
    }
    if (e.hostnameMismatch) {
      return 'Het certificaat van de server is niet geldig voor "${e.host}". '
          'Probeer je hoofddomein (zonder "mail.") als server, of vraag je '
          'hostingprovider welke hostnaam je moet gebruiken.';
    }
    return 'Het certificaat van "${e.host}" is ongeldig (${e.details}).';
  }
  if (e is SmtpException)return 'SMTP-fout: ${e.message}';
  if (e is ImapException) return 'IMAP-fout: ${e.message ?? e.toString()}';
  final s = e.toString();
  if (s.contains('HandshakeException')) {
    return 'TLS-handshake mislukt. Controleer poort en beveiliging '
        '(465 = SSL/TLS, 587 = STARTTLS).';
  }
  if (s.contains('SocketException') || s.contains('TimeoutException')) {
    return 'Kan geen verbinding maken met de server. Controleer host en poort.';
  }
  return s;
}
