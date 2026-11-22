/// Type beveiliging voor een server-verbinding.
enum ConnectionSecurity {
  /// Direct TLS/SSL (bijv. SMTP 465, IMAP 993).
  ssl,

  /// Plain verbinding die via STARTTLS wordt geüpgraded (bijv. SMTP 587, IMAP 143).
  starttls,

  /// Geen versleuteling (alleen voor lokale/test servers).
  none;

  String get label => switch (this) {
        ConnectionSecurity.ssl => 'SSL/TLS',
        ConnectionSecurity.starttls => 'STARTTLS',
        ConnectionSecurity.none => 'Geen (onveilig)',
      };
}

/// Instellingen voor één server (SMTP of IMAP).
class ServerConfig {
  final String host;
  final int port;
  final ConnectionSecurity security;
  final String username;

  /// Het wachtwoord wordt apart in secure storage bewaard, niet in toJson.
  final String password;

  const ServerConfig({
    required this.host,
    required this.port,
    required this.security,
    required this.username,
    this.password = '',
  });

  ServerConfig copyWith({String? password}) => ServerConfig(
        host: host,
        port: port,
        security: security,
        username: username,
        password: password ?? this.password,
      );

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'security': security.name,
        'username': username,
      };

  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
        host: json['host'] as String,
        port: json['port'] as int,
        security: ConnectionSecurity.values.byName(json['security'] as String),
        username: json['username'] as String,
      );
}

/// Een mailaccount: verplicht SMTP (versturen), optioneel IMAP (ontvangen).
class MailAccount {
  final String id;
  final String displayName;
  final String email;
  final ServerConfig smtp;
  final ServerConfig? imap;

  const MailAccount({
    required this.id,
    required this.displayName,
    required this.email,
    required this.smtp,
    this.imap,
  });

  bool get canReceive => imap != null;

  MailAccount copyWith({ServerConfig? smtp, ServerConfig? imap}) => MailAccount(
        id: id,
        displayName: displayName,
        email: email,
        smtp: smtp ?? this.smtp,
        imap: imap ?? this.imap,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'email': email,
        'smtp': smtp.toJson(),
        if (imap != null) 'imap': imap!.toJson(),
      };

  factory MailAccount.fromJson(Map<String, dynamic> json) => MailAccount(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        email: json['email'] as String,
        smtp: ServerConfig.fromJson(json['smtp'] as Map<String, dynamic>),
        imap: json['imap'] == null
            ? null
            : ServerConfig.fromJson(json['imap'] as Map<String, dynamic>),
      );
}

/// Lokaal bewaard verzonden bericht (handig als er geen IMAP is).
class SentMail {
  final String accountId;
  final List<String> to;
  final List<String> cc;
  final String subject;
  final String body;
  final DateTime sentAt;

  const SentMail({
    required this.accountId,
    required this.to,
    required this.cc,
    required this.subject,
    required this.body,
    required this.sentAt,
  });

  Map<String, dynamic> toJson() => {
        'accountId': accountId,
        'to': to,
        'cc': cc,
        'subject': subject,
        'body': body,
        'sentAt': sentAt.toIso8601String(),
      };

  factory SentMail.fromJson(Map<String, dynamic> json) => SentMail(
        accountId: json['accountId'] as String,
        to: (json['to'] as List).cast<String>(),
        cc: (json['cc'] as List).cast<String>(),
        subject: json['subject'] as String,
        body: json['body'] as String,
        sentAt: DateTime.parse(json['sentAt'] as String),
      );
}
