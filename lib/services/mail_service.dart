import 'package:enough_mail/enough_mail.dart' hide MailAccount, ServerConfig;

import '../models/mail_account.dart';

/// Wrapper rond enough_mail voor SMTP (versturen) en IMAP (ontvangen).
class MailService {
  static const _timeout = Duration(seconds: 20);

  // ---------------------------------------------------------------- SMTP

  Future<SmtpClient> _connectSmtp(MailAccount account) async {
    final cfg = account.smtp;
    final domain = account.email.contains('@')
        ? account.email.split('@').last
        : 'localhost';
    final client = SmtpClient(domain, isLogEnabled: false);
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
    if (cfg.username.isNotEmpty) {
      // Voorkeur voor PLAIN, val terug op LOGIN als de server alleen dat kent.
      final mechanism = client.serverInfo.supportsAuth(AuthMechanism.plain) ||
              !client.serverInfo.supportsAuth(AuthMechanism.login)
          ? AuthMechanism.plain
          : AuthMechanism.login;
      await client.authenticate(cfg.username, cfg.password, mechanism);
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
    final from = MailAddress(account.displayName, account.email);
    final builder = replyTo != null
        ? MessageBuilder.prepareReplyToMessage(replyTo, from, replyAll: false)
        : MessageBuilder();
    builder
      ..from = [from]
      ..to = to.map((e) => MailAddress(null, e)).toList()
      ..cc = cc.map((e) => MailAddress(null, e)).toList()
      ..bcc = bcc.map((e) => MailAddress(null, e)).toList()
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
  }

  Future<void> _safeQuit(SmtpClient client) async {
    try {
      await client.quit();
    } catch (_) {}
  }

  // ---------------------------------------------------------------- IMAP

  Future<ImapClient> _connectImap(ServerConfig cfg) async {
    final client = ImapClient(isLogEnabled: false);
    await client.connectToServer(
      cfg.host,
      cfg.port,
      isSecure: cfg.security == ConnectionSecurity.ssl,
      timeout: _timeout,
    );
    if (cfg.security == ConnectionSecurity.starttls) {
      await client.startTls();
    }
    await client.login(cfg.username, cfg.password);
    return client;
  }

  Future<void> testImap(ServerConfig cfg) async {
    final client = await _connectImap(cfg);
    await _safeLogout(client);
  }

  /// Haalt de nieuwste [count] berichten uit de inbox op (alleen headers).
  Future<List<MimeMessage>> fetchInbox(ServerConfig cfg,
      {int count = 50}) async {
    final client = await _connectImap(cfg);
    try {
      final box = await client.selectInbox();
      if (box.messagesExists == 0) return [];
      final result = await client.fetchRecentMessages(
        messageCount: count,
        criteria: '(UID FLAGS ENVELOPE BODY.PEEK[HEADER.FIELDS (SUBJECT FROM DATE)])',
      );
      final messages = result.messages
        ..sort((a, b) => (b.sequenceId ?? 0).compareTo(a.sequenceId ?? 0));
      return messages;
    } finally {
      await _safeLogout(client);
    }
  }

  /// Haalt het volledige bericht op via UID (markeert het als gelezen).
  Future<MimeMessage?> fetchFull(ServerConfig cfg, int uid) async {
    final client = await _connectImap(cfg);
    try {
      await client.selectInbox();
      final result =
          await client.uidFetchMessage(uid, '(UID FLAGS BODY[])');
      return result.messages.isEmpty ? null : result.messages.first;
    } finally {
      await _safeLogout(client);
    }
  }

  Future<void> deleteMessage(ServerConfig cfg, int uid) async {
    final client = await _connectImap(cfg);
    try {
      await client.selectInbox();
      await client.uidMarkDeleted(MessageSequence.fromId(uid, isUid: true));
      await client.uidExpunge(MessageSequence.fromId(uid, isUid: true));
    } finally {
      await _safeLogout(client);
    }
  }

  Future<void> _safeLogout(ImapClient client) async {
    try {
      await client.logout();
    } catch (_) {}
  }
}

/// Maakt van een exception een leesbare foutmelding.
String describeMailError(Object e) {
  if (e is SmtpException) return 'SMTP-fout: ${e.message}';
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
