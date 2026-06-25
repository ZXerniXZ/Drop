# Drop

**Drop** è un assistente AI open-source ispirato a [Plaud Note](https://www.plaud.ai/products/plaud-note): registra l'audio dal microfono dello smartphone, lo invia a un backend self-hosted e restituisce trascrizioni e riassunti generati dall'AI.

Il progetto è pensato per un uso domestico: il server gira su una **Raspberry Pi** in rete locale ed è esposto in modo sicuro tramite **Cloudflare Tunnel**, senza aprire porte sul router.

---

## Obiettivi del progetto

| Obiettivo | Descrizione |
|-----------|-------------|
| **Registrazione continua** | L'app mobile registra audio in background (formato `.m4a`) e lo invia al backend. |
| **Trascrizione** | Il backend invia l'audio a **OpenRouter** (modello Whisper) per ottenere il testo integrale. |
| **Riassunto AI** | Un LLM via OpenRouter produce riassunti e note strutturate dalle trascrizioni. |
| **Self-hosting** | Tutti i metadati restano su un database SQLite locale; nessun vendor lock-in sullo storage. |
| **Privacy** | Il server è sotto il tuo controllo, raggiungibile solo tramite tunnel crittografato. |

---

## Architettura

```
┌─────────────────┐         HTTPS          ┌──────────────────────────┐
│  Mobile App     │  ──────────────────►   │  Cloudflare Tunnel       │
│  (Flutter)      │                        │  (Raspberry Pi / locale) │
│                 │                        └────────────┬─────────────┘
│  • Registra     │                                     │
│    audio .m4a   │                                     ▼
│  • Upload       │                        ┌──────────────────────────┐
│    background   │                        │  Backend (FastAPI)       │
└─────────────────┘                        │  • Riceve audio          │
                                           │  • SQLite (metadati)     │
                                           │  • OpenRouter API        │
                                           └────────────┬─────────────┘
                                                        │
                                                        ▼
                                           ┌──────────────────────────┐
                                           │  OpenRouter              │
                                           │  • Whisper (trascrizione)│
                                           │  • LLM (riassunti)       │
                                           └──────────────────────────┘
```

### Flusso dati

1. L'app Flutter avvia una registrazione audio in background e salva file `.m4a`.
2. Al termine (o a intervalli), l'audio viene caricato sul backend via API REST.
3. Il backend persiste i metadati (timestamp, durata, stato) in **SQLite**.
4. Il backend invia l'audio a **OpenRouter** per la trascrizione Whisper.
5. Il testo trascritto viene inviato a un LLM per generare riassunti e note.
6. L'app può consultare trascrizioni e riassunti tramite le API del backend.

---

## Stack tecnologico

| Componente | Tecnologia | Note |
|------------|------------|------|
| **Mobile** | Flutter (Dart) | Registrazione audio background, upload HTTP |
| **Backend** | Python 3.12+, FastAPI | API REST, gestione file e job asincroni |
| **Database** | SQLite | Metadati registrazioni, trascrizioni, riassunti |
| **Container** | Docker + Docker Compose | Deploy riproducibile su PC e Raspberry Pi |
| **AI** | OpenRouter | Whisper per STT, LLM per summarization |
| **Rete** | Cloudflare Tunnel | Esposizione sicura senza port forwarding |
| **Target hardware** | Raspberry Pi | Produzione; sviluppo iniziale su PC locale |

---

## Struttura del repository

```
Drop/
├── README.md           # Questo file
├── backend/            # API FastAPI, Docker, SQLite
│   └── data/           # Database SQLite (gitignored)
└── mobile_app/         # Applicazione Flutter
```

---

## Sviluppo locale

### Prerequisiti

- **Git**
- **Docker** e **Docker Compose** (per il backend)
- **Flutter SDK** (per l'app mobile, setup in corso)
- Account **OpenRouter** con API key
- (Opzionale) **cloudflared** per testare il tunnel in locale

### Backend

> Il backend sarà configurato nelle prossime iterazioni. Struttura prevista:

```bash
cd backend
cp .env.example .env   # configurare OPENROUTER_API_KEY
docker compose up --build
```

L'API sarà disponibile su `http://localhost:8000`. La documentazione interattiva sarà su `/docs` (Swagger UI).

### Mobile App

> Il progetto Flutter sarà inizializzato nelle prossime iterazioni.

```bash
cd mobile_app
flutter pub get
flutter run
```

Configurare l'URL del backend nell'app (es. `http://<IP-PC>:8000` in sviluppo, URL del tunnel in produzione).

### Cloudflare Tunnel (produzione su Raspberry Pi)

1. Installare `cloudflared` sulla Raspberry Pi.
2. Creare un tunnel nel dashboard Cloudflare e associarlo al servizio backend (`localhost:8000`).
3. L'app mobile punterà all'URL pubblico del tunnel (es. `https://drop.example.com`).

---

## Setup del CI/CD (Self-Hosted Runner)

Il deploy del backend in produzione è automatizzato tramite **GitHub Actions** con un runner self-hosted installato direttamente sulla Raspberry Pi. Ogni push su `main` esegue il workflow `.github/workflows/backend-deploy.yml`, che ricostruisce e riavvia i container Docker.

### 1. Registrare la Raspberry su GitHub

1. Apri la repository su GitHub → **Settings** → **Actions** → **Runners**.
2. Clicca **New self-hosted runner**.
3. Seleziona **Linux** e architettura **ARM64** (Raspberry Pi 64-bit).
4. Segui i comandi mostrati da GitHub (eseguili **sulla Raspberry**):

```bash
# Esempio — usa i comandi esatti mostrati da GitHub per la tua repo
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-linux-arm64-2.XXX.X.tar.gz -L https://github.com/actions/runner/releases/download/vX.X.X/actions-runner-linux-arm64-2.XXX.X.tar.gz
tar xzf ./actions-runner-linux-arm64-*.tar.gz
./config.sh --url https://github.com/ZXerniXZ/Drop --token <TOKEN_TEMPORANEO>
```

Durante `config.sh`:
- **Runner name**: `raspberry-drop` (o un nome a piacere)
- **Labels**: lascia `self-hosted`, `Linux`, `ARM64`
- **Work folder**: accetta il default (`_work`)

### 2. Installare il runner come servizio di sistema

Sempre nella cartella `~/actions-runner` sulla Raspberry:

```bash
sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status
```

Il runner resterà attivo in background e si riavvierà automaticamente al boot.

Comandi utili:

```bash
sudo ./svc.sh stop      # ferma il runner
sudo ./svc.sh status    # verifica stato
journalctl -u actions.runner.* -f   # log in tempo reale
```

### 3. Prerequisiti sulla Raspberry (una tantum)

Il workflow esegue `docker compose` nella cartella `backend/` della workspace del runner. I file **non** versionati devono essere collegati dalla produzione:

```bash
# Dopo la prima esecuzione del workflow (o preventivamente)
WORKSPACE=~/actions-runner/_work/Drop/Drop/backend
mkdir -p "$WORKSPACE"
ln -sf ~/Drop/backend/.env "$WORKSPACE/.env"
ln -sf ~/Drop/backend/storage "$WORKSPACE/storage"
ln -sf ~/Drop/backend/data "$WORKSPACE/data"
```

Assicurati che:
- Docker e Docker Compose siano installati
- `~/Drop/backend/.env` contenga le chiavi di produzione (`OPENROUTER_API_KEY`, `BACKEND_PORT`, ecc.)
- l'utente del runner (`ares`) sia nel gruppo `docker`

### 4. Come funziona il deploy

| Evento | Azione automatica |
|--------|-------------------|
| Push / merge su `main` | GitHub Actions avvia il job |
| Runner `self-hosted` | Esegue il job sulla Raspberry |
| `actions/checkout@v4` | Scarica l'ultimo codice |
| `docker compose up -d --build` | Ricostruisce e riavvia il backend |

Verifica manuale dopo un deploy:

```bash
cd ~/actions-runner/_work/Drop/Drop/backend
docker compose ps
docker compose logs --tail=30 backend
curl -I http://localhost:8083/docs
```

---

## Installazione app Android (GitHub Releases)

Ogni modifica in `mobile_app/` su `main` compila automaticamente l'APK e lo pubblica come **GitHub Release**.

### Scaricare l'APK sul telefono

Link diretto all'ultima versione:

**https://github.com/ZXerniXZ/Drop/releases/latest/download/drop-release.apk**

1. Apri il link dal **browser** del telefono (Chrome/Firefox)
2. Scarica `drop-release.apk`
3. Abilita **Installa app sconosciute** per il browser se richiesto
4. Apri il file scaricato e installa

Tutte le release: https://github.com/ZXerniXZ/Drop/releases

> Incrementa `version:` in `mobile_app/pubspec.yaml` (es. `1.0.0+5`) prima di ogni nuova release, così il tag GitHub resta univoco.

---

## Convenzioni Git

- **Branch**: `feature/nome`, `bugfix/nome`, `chore/nome` — mai commit diretti su `main`.
- **Commit**: [Conventional Commits](https://www.conventionalcommits.org/) — es. `feat(backend): add audio upload endpoint`.
- **Release**: Semantic Versioning (`MAJOR.MINOR.PATCH`); PR verso `main` al completamento di ogni feature.

---

## Roadmap

- [ ] Setup backend FastAPI + Docker
- [ ] Schema SQLite e API upload audio
- [ ] Integrazione OpenRouter (Whisper + LLM)
- [ ] Setup progetto Flutter con registrazione background
- [ ] Upload audio dall'app al backend
- [ ] Cloudflare Tunnel su Raspberry Pi
- [ ] UI per consultare trascrizioni e riassunti

---

## Licenza

Da definire.
