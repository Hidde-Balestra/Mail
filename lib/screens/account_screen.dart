import 'package:flutter/material.dart';

import '../models/mail_account.dart';
import '../services/account_store.dart';
import '../services/mail_service.dart';

/// Formulier om een account met custom SMTP (en optioneel IMAP) in te stellen.
class AccountScreen extends StatefulWidget {
  final MailAccount? existing;
  const AccountScreen({super.key, this.existing});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _ServerFields {
  final host = TextEditingController();
  final port = TextEditingController();
  final user = TextEditingController();
  final password = TextEditingController();
  ConnectionSecurity security;

  _ServerFields(this.security, int defaultPort) {
    port.text = '$defaultPort';
  }

  void load(ServerConfig c) {
    host.text = c.host;
    port.text = '${c.port}';
    user.text = c.username;
    password.text = c.password;
    security = c.security;
  }

  ServerConfig build() => ServerConfig(
        host: host.text.trim(),
        port: int.tryParse(port.text.trim()) ?? 0,
        security: security,
        username: user.text.trim(),
        password: password.text,
      );

  void dispose() {
    host.dispose();
    port.dispose();
    user.dispose();
    password.dispose();
  }
}

class _AccountScreenState extends State<AccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _smtp = _ServerFields(ConnectionSecurity.starttls, 587);
  final _imap = _ServerFields(ConnectionSecurity.ssl, 993);
  bool _useImap = false;
  bool _busy = false;
  String? _status;
  bool _statusOk = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.displayName;
      _email.text = e.email;
      _smtp.load(e.smtp);
      if (e.imap != null) {
        _useImap = true;
        _imap.load(e.imap!);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _smtp.dispose();
    _imap.dispose();
    super.dispose();
  }

  MailAccount _buildAccount() => MailAccount(
        id: widget.existing?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        displayName: _name.text.trim(),
        email: _email.text.trim(),
        smtp: _smtp.build(),
        imap: _useImap ? _imap.build() : null,
      );

  Future<void> _test() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _status = 'Verbinding testen...';
      _statusOk = false;
    });
    final account = _buildAccount();
    final service = MailService();
    try {
      await service.testSmtp(account);
      if (account.imap != null) await service.testImap(account.imap!);
      setState(() {
        _status = account.imap != null
            ? 'SMTP en IMAP verbinding geslaagd ✓'
            : 'SMTP verbinding geslaagd ✓';
        _statusOk = true;
      });
    } catch (e) {
      setState(() => _status = describeMailError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final account = _buildAccount();
    await AccountStore().saveAccount(account);
    if (mounted) Navigator.pop(context, account);
  }

  void _autofillFromEmail() {
    // Vul hosts/gebruikersnaam in op basis van het e-mailadres als ze nog leeg zijn.
    final email = _email.text.trim();
    if (!email.contains('@')) return;
    final domain = email.split('@').last;
    if (_smtp.host.text.isEmpty) _smtp.host.text = 'mail.$domain';
    if (_smtp.user.text.isEmpty) _smtp.user.text = email;
    if (_imap.host.text.isEmpty) _imap.host.text = 'mail.$domain';
    if (_imap.user.text.isEmpty) _imap.user.text = email;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Account toevoegen' : 'Account bewerken'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('Algemeen'),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Weergavenaam', hintText: 'Jan Jansen'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            Focus(
              onFocusChange: (f) {
                if (!f) setState(_autofillFromEmail);
              },
              child: TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                    labelText: 'E-mailadres', hintText: 'jij@domein.nl'),
                validator: (v) =>
                    v != null && v.contains('@') ? null : 'Ongeldig e-mailadres',
              ),
            ),
            const SizedBox(height: 24),
            _section('Uitgaande server (SMTP)'),
            ..._serverFields(_smtp, isSmtp: true),
            const SizedBox(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Inkomende mail via IMAP'),
              subtitle: const Text('Optioneel — zonder IMAP kun je alleen versturen'),
              value: _useImap,
              onChanged: (v) => setState(() => _useImap = v),
            ),
            if (_useImap) ..._serverFields(_imap, isSmtp: false),
            const SizedBox(height: 24),
            if (_status != null)
              Card(
                color: _statusOk
                    ? Colors.green.withValues(alpha: 0.15)
                    : Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      if (_busy)
                        const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        Icon(_statusOk ? Icons.check_circle : Icons.error_outline),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_status!)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _test,
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Test verbinding'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.save),
                    label: const Text('Opslaan'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _serverFields(_ServerFields f, {required bool isSmtp}) {
    return [
      TextFormField(
        controller: f.host,
        decoration: InputDecoration(
            labelText: 'Server', hintText: isSmtp ? 'smtp.domein.nl' : 'imap.domein.nl'),
        validator: _required,
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<ConnectionSecurity>(
              initialValue: f.security,
              decoration: const InputDecoration(labelText: 'Beveiliging'),
              items: [
                for (final s in ConnectionSecurity.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (s) {
                if (s == null) return;
                setState(() {
                  f.security = s;
                  f.port.text = '${_defaultPort(s, isSmtp)}';
                });
              },
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: TextFormField(
              controller: f.port,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Poort'),
              validator: (v) {
                final p = int.tryParse(v ?? '');
                return p != null && p > 0 && p < 65536 ? null : 'Ongeldig';
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: f.user,
        decoration: InputDecoration(
          labelText: 'Gebruikersnaam',
          helperText: isSmtp ? 'Leeg laten als de server geen login vereist' : null,
        ),
        validator: isSmtp ? null : _required,
      ),
      const SizedBox(height: 12),
      _PasswordField(controller: f.password),
    ];
  }

  int _defaultPort(ConnectionSecurity s, bool isSmtp) => isSmtp
      ? switch (s) {
          ConnectionSecurity.ssl => 465,
          ConnectionSecurity.starttls => 587,
          ConnectionSecurity.none => 25,
        }
      : switch (s) {
          ConnectionSecurity.ssl => 993,
          ConnectionSecurity.starttls || ConnectionSecurity.none => 143,
        };

  String? _required(String? v) =>
      v == null || v.trim().isEmpty ? 'Verplicht veld' : null;

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

class _PasswordField extends StatefulWidget {
  final TextEditingController controller;
  const _PasswordField({required this.controller});

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        obscureText: _obscure,
        decoration: InputDecoration(
          labelText: 'Wachtwoord',
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      );
}
