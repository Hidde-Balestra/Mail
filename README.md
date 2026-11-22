# Mail

Flutter mailclient waarmee je je eigen (custom) SMTP-server koppelt om mail te versturen, met optioneel IMAP om je inbox te lezen.

## Functies
- Meerdere accounts met eigen SMTP (SSL/TLS, STARTTLS of onversleuteld)
- Verbindingstest voordat je opslaat
- Optioneel IMAP: inbox, bericht lezen, beantwoorden, verwijderen
- Wachtwoorden in secure storage (Android Keystore / Windows Credential Manager)
- Lokale lijst van verzonden berichten

## Release
Push een tag `vX.Y.Z`; de workflow bouwt een APK en zet die in een GitHub Release.
