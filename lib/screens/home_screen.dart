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

class _HomeScreenState extends State<HomeScreen> {
  final _store = AccountStore();
  final _service = MailService();
  List<MailAccount> _accounts = [];
  MailAccount? _account;
  bool _loadingAccounts = true;

  /// IMAP-mappen van het huidige account (leeg zonder IMAP).
  List<MailFolder> _folders = [];

  /// Geselecteerde map; `null` = lokale lijst "Verzonden" (accounts zonder IMAP).
  MailFolder? _folder;

  List<MimeMessage> _messages = [];
  List<SentMail> _localSent = [];
  bool _loading = false;
  String? _error;

  /// Voorkomt dat een trage oude laadactie een nieuwere overschrijft.
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts({String? selectId}) async {
    final accounts = await _store.loadAccounts();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _loadingAccounts = false;
    });
    if (accounts.isEmpty) {
      setState(() => _account = null);
      return;
    }
    final id = selectId ?? _account?.id;
    _selectAccount(accounts.firstWhere((a) => a.id == id, orElse: () => accounts.first));
  }

  void _selectAccount(MailAccount a) {
    setState(() {
      _account = a;
      _folders = [];
      _folder = null;
      _messages = [];
      _localSent = [];
      _error = null;
    });
    _refresh(reloadFolders: true);
  }

  Future<void> _refresh({bool reloadFolders = true}) async {
    final acc = _account;
    if (acc == null) return;
    final token = ++_loadToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (acc.imap == null) {
        final sent = await _store.loadSent(acc.id);
        if (token == _loadToken && mounted) setState(() => _localSent = sent);
        return;
      }
      if (reloadFolders || _folders.isEmpty) {
        final folders = await _service.listFolders(acc.imap!);
        if (token != _loadToken || !mounted) return;
        setState(() {
          _folders = folders;
          // Huidige map behouden (op pad), anders Inbox.
          _folder = folders.where((f) => f.encodedPath == _folder?.encodedPath).firstOrNull ??
              folders.where((f) => f.role == FolderRole.inbox).firstOrNull ??
              folders.firstOrNull;
        });
      }
      final folder = _folder;
      if (folder == null) return;
      final msgs = await _service.fetchFolder(acc.imap!, folder.encodedPath);
      if (token == _loadToken && mounted) setState(() => _messages = msgs);
    } catch (e) {
      if (token == _loadToken && mounted) setState(() => _error = describeMailError(e));
    } finally {
      if (token == _loadToken && mounted) setState(() => _loading = false);
    }
  }

  void _openFolder(MailFolder f) {
    Navigator.pop(context);
    if (f.encodedPath == _folder?.encodedPath) return;
    setState(() {
      _folder = f;
      _messages = [];
    });
    _refresh(reloadFolders: false);
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
    setState(() => _account = null);
    await _loadAccounts();
  }

  /// Herlaadt opgeslagen accountgegevens (bijv. na aanpassen vanuit het opstelscherm)
  /// zonder mappen en berichten opnieuw op te halen.
  Future<void> _syncAccountData() async {
    final accounts = await _store.loadAccounts();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _account = accounts.where((a) => a.id == _account?.id).firstOrNull ?? _account;
    });
  }

  Future<void> _compose() async {
    final sent = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ComposeScreen(account: _account!)),
    );
    await _syncAccountData();
    if (sent == true && (_folder == null || _folder!.role == FolderRole.sent)) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingAccounts) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_account == null) return _welcome();

    return Scaffold(
      appBar: AppBar(
        title: Text(_folder?.displayName ?? 'Verzonden'),
        actions: [
          IconButton(
            tooltip: 'Vernieuwen',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _refresh,
          ),
        ],
        bottom: _loading && (_messages.isNotEmpty || _localSent.isNotEmpty)
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
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

  static IconData _iconFor(FolderRole role) => switch (role) {
        FolderRole.inbox => Icons.inbox,
        FolderRole.drafts => Icons.drafts_outlined,
        FolderRole.sent => Icons.send_outlined,
        FolderRole.archive => Icons.archive_outlined,
        FolderRole.junk => Icons.report_gmailerrorred,
        FolderRole.trash => Icons.delete_outline,
        FolderRole.other => Icons.folder_outlined,
      };

  Widget _drawer() {
    final acc = _account!;
    final theme = Theme.of(context);
    final firstCustom = _folders.indexWhere((f) => f.role == FolderRole.other);
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
          if (acc.imap == null)
            ListTile(
              leading: const Icon(Icons.send_outlined),
              title: const Text('Verzonden'),
              subtitle: const Text('Lokaal — geen IMAP ingesteld'),
              selected: true,
              onTap: () => Navigator.pop(context),
            )
          else if (_folders.isEmpty)
            const ListTile(
              leading: SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              title: Text('Mappen laden...'),
            ),
          for (var i = 0; i < _folders.length; i++) ...[
            if (i == firstCustom)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('Mappen', style: TextStyle(color: Colors.grey)),
              ),
            ListTile(
              contentPadding: EdgeInsets.only(left: 16.0 + 20 * _folders[i].depth, right: 16),
              leading: Icon(_iconFor(_folders[i].role)),
              title: Text(_folders[i].displayName,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: _folders[i].unseen > 0 && _folders[i].role != FolderRole.trash
                  ? Text('${_folders[i].unseen}',
                      style: TextStyle(
                          color: theme.colorScheme.primary, fontWeight: FontWeight.bold))
                  : null,
              selected: _folders[i].encodedPath == _folder?.encodedPath,
              onTap: () => _openFolder(_folders[i]),
            ),
          ],
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
                if (a.id != acc.id) _selectAccount(a);
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

  Widget _body() {
    final isLocal = _account!.imap == null;
    final empty = isLocal ? _localSent.isEmpty : _messages.isEmpty;
    if (_loading && empty) {
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
    return isLocal ? _localSentList() : _messageList();
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

  Widget _messageList() {
    if (_messages.isEmpty) {
      return _centeredScrollable(Text('${_folder?.displayName ?? 'Deze map'} is leeg'));
    }
    // In Verzonden/Concepten is de ontvanger interessanter dan de afzender.
    final showRecipient =
        _folder?.role == FolderRole.sent || _folder?.role == FolderRole.drafts;
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _messages.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final m = _messages[i];
        final addr = showRecipient ? m.to?.firstOrNull : m.from?.firstOrNull;
        final name = addr?.personalName ?? addr?.email ?? 'Onbekend';
        final unread = !m.isSeen;
        final style = TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.normal);
        return ListTile(
          leading: CircleAvatar(child: Text(name.isEmpty ? '?' : name[0].toUpperCase())),
          title: Text(showRecipient ? 'Aan: $name' : name,
              style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(m.decodeSubject() ?? '(geen onderwerp)',
              style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text(_formatDate(m.decodeDate()), style: const TextStyle(fontSize: 12)),
          onTap: () => _openMessage(m),
        );
      },
    );
  }

  Future<void> _openMessage(MimeMessage m) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MessageScreen(
          account: _account!,
          folder: _folder!,
          folders: _folders,
          header: m,
        ),
      ),
    );
    await _syncAccountData(); // beantwoorden kan de instellingen hebben aangepast
    if (changed == true) {
      _refresh();
    } else if (!m.isSeen) {
      setState(() => m.isSeen = true);
      _refresh(); // ongelezen-tellers bijwerken
    }
  }

  Widget _localSentList() {
    if (_localSent.isEmpty) {
      return _centeredScrollable(const Text('Nog geen verzonden berichten'));
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _localSent.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final m = _localSent[i];
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
