import 'package:enough_mail/enough_mail.dart' hide MailAccount, ServerConfig;
import 'package:flutter/material.dart';

import '../models/mail_account.dart';
import '../services/account_store.dart';
import '../services/mail_service.dart';

class ComposeScreen extends StatefulWidget {
  final MailAccount account;
  final MimeMessage? replyTo;

  const ComposeScreen({super.key, required this.account, this.replyTo});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _to = TextEditingController();
  final _cc = TextEditingController();
  final _bcc = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  bool _showCc = false;
  bool _sending = false;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    final r = widget.replyTo;
    if (r != null) {
      final sender = (r.replyTo?.isNotEmpty ?? false) ? r.replyTo! : r.from;
      _to.text = sender?.map((a) => a.email).join(', ') ?? '';
      final subj = r.decodeSubject() ?? '';
      _subject.text =
          subj.toLowerCase().startsWith('re:') ? subj : 'Re: $subj';
      final original = r.decodeTextPlainPart() ?? '';
      final fromName = r.from?.firstOrNull?.toString() ?? '';
      final quoted = original.split('\n').map((l) => '> $l').join('\n');
      _body.text = '\n\n$fromName schreef:\n$quoted';
      _body.selection = const TextSelection.collapsed(offset: 0);
    }
  }

  @override
  void dispose() {
    for (final c in [_to, _cc, _bcc, _subject, _body]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _split(String s) => s
      .split(RegExp(r'[,;\s]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  String? _validateList(String? v, {bool required = false}) {
    final list = _split(v ?? '');
    if (required && list.isEmpty) return 'Minimaal één ontvanger';
    final bad = list.where((e) => !_emailRe.hasMatch(e));
    return bad.isEmpty ? null : 'Ongeldig adres: ${bad.first}';
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    if (_subject.text.trim().isEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Geen onderwerp'),
          content: const Text('Wil je dit bericht zonder onderwerp versturen?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuleren')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Versturen')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _sending = true);
    final to = _split(_to.text);
    final cc = _split(_cc.text);
    final bcc = _split(_bcc.text);
    try {
      await MailService().send(
        account: widget.account,
        to: to,
        cc: cc,
        bcc: bcc,
        subject: _subject.text.trim(),
        body: _body.text,
        replyTo: widget.replyTo,
      );
      await AccountStore().addSent(SentMail(
        accountId: widget.account.id,
        to: to,
        cc: cc,
        subject: _subject.text.trim(),
        body: _body.text,
        sentAt: DateTime.now(),
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Bericht verzonden')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(describeMailError(e)),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.replyTo == null ? 'Nieuw bericht' : 'Beantwoorden'),
        actions: [
          IconButton(
            tooltip: 'CC/BCC',
            icon: Icon(_showCc ? Icons.expand_less : Icons.expand_more),
            onPressed: () => setState(() => _showCc = !_showCc),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _sending
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    tooltip: 'Versturen',
                    icon: const Icon(Icons.send),
                    onPressed: _send,
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            _row('Van', Text('${widget.account.displayName} <${widget.account.email}>')),
            _field('Aan', _to, (v) => _validateList(v, required: true)),
            if (_showCc) ...[
              _field('CC', _cc, _validateList),
              _field('BCC', _bcc, _validateList),
            ],
            _field('Onderwerp', _subject, null, isEmail: false),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _body,
                  maxLines: null,
                  expands: true,
                  autofocus: widget.replyTo != null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: 'Schrijf je bericht...',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor))),
        child: Row(children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: child),
        ]),
      );

  Widget _field(String label, TextEditingController c,
          String? Function(String?)? validator,
          {bool isEmail = true}) =>
      _row(
        label,
        TextFormField(
          controller: c,
          validator: validator,
          keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      );
}
