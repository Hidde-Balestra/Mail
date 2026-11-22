import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mail_account.dart';

/// Bewaart accounts in SharedPreferences en wachtwoorden in secure storage
/// (Windows Credential Manager / Android Keystore).
class AccountStore {
  static const _accountsKey = 'accounts';
  static const _sentKey = 'sent_mails';
  static const _maxSent = 200;

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  String _pwKey(String accountId, String kind) => 'pw_${accountId}_$kind';

  Future<List<MailAccount>> loadAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_accountsKey);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List)
        .map((e) => MailAccount.fromJson(e as Map<String, dynamic>))
        .toList();

    final result = <MailAccount>[];
    for (final a in list) {
      final smtpPw = await _secure.read(key: _pwKey(a.id, 'smtp')) ?? '';
      final imapPw = a.imap == null
          ? null
          : await _secure.read(key: _pwKey(a.id, 'imap')) ?? '';
      result.add(a.copyWith(
        smtp: a.smtp.copyWith(password: smtpPw),
        imap: a.imap?.copyWith(password: imapPw),
      ));
    }
    return result;
  }

  Future<void> saveAccount(MailAccount account) async {
    final accounts = await loadAccounts();
    final idx = accounts.indexWhere((a) => a.id == account.id);
    if (idx >= 0) {
      accounts[idx] = account;
    } else {
      accounts.add(account);
    }
    await _secure.write(
        key: _pwKey(account.id, 'smtp'), value: account.smtp.password);
    if (account.imap != null) {
      await _secure.write(
          key: _pwKey(account.id, 'imap'), value: account.imap!.password);
    } else {
      await _secure.delete(key: _pwKey(account.id, 'imap'));
    }
    await _writeAccounts(accounts);
  }

  Future<void> deleteAccount(String id) async {
    final accounts = await loadAccounts()
      ..removeWhere((a) => a.id == id);
    await _secure.delete(key: _pwKey(id, 'smtp'));
    await _secure.delete(key: _pwKey(id, 'imap'));
    await _writeAccounts(accounts);
  }

  Future<void> _writeAccounts(List<MailAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _accountsKey, jsonEncode(accounts.map((a) => a.toJson()).toList()));
  }

  Future<List<SentMail>> loadSent(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sentKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => SentMail.fromJson(e as Map<String, dynamic>))
        .where((m) => m.accountId == accountId)
        .toList()
      ..sort((a, b) => b.sentAt.compareTo(a.sentAt));
  }

  Future<void> addSent(SentMail mail) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sentKey);
    final list = raw == null
        ? <Map<String, dynamic>>[]
        : (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    list.insert(0, mail.toJson());
    if (list.length > _maxSent) list.removeRange(_maxSent, list.length);
    await prefs.setString(_sentKey, jsonEncode(list));
  }
}
