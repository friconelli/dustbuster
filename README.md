# Dustbuster

App macOS (SwiftUI) per liberare spazio su disco: analizza cache e file temporanei, segnala cosa è sicuro eliminare e cosa richiede attenzione, trova file duplicati e mostra lo spazio occupato da Docker.

## Funzionalità

- **Panoramica**: totale spazio liberabile in sicurezza vs. da valutare caso per caso.
- **Categorie analizzate**:
  - Cache applicazioni (`~/Library/Caches`) — sicuro
  - Log applicazioni (`~/Library/Logs`) — sicuro
  - Xcode DerivedData — sicuro
  - Xcode Archives — attenzione (servono per simbolicare i crash di versioni pubblicate)
  - Simulatore iOS: cache (sicuro) e dati dispositivi (attenzione)
  - Cache npm, Yarn, Homebrew, CocoaPods — sicuro
  - Store pnpm — attenzione (va riscaricato, nessuna perdita di dati)
- **Creati dall'AI** (sezione dedicata, viola): temporanei e backup di Claude Code e Codex
  - Claude · lavoro: scratchpad delle sessioni passate (`/private/tmp/claude-<uid>`); quelle modificate nelle ultime 6 ore sono segnalate come in uso e non preselezionate
  - Claude · pre-modifica: copie salvate prima di ogni modifica (`file-history`), servono solo ad annullare
  - Claude · temporanei: snapshot shell, paste-cache, telemetria, debug, backup della configurazione (mai le conversazioni)
  - Codex · cache e immagini generate (queste ultime con livello Attenzione)
  - Backup lasciati dall'AI: cartelle come `_sostituiti`/`_backup` (per intero) e file `.orig_backup*`, `.bak`, `.orig`, `.backup` in Scrivania, Documenti, Download, Film e progetti — Attenzione, mai preselezionati
- **Mappa dello spazio**: vista a blocchi (treemap) di cosa occupa più spazio, con navigazione nelle cartelle e blocchi che compaiono man mano che vengono misurati. Le cartelle con repository git sono bloccate.
- **App e resti**: disinstalla un'app insieme ai file che lascia in `~/Library` (trovati per bundle identifier), oppure cerca i resti di app non più installate (nulla preselezionato).
- **File grandi e vecchi**: file pesanti non aperti da mesi in Scrivania, Documenti, Download, Film, Musica e Immagini, fuori da repository e cartelle di dipendenze.
- **Privacy**: cronologia e cookie di Chrome, Edge, Brave, Arc e Firefox (con avviso se il browser è aperto) e allegati aperti da Mail.
- **Elementi di avvio**: launch agent e daemon di terze parti, con quelli che puntano a programmi non più esistenti in evidenza; si possono disattivare quelli del proprio utente (il file va nel Cestino).
- **Pulizia intelligente**: pulsante in Panoramica che sposta nel Cestino in un colpo solo tutte le categorie "Sicuro", escludendo elementi recenti e repository git, dopo conferma.
- **File duplicati**: trova file con contenuto identico (hash SHA-256) in cartelle a scelta (default: Downloads, Desktop, Documents), tenendo sempre almeno una copia per gruppo.
- **Docker**: mostra `docker system df` senza eliminare nulla in automatico — immagini/volumi possono contenere dati che l'app non può valutare in sicurezza.

## Filosofia di sicurezza

- **I repository git non si toccano**: i duplicati e i backup dell'AI ignorano ogni cartella con `.git` e le cartelle di dipendenze (`node_modules`, `Pods`, `vendor`, `.build`, …). Un controllo finale rifiuta qualunque file dentro un repository anche se arrivasse nella selezione.

- Nessuna eliminazione diretta: tutto viene spostato nel **Cestino** (`FileManager.trashItem`), recuperabile finché non lo svuoti.
- L'unica eliminazione reale e irreversibile è "Svuota Cestino", delegata a Finder via AppleScript (rispetta eventuali conferme di sistema).
- Ogni categoria ha un livello (Sicuro / Attenzione) con spiegazione del perché.
- Docker non viene mai toccato in automatico: solo diagnosi + comando suggerito da copiare.

## Requisiti

- macOS 13+
- Xcode (necessario per compilare: SwiftUI su questo SDK usa macro del compilatore disponibili solo con Xcode, non con le sole Command Line Tools)

Le funzioni sono scritte da zero sulla base del comportamento documentato di strumenti simili; nessun codice di app commerciali è stato analizzato o copiato.

## Linux (Zorin OS, Ubuntu, Debian)

C'è una versione per Linux in `linux/` (Python + GTK 3, nessuna dipendenza da installare a mano). Ha le stesse regole di sicurezza della versione Mac: i repository git non si toccano mai e tutto va nel Cestino. Sezioni: cache e miniature, pip/npm/yarn/pnpm/cargo, **file creati dall'AI** (Claude Code, Codex, cartelle `_sostituiti`/`_backup`, `.orig_backup*`), cronologia e cookie dei browser (Firefox, Chrome, Chromium, Brave, Edge), mappa dello spazio, file grandi e vecchi, duplicati, elementi di avvio (si disattivano con un interruttore, senza eliminare nulla), pulizia intelligente. Non c'è il disinstallatore di app: su Linux è compito di `apt`, Snap e Flatpak.

Installazione (scarica `dustbuster_<versione>_all.deb` dall'ultima release):

```bash
sudo apt install ./dustbuster_1.1.0_all.deb
```

Provato su Ubuntu 22.04 (base di Zorin 17) e 24.04 (Zorin 18). Gli aggiornamenti funzionano come su Mac: l'app controlla le release e, con **Aggiorna e riavvia**, scarica il nuovo `.deb` e lo installa (il sistema chiede la password). Per costruire il pacchetto: `linux/build_deb.sh` (serve Docker o `dpkg-deb`). Per provare l'app su dati finti: `python3 linux/tests/make_fixture.py /tmp/casa` e poi `HOME=/tmp/casa python3 -m dustbuster` da `linux/`. Test: `cd linux && python3 -m unittest discover -s tests`.

## Aggiornamenti

L'app controlla da sola le nuove versioni su GitHub (all'avvio, al massimo ogni 6 ore) e dal menu **Dustbuster › Controlla aggiornamenti…**. Quando ne trova una compare in fondo alla barra laterale il pulsante **Aggiorna e riavvia**: scarica `Dustbuster.zip` dalla release, verifica che sia la stessa app (stesso bundle id e versione attesa), sostituisce la copia in uso, porta la vecchia nel Cestino e si riapre.

Per pubblicare una versione: `Scripts/release.sh 1.1.0 "Novità"` (richiede `gh` e un albero git pulito). L'allegato deve chiamarsi `Dustbuster.zip`.

## Build e installazione

```bash
./Scripts/build_app.sh --install
```

Compila in release, assembla `Dustbuster.app`, lo firma ad-hoc e lo installa in `/Applications`.

## Icona

L'icona attuale (aspirapolvere robot con la polvere) è stata generata con Codex e convertita in `AppIcon.icns`. `Scripts/generate_icon.swift` genera invece la versione vettoriale precedente.

## Rigenerare l'icona (versione vettoriale)

```bash
swift Scripts/generate_icon.swift AppIcon.iconset
iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
```

## Struttura

- `Sources/Dustbuster/` — codice SwiftUI, scanner, duplicate finder
- `Resources/` — `Info.plist` e icona del bundle
- `Scripts/` — build dell'app e generazione icona
