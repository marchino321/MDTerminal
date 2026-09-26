# MD Terminal 1.0 — Vibe Coding Report

## Sintesi

MD Terminal 1.0 è stato sviluppato e rifinito in **2 chat di contesto** tra il 25 e il 26 settembre 2026.

- **Tempo end-to-end verificato:** circa 5 ore e 55 minuti
- **Esecuzione effettiva Codex:** circa 2 ore e 30 minuti
- **Metodo:** sviluppo iterativo human-in-the-loop con build, test e verifica su Mac e iPad reali

Il tempo end-to-end somma le finestre di lavoro e include feedback, prove manuali e attese brevi; le pause superiori a 30 minuti sono escluse. Il tempo Codex somma invece solo le esecuzioni registrate nei due log. I valori sono quindi riproducibili e non stimati a memoria.

## Chat 1 — Prodotto e versione 1.0

La prima chat ha portato il progetto da zero a un client SSH nativo funzionante:

- architettura Swift modulare con core separato dalla UI;
- gestione host, gruppi, preferiti, ricerca e duplicazione;
- password e passphrase protette nel Keychain;
- connessioni SSH reali con password o chiave privata;
- verifica delle host key e gestione `known_hosts`;
- terminale VT100/Xterm basato su SwiftTerm;
- sessioni multiple a schede;
- file manager SFTP locale/remoto;
- snippet di comandi;
- port forwarding;
- import della configurazione `~/.ssh/config`;
- archivio portabile cifrato AES-256-GCM per host e credenziali;
- app macOS compilata in Debug e Release;
- app iPadOS firmata, installata e provata su dispositivo fisico;
- creazione dell'icona ufficiale MD Terminal.

## Chat 2 — UI, stabilità e distribuzione

La seconda chat ha uniformato l'esperienza desktop/iPad e risolto i problemi emersi nell'uso reale:

- palette navy, cyan, verde, fucsia e arancio coerente;
- dashboard macOS ridisegnata con card e filtri gruppo;
- terminale iPad allineato al desktop per sfondo, colori ANSI, cursore, selezione e margini;
- testo predefinito del terminale impostato in verde;
- sessioni SSH persistenti durante il cambio tab;
- eliminazione delle riconnessioni e dell'output duplicato;
- chiusura esplicita della sessione tramite **Chiudi**;
- snippet corretti: viene eseguito il comando, non il nome visualizzato;
- pulsanti **Nuovo** e **Importa** più grandi e visibili;
- asset catalog iOS corretto per mostrare l'icona MD sul dispositivo;
- build finale firmata, installata e avviata su iPad.

## Problemi tecnici risolti

1. **Terminale iPad non completo**
   La console iniziale non gestiva correttamente Backspace, ANSI e tastiera esterna. È stata sostituita con SwiftTerm.

2. **Sessione duplicata al cambio tab**
   La vista SwiftUI ricreava il client SSH. Ogni tab ora mantiene una sessione persistente fino alla chiusura manuale.

3. **Snippet non aggiornati**
   Il comando viene risolto tramite ID al momento del tap, evitando copie obsolete.

4. **Icona placeholder su iPad**
   Il catalogo `iOS.xcassets` non era incluso nella fase Resources. La configurazione XcodeGen è stata corretta e la build incrementata.

5. **Firma iOS bloccata dai metadati Finder**
   La build device è stata spostata nella DerivedData standard di Xcode.

## Sicurezza e condivisione self-hosted

- Password e passphrase restano nel Keychain del dispositivo.
- Host e credenziali possono essere esportati in un archivio cifrato AES-256-GCM.
- L'archivio può essere condiviso, se desiderato, tramite un servizio di storage self-hosted.
- La passphrase dell'archivio non viene memorizzata e va comunicata separatamente.
- Nessuna credenziale o configurazione host personale è inclusa nel repository GitHub.

## Verifiche eseguite

- build macOS Debug e Release;
- 8 test automatici completati senza errori;
- verifica visiva della dashboard e del terminale macOS;
- test delle connessioni e delle funzioni terminale su iPad;
- build iOS arm64 firmata con provisioning Apple Development;
- controllo della firma del bundle iOS;
- verifica di `Assets.car` e delle icone iPad generate;
- installazione e avvio su iPad fisico.

## Stack

- Swift 6
- SwiftUI e AppKit
- SwiftTerm
- SwiftNIO e NIOSSH
- OpenSSH di macOS
- XcodeGen
- Xcode 27

## Risultato

In circa **6 ore complessive distribuite su 2 chat**, il progetto è passato da zero a una versione 1.0 nativa, multipiattaforma, firmata e testata su hardware reale. Il ciclo di vibe coding è stato: richiesta, implementazione, build, prova manuale, screenshot, diagnosi e nuova installazione.
