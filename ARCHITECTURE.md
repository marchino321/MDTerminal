# Architettura MySSH

## Moduli attuali

- `MySSH`: lifecycle SwiftUI, view, view model e impostazioni macOS.
- `MySSHCore/Models`: modelli persistibili privi di segreti.
- `MySSHCore/Persistence`: storage versionato dietro protocollo, sostituibile in futuro con iCloud.
- `MySSHCore/Security`: password e passphrase nel Keychain macOS.
- `MySSHCore/Services`: casi d'uso e coordinamento tra storage e Keychain.

## Moduli previsti

- `SSH`: OpenSSH di sistema in PTY, autenticazione, host-key policy e forwarding.
- `Terminal`: bridge SwiftUI/AppKit verso SwiftTerm e gestione PTY.
- `Sessions`: actor per sessioni indipendenti e tab multipli.
- `SFTP`: operazioni e trasferimenti cancellabili fuori dal MainActor.
- `KnownHosts`: parser e persistenza compatibile con la verifica dei fingerprint.

L'interfaccia dipende dai servizi, non dalle implementazioni concrete. Networking, filesystem e Keychain non vengono eseguiti sul `MainActor`.

## Piano

1. Completata: shell app, CRUD host, persistenza, Keychain, UI e test core.
2. Completata: SSH reale, autenticazione password/chiave, known_hosts e verifica host key.
3. Completata: SwiftTerm, PTY, input/output, resize, ANSI e TUI.
4. Completata: sessioni e tab indipendenti, keep-alive e chiusura selettiva.
5. Completata per la prima versione: file manager SFTP locale/remoto con drag & drop e operazioni file principali.
6. Completata per la prima versione: snippet salvabili, import `~/.ssh/config` e forwarding locale/remoto/SOCKS.
