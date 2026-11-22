import 'package:enough_mail/enough_mail.dart' hide MailAccount, ServerConfig;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/mail_account.dart';
import '../services/mail_service.dart';
import 'compose_screen.dart';

/// Toont één bericht uit de inbox.
class MessageScreen extends StatefulWidget {
  final MailAccount account;
  final MimeMessage header;

  const MessageScreen({super.key, required this.account, required this.header});

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> {
  MimeMessage? _message;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = widget.header.uid;
    if (uid == null) {
      setState(() => _error = 'Bericht heeft geen UID');
      return;
    }
    try {
      final m = await MailService().fetchFull(widget.account.imap!, uid);
      setState(() => _message = m);
    } catch (e) {
      setState(() => _error = describeMailError(e));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Bericht verwijderen?'),
        content: const Text('Het bericht wordt definitief van de server verwijderd.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuleren')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Verwijderen')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await MailService().deleteMessage(widget.account.imap!, widget.header.uid!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeMailError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _message ?? widget.header;
    final date = m.decodeDate();
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Beantwoorden',
            icon: const Icon(Icons.reply),
            onPressed: _message == null
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ComposeScreen(
                            account: widget.account, replyTo: _message),
                      ),
                    ),
          ),
          IconButton(
            tooltip: 'Verwijderen',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SelectableText(m.decodeSubject() ?? '(geen onderwerp)',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Text(_initial(m))),
            title: Text(m.from?.firstOrNull?.personalName ??
                m.from?.firstOrNull?.email ??
                'Onbekend'),
            subtitle: Text([
              m.from?.firstOrNull?.email ?? '',
              if (m.to?.isNotEmpty ?? false)
                'aan ${m.to!.map((a) => a.email).join(', ')}',
            ].join('\n')),
            trailing: date == null
                ? null
                : Text(DateFormat('d MMM yyyy\nHH:mm').format(date.toLocal()),
                    textAlign: TextAlign.right),
          ),
          const Divider(),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
          else if (_message == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            SelectableText(_bodyText(_message!)),
            if (_message!.findContentInfo().isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  for (final info in _message!.findContentInfo())
                    Chip(
                      avatar: const Icon(Icons.attach_file, size: 16),
                      label: Text(info.fileName ?? 'bijlage'),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _initial(MimeMessage m) {
    final s = m.from?.firstOrNull?.personalName ?? m.from?.firstOrNull?.email ?? '?';
    return s.isEmpty ? '?' : s[0].toUpperCase();
  }

  /// Toont platte tekst; valt terug op HTML met tags gestript.
  String _bodyText(MimeMessage m) {
    final plain = m.decodeTextPlainPart();
    if (plain != null && plain.trim().isNotEmpty) return plain.trim();
    final html = m.decodeTextHtmlPart();
    if (html != null) return htmlToText(html);
    return '(geen tekstinhoud)';
  }
}

String htmlToText(String html) {
  var s = html
      .replaceAll(RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|tr|h\d|li)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  s = s.replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n');
  return s.trim();
}
