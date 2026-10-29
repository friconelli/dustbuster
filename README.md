# MacCleaner

App macOS (SwiftUI) per liberare spazio su disco: analizza cache e file temporanei, segnala cosa è sicuro eliminare e cosa richiede attenzione, trova file duplicati e mostra lo spazio occupato da Docker.

## Funzionalità

- **Panoramica**: totale spazio liberabile in sicurezza vs. da valutare caso per caso.
- **Categorie analizzate**:
  - Cache applicazioni (`~/Library/Caches`) — sicuro
  - Log applicazioni (`~/Library/Logs`) — sicuro
  - **File di lavoro Claude Code** (`/private/tmp/claude-<uid>`) — scratchpad di sessioni passate, elencate singolarmente; quelle modificate nelle ultime 6 ore sono segnalate come potenzialmente in uso e non pre-selezionate
  - Xcode DerivedData — sicuro
  - Xcode Archives — attenzione (servono per simbolicare i crash di versioni pubblicate)
  - Simulatore iOS: cache (sicuro) e dati dispositivi (attenzione)
  - Cache npm, Yarn, Homebrew, CocoaPods — sicuro
  - Store pnpm — attenzione (va riscaricato, nessuna perdita di dati)
- **File duplicati**: trova file con contenuto identico (hash SHA-256) in cartelle a scelta (default: Downloads, Desktop, Documents), tenendo sempre almeno una copia per gruppo.
- **Docker**: mostra `docker system df` senza eliminare nulla in automatico — immagini/volumi possono contenere dati che l'app non può valutare in sicurezza.

## Filosofia di sicurezza

- Nessuna eliminazione diretta: tutto viene spostato nel **Cestino** (`FileManager.trashItem`), recuperabile finché non lo svuoti.
- L'unica eliminazione reale e irreversibile è "Svuota Cestino", delegata a Finder via AppleScript (rispetta eventuali conferme di sistema).
- Ogni categoria ha un livello (Sicuro / Attenzione) con spiegazione del perché.
- Docker non viene mai toccato in automatico: solo diagnosi + comando suggerito da copiare.

## Requisiti

- macOS 13+
- Xcode (necessario per compilare: SwiftUI su questo SDK usa macro del compilatore disponibili solo con Xcode, non con le sole Command Line Tools)

## Build e installazione

```bash
./Scripts/build_app.sh --install
```

Compila in release, assembla `MacCleaner.app`, lo firma ad-hoc e lo installa in `/Applications`.

## Rigenerare l'icona

```bash
swift Scripts/generate_icon.swift AppIcon.iconset
iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
```

## Struttura

- `Sources/MacCleaner/` — codice SwiftUI, scanner, duplicate finder
- `Resources/` — `Info.plist` e icona del bundle
- `Scripts/` — build dell'app e generazione icona
