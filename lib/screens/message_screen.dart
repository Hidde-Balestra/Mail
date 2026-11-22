import 'package:enough_mail/enough_mail.dart' hide MailAccount, ServerConfig;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/mail_account.dart';
import '../services/mail_service.dart';
import 'compose_screen.dart';

/// Toont één bericht uit een IMAP-map.
class MessageScreen extends StatefulWidget {
  final MailAccount account;
  final MailFolder folder;
  final List<MailFolder> folders;
  final MimeMessage header;

  const MessageScreen({
    super.key,
    required this.account,
    required this.folder,
    required this.folders,
    required this.header,
  });

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
      final m = await MailService()
          .fetchFull(widget.account.imap!, widget.folder.encodedPath, uid);
      if (mounted) setState(() => _message = m);
    } catch (e) {
      if (mounted) setState(() => _error = describeMailError(e));
    }
  }

  bool get _hasTrash => widget.folders.any((f) => f.role == FolderRole.trash);

  Future<void> _delete() async {
    final permanent = widget.folder.role == FolderRole.trash || !_hasTrash;
    if (permanent) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Definitief verwijderen?'),
          content: const Text('Het bericht wordt definitief van de server verwijderd.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuleren')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Verwijderen')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    await _run(
      () => MailService().deleteMessage(
          widget.account.imap!, widget.folder.encodedPath, widget.header.uid!),
      permanent ? 'Bericht verwijderd' : 'Verplaatst naar Prullenbak',
    );
  }

  Future<void> _move() async {
    final targets =
        widget.folders.where((f) => f.encodedPath != widget.folder.encodedPath).toList();
    final target = await showModalBottomSheet<MailFolder>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Verplaatsen naar', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              for (final f in targets)
                ListTile(
                  contentPadding: EdgeInsets.only(left: 16.0 + 20 * f.depth, right: 16),
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(f.displayName),
                  onTap: () => Navigator.pop(c, f),
                ),
            ],
          ),
        ),
      ),
    );
    if (target == null || !mounted) return;
    await _run(
      () => MailService().moveMessage(widget.account.imap!, widget.folder.encodedPath,
          widget.header.uid!, target.encodedPath),
      'Verplaatst naar ${target.displayName}',
    );
  }

  /// Voert een actie uit, toont feedback en sluit het scherm bij succes.
  Future<void> _run(Future<Object?> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeMailError(e))));
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
          if (widget.folders.length > 1)
            IconButton(
              tooltip: 'Verplaatsen',
              icon: const Icon(Icons.drive_file_move_outline),
              onPressed: widget.header.uid == null ? null : _move,
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
