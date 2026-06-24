# Drop

**Drop** è un assistente AI open-source ispirato a [Plaud Note](https://www.plaud.ai/products/plaud-note): registra l'audio dal microfono dello smartphone, lo invia a un backend self-hosted e restituisce trascrizioni e riassunti generati dall'AI.

Il progetto è pensato per un uso domestico: il server gira su una **Raspberry Pi** in rete locale ed è esposto in modo sicuro tramite **Cloudflare Tunnel**, senza aprire porte sul router.

---

## Obiettivi del progetto

| Obiettivo | Descrizione |
|-----------|-------------|
| **Registrazione continua** | L'app mobile registra audio (formato `.m4a`) e lo invia al backend. |
| **Trascrizione** | Il backend invia l'audio a **OpenRouter** (modello Whisper) per ottenere il testo integrale. |
| **Riassunto AI** | Un LLM via OpenRouter produce riassunti e note strutturate dalle trascrizioni. |
| **Self-hosting** | I file audio restano in `backend/storage/`; metadati SQLite in `backend/data/`. |
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
└─────────────────┘                        │  Backend (FastAPI)       │
                                           │  • Riceve audio          │
                                           │  • storage/ + data/      │
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

1. L'app Flutter registra audio e salva file `.m4a`.
2. Al termine, l'audio viene caricato sul backend via `POST /upload-audio`.
3. Il backend salva il file in `storage/` e invia l'audio a **OpenRouter** (Whisper).
4. Il testo trascritto viene elaborato da un LLM (formattazione interlocutori + riepilogo Markdown).
5. L'app mostra trascrizione formattata e riepilogo nella lista in-app.

---

## Stack tecnologico

| Componente | Tecnologia | Note |
|------------|------------|------|
| **Mobile** | Flutter (Dart) | Registrazione audio, upload HTTP |
| **Backend** | Python 3.11+, FastAPI | API REST, gestione file |
| **Database** | SQLite (`backend/data/`) | Predisposizione per metadati futuri |
| **Container** | Docker + Docker Compose | Deploy riproducibile su PC e Raspberry Pi |
| **AI** | OpenRouter | Whisper per STT, LLM per summarization |
| **Rete** | Cloudflare Tunnel | Esposizione sicura senza port forwarding |
| **Target hardware** | Raspberry Pi | Produzione; sviluppo su PC locale |

---

## Struttura del repository

```
Drop/
├── README.md           # Questo file
├── backend/            # API FastAPI, Docker, volumi persistenti
│   ├── storage/        # File audio caricati (gitignored)
│   └── data/           # Database SQLite (gitignored, tranne .gitkeep)
└── mobile_app/         # Applicazione Flutter
```

---

## Sviluppo locale

### Prerequisiti

- **Git**
- **Docker** e **Docker Compose** (per il backend)
- **Flutter SDK** (per l'app mobile)
- Account **OpenRouter** con API key

### Backend

```bash
cd backend
cp .env.example .env   # configurare OPENROUTER_API_KEY
docker compose up --build
```

L'API è disponibile su `http://localhost:8080`. Documentazione interattiva su `/docs`.

### Mobile App

```bash
cd mobile_app
flutter pub get
flutter run
```

In `mobile_app/lib/main.dart` l'host di sviluppo è configurato per:

| Piattaforma | URL backend |
|-------------|-------------|
| Linux / desktop | `http://localhost:8080` |
| Android emulator | `http://10.0.2.2:8080` |
| Dispositivo fisico | `physicalDeviceBackendHost` (IP LAN del PC, es. `http://192.168.1.100:8080`) |

---

## Deploy su Raspberry Pi

Guida per esporre il backend in produzione tramite **Cloudflare Tunnel** su un dominio privato (es. `https://api.tuodominio.it`).

### Prerequisiti sulla Raspberry

- Raspberry Pi OS (64-bit consigliato) aggiornato
- [Docker](https://docs.docker.com/engine/install/debian/) e Docker Compose plugin
- Account Cloudflare con un dominio gestito
- Chiave API **OpenRouter**

### 1. Clonare il repository

```bash
cd ~
git clone https://github.com/ZXerniXZ/Drop.git
cd Drop/backend
```

### 2. Configurare `.env` di produzione

```bash
cp .env.example .env
nano .env
```

Imposta almeno:

```env
OPENROUTER_API_KEY=sk-or-v1-...
OPENROUTER_LLM_MODEL=google/gemini-2.5-flash
```

> Non committare mai `.env`. Il file è già nel `.gitignore`.

I volumi Docker persistono i dati in percorsi relativi stabili rispetto alla cartella `backend/`:

| Volume host | Percorso container | Contenuto |
|-------------|-------------------|-----------|
| `./storage` | `/app/storage` | File audio `.m4a` |
| `./data` | `/app/data` | Database SQLite |

### 3. Cloudflare Tunnel

Hai due opzioni equivalenti.

#### Opzione A — `cloudflared` nel Docker Compose (consigliata)

1. Accedi a [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) → **Networks** → **Tunnels** → **Create a tunnel**.
2. Scegli **Cloudflared** come connettore e assegna un nome (es. `drop-raspberry`).
3. Nella configurazione del **Public Hostname**:
   - **Subdomain**: `api` (o il sottodominio desiderato)
   - **Domain**: `tuodominio.it`
   - **Service type**: HTTP
   - **URL**: `http://backend:8080` (nome del servizio Docker nella stessa rete Compose)
4. Copia il **Tunnel Token** generato da Cloudflare.
5. Aggiungilo al `.env` sulla Raspberry:

   ```env
   CLOUDFLARE_TUNNEL_TOKEN=eyJhIjoi...
   ```

6. Avvia backend + tunnel:

   ```bash
   docker compose --profile tunnel up -d --build
   ```

#### Opzione B — `cloudflared` installato sulla Raspberry (host)

```bash
# Installazione (Debian / Raspberry Pi OS)
curl -L https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared jammy main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update && sudo apt install cloudflared
```

1. Crea il tunnel dal [dashboard Cloudflare](https://one.dash.cloudflare.com/) come sopra.
2. Per il **Public Hostname**, imposta l'URL del servizio su `http://localhost:8080` (backend in ascolto sulla porta host).
3. Installa il tunnel come servizio di sistema:

   ```bash
   sudo cloudflared service install <TUNNEL_TOKEN>
   sudo systemctl enable --now cloudflared
   ```

4. Avvia solo il backend:

   ```bash
   docker compose up -d --build
   ```

### 4. Verifica

```bash
# Stato container
docker compose ps

# Log backend
docker compose logs -f backend

# Test endpoint pubblico (sostituisci col tuo dominio)
curl -I https://api.tuodominio.it/docs
```

### 5. Configurare l'app mobile per la produzione

In `mobile_app/lib/main.dart`:

1. Commenta il blocco **Sviluppo locale**.
2. Decommenta il blocco **Produzione** e aggiorna il dominio:

   ```dart
   const bool useProductionBackend = true;
   const String productionBackendUrl = 'https://api.tuodominio.it/upload-audio';
   ```

3. Compila e installa l'app:

   ```bash
   cd mobile_app
   flutter build apk   # Android
   # oppure flutter build ios
   ```

### Comandi utili in produzione

```bash
cd ~/Drop/backend

# Avvio in background (solo backend)
docker compose up -d

# Avvio con tunnel Cloudflare
docker compose --profile tunnel up -d

# Aggiornamento dopo git pull
git pull
docker compose up -d --build

# Arresto
docker compose down
```

---

## Convenzioni Git

- **Branch**: `feature/nome`, `bugfix/nome`, `chore/nome` — mai commit diretti su `main`.
- **Commit**: [Conventional Commits](https://www.conventionalcommits.org/) — es. `feat(backend): add audio upload endpoint`.
- **Release**: Semantic Versioning (`MAJOR.MINOR.PATCH`); PR verso `main` al completamento di ogni feature.

---

## Roadmap

- [x] Setup backend FastAPI + Docker
- [x] Integrazione OpenRouter (Whisper + LLM)
- [x] Setup progetto Flutter con registrazione audio
- [x] Upload audio dall'app al backend
- [x] UI per consultare trascrizioni e riassunti
- [ ] Cloudflare Tunnel su Raspberry Pi (documentato, deploy da completare)
- [ ] Schema SQLite e persistenza metadati trascrizioni

---

## Licenza

Da definire.
