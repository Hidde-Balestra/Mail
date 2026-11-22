import 'package:enough_mail/enough_mail.dart' hide MailAccount, ServerConfig;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/mail_account.dart';
import '../services/account_store.dart';
import '../services/mail_service.dart';
import 'account_screen.dart';
import 'compose_screen.dart';
import 'message_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _Folder { inbox, sent }

class _HomeScreenState extends State<HomeScreen> {
  final _store = AccountStore();
  List<MailAccount> _accounts = [];
  MailAccount? _current;
  _Folder _folder = _Folder.inbox;
  bool _loadingAccounts = true;

  List<MimeMessage> _inbox = [];
  List<SentMail> _sent = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts({String? selectId}) async {
    final accounts = await _store.loadAccounts();
    setState(() {
      _accounts = accounts;
      _current = accounts.isEmpty
          ? null
          : accounts.firstWhere((a) => a.id == (selectId ?? _current?.id),
              orElse: () => accounts.first);
      _loadingAccounts = false;
      if (_current != null && !_current!.canReceive) _folder = _Folder.sent;
    });
    _refresh();
  }

  Future<void> _refresh() async {
    final acc = _current;
    if (acc == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_folder == _Folder.inbox && acc.imap != null) {
        final msgs = await MailService().fetchInbox(acc.imap!);
        if (mounted) setState(() => _inbox = msgs);
      } else {
        final sent = await _store.loadSent(acc.id);
        if (mounted) setState(() => _sent = sent);
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeMailError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addOrEditAccount([MailAccount? existing]) async {
    final result = await Navigator.push<MailAccount>(
      context,
      MaterialPageRoute(builder: (_) => AccountScreen(existing: existing)),
    );
    if (result != null) await _loadAccounts(selectId: result.id);
  }

  Future<void> _deleteAccount(MailAccount a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Account verwijderen?'),
        content: Text('${a.email} en de opgeslagen wachtwoorden worden verwijderd.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuleren')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Verwijderen')),
        ],
      ),
    );
    if (ok != true) return;
    await _store.deleteAccount(a.id);
    setState(() => _current = null);
    await _loadAccounts();
  }

  Future<void> _compose() async {
    final sent = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ComposeScreen(account: _current!)),
    );
    if (sent == true && _folder == _Folder.sent) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingAccounts) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_current == null) return _welcome();

    return Scaffold(
      appBar: AppBar(
        title: Text(_folder == _Folder.inbox ? 'Inbox' : 'Verzonden'),
        actions: [
          IconButton(
            tooltip: 'Vernieuwen',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      drawer: _drawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _compose,
        icon: const Icon(Icons.edit),
        label: const Text('Opstellen'),
      ),
      body: RefreshIndicator(onRefresh: _refresh, child: _body()),
    );
  }

  Widget _welcome() => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mail_outline, size: 80, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text('Welkom', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                const Text('Koppel je eigen SMTP-server om te beginnen.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _addOrEditAccount(),
                  icon: const Icon(Icons.add),
                  label: const Text('Account toevoegen'),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _drawer() {
    final acc = _current!;
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(acc.displayName),
            accountEmail: Text(acc.email),
            currentAccountPicture: CircleAvatar(
              child: Text(acc.displayName.isEmpty ? '?' : acc.displayName[0].toUpperCase()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.inbox),
            title: const Text('Inbox'),
            subtitle: acc.canReceive ? null : const Text('Geen IMAP ingesteld'),
            enabled: acc.canReceive,
            selected: _folder == _Folder.inbox,
            onTap: () => _switchFolder(_Folder.inbox),
          ),
          ListTile(
            leading: const Icon(Icons.send),
            title: const Text('Verzonden'),
            selected: _folder == _Folder.sent,
            onTap: () => _switchFolder(_Folder.sent),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Accounts', style: TextStyle(color: Colors.grey)),
          ),
          for (final a in _accounts)
            ListTile(
              leading: Icon(a.id == acc.id ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text(a.email),
              subtitle: Text('${a.smtp.host}:${a.smtp.port}'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _current = a;
                  _inbox = [];
                  _sent = [];
                  _folder = a.canReceive ? _Folder.inbox : _Folder.sent;
                });
                _refresh();
              },
              trailing: PopupMenuButton<String>(
                onSelected: (v) {
                  Navigator.pop(context);
                  v == 'edit' ? _addOrEditAccount(a) : _deleteAccount(a);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Bewerken')),
                  PopupMenuItem(value: 'delete', child: Text('Verwijderen')),
                ],
              ),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Account toevoegen'),
            onTap: () {
              Navigator.pop(context);
              _addOrEditAccount();
            },
          ),
        ],
      ),
    );
  }

  void _switchFolder(_Folder f) {
    Navigator.pop(context);
    setState(() => _folder = f);
    _refresh();
  }

  Widget _body() {
    if (_loading && (_folder == _Folder.inbox ? _inbox.isEmpty : _sent.isEmpty)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _centeredScrollable(Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _refresh, child: const Text('Opnieuw proberen')),
        ],
      ));
    }
    return _folder == _Folder.inbox ? _inboxList() : _sentList();
  }

  Widget _centeredScrollable(Widget child) => LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: c.maxHeight,
            child: Center(child: Padding(padding: const EdgeInsets.all(24), child: child)),
          ),
        ),
      );

  Widget _inboxList() {
    if (_inbox.isEmpty) return _centeredScrollable(const Text('Inbox is leeg'));
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _inbox.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final m = _inbox[i];
        final from = m.from?.firstOrNull;
        final name = from?.personalName ?? from?.email ?? 'Onbekend';
        final unread = !m.isSeen;
        final style = TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.normal);
        return ListTile(
          leading: CircleAvatar(child: Text(name.isEmpty ? '?' : name[0].toUpperCase())),
          title: Text(name, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(m.decodeSubject() ?? '(geen onderwerp)',
              style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text(_formatDate(m.decodeDate()), style: const TextStyle(fontSize: 12)),
          onTap: () async {
            final deleted = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => MessageScreen(account: _current!, header: m),
              ),
            );
            if (deleted == true) {
              _refresh();
            } else {
              setState(() => m.isSeen = true);
            }
          },
        );
      },
    );
  }

  Widget _sentList() {
    if (_sent.isEmpty) {
      return _centeredScrollable(const Text('Nog geen verzonden berichten'));
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _sent.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final m = _sent[i];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.send, size: 18)),
          title: Text('Aan: ${m.to.join(', ')}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(m.subject.isEmpty ? '(geen onderwerp)' : m.subject,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text(_formatDate(m.sentAt), style: const TextStyle(fontSize: 12)),
          onTap: () => showDialog(
            context: context,
            builder: (c) => AlertDialog(
              title: Text(m.subject.isEmpty ? '(geen onderwerp)' : m.subject),
              content: SingleChildScrollView(
                child: SelectableText(
                  'Aan: ${m.to.join(', ')}\n'
                  '${m.cc.isNotEmpty ? 'CC: ${m.cc.join(', ')}\n' : ''}'
                  '${DateFormat('d MMM yyyy HH:mm').format(m.sentAt)}\n\n${m.body}',
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c), child: const Text('Sluiten')),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    final local = d.toLocal();
    final now = DateTime.now();
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return DateFormat('HH:mm').format(local);
    }
    if (local.year == now.year) return DateFormat('d MMM').format(local);
    return DateFormat('d-M-yyyy').format(local);
  }
}
