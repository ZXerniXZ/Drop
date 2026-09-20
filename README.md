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
│  App / PWA      │  ──────────────────►   │  Cloudflare Tunnel       │
│  (Flutter)      │                        │  (Raspberry Pi)          │
│                 │                        └────────────┬─────────────┘
│  • Login        │                                     │
│  • Audio .m4a   │              ┌──────────────────────┼──────────────────┐
│  • Upload       │              ▼                      ▼                  │
└─────────────────┘   auth.drop-prj.xyz        api.drop-prj.xyz            │
                      ┌─────────────────┐    ┌──────────────────────────┐  │
                      │ Caddy :8090     │    │ FastAPI                  │  │
                      │ /auth/v1 →      │    │ JWT HS256 = JWT_SECRET   │  │
                      │ GoTrue          │    │ SQLite note/job          │  │
                      │ Postgres auth   │    │ OpenRouter               │  │
                      └─────────────────┘    └──────────────────────────┘  │
                                                                           │
                                           ┌───────────────────────────────┘
                                           ▼
                                      OpenRouter (Whisper + LLM)
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
| **Auth** | GoTrue + Postgres | Login email, Google, GitHub sulla Pi (`auth.drop-prj.xyz`) |
| **Container** | Docker + Docker Compose | Deploy riproducibile su PC e Raspberry Pi |
| **AI** | OpenRouter | Whisper per STT, LLM per summarization |
| **Rete** | Cloudflare Tunnel | Esposizione sicura senza port forwarding |
| **Target hardware** | Raspberry Pi | Produzione; sviluppo iniziale su PC locale |

---

## Struttura del repository

```
Drop/
├── README.md           # Questo file
├── backend/            # API FastAPI, GoTrue, Caddy, Docker
│   ├── Caddyfile       # Prefisso /auth/v1 verso GoTrue
│   └── data/           # SQLite e Postgres auth (gitignored)
└── mobile_app/         # Applicazione Flutter (APK + PWA)
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

Il workflow aggiorna e avvia il backend da **`~/Drop`** (clone git permanente), non dalla workspace temporanea del runner.

```bash
# Clone iniziale (se non esiste già)
git clone https://github.com/ZXerniXZ/Drop.git ~/Drop
cp backend/.env.example ~/Drop/backend/.env   # poi compila le chiavi
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
| `git fetch` + `git reset --hard origin/main` | Aggiorna `~/Drop` all'ultimo `main` |
| `docker compose up -d --build` in `~/Drop/backend` | Ricostruisce e riavvia il backend |

Verifica manuale dopo un deploy:

```bash
cd ~/Drop/backend
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

## PWA per iPhone (Safari)

La stessa app Flutter è pubblicata come sito installabile su **https://app.drop-prj.xyz**.

iOS non permette la registrazione in background: Drop deve restare aperto e a schermo acceso. L'APK Android continua a usare il foreground service.

### Installazione su iPhone

1. Apri https://app.drop-prj.xyz in **Safari** (non Chrome)
2. Tocca **Condividi**
3. Tocca **Aggiungi a Home**
4. Consenti il microfono alla prima registrazione

### Deploy Cloudflare Pages

Ogni push su `main` che tocca `mobile_app/` esegue `.github/workflows/web-deploy.yml`.

Secret GitHub da configurare:

| Secret | Uso |
|--------|-----|
| `SUPABASE_URL` | già usato per l'APK |
| `SUPABASE_ANON_KEY` | già usato per l'APK |
| `CLOUDFLARE_API_TOKEN` | token con permesso Pages |
| `CLOUDFLARE_ACCOUNT_ID` | account Cloudflare di `drop-prj.xyz` |

Poi nel dashboard Cloudflare Pages, progetto `drop-app`: custom domain **app.drop-prj.xyz**.

### Auth OAuth (self-host)

Login email, Google e GitHub passano da **GoTrue** sulla Raspberry, non da supabase.com. L'app Flutter non cambia: usa `SUPABASE_URL` + `SUPABASE_ANON_KEY` puntati a `https://auth.drop-prj.xyz`.

Redirect URI da registrare su Google Cloud Console e GitHub OAuth App:

`https://auth.drop-prj.xyz/auth/v1/callback`

Dettagli: sezione [Auth self-host sulla Raspberry](#auth-self-host-sulla-raspberry) più sotto.

---

## Resilienza sulla Raspberry Pi

Drop è progettato per ripartire automaticamente dopo **blackout** o **caduta Wi‑Fi**.

### Servizi con avvio automatico

| Servizio | Ruolo | Avvio al boot |
|----------|--------|---------------|
| `docker` | Container backend | `enabled` |
| `cloudflared` | Tunnel Cloudflare | `enabled` + `Restart=always` |
| `drop-backend.service` | `docker compose up -d` | `enabled` |
| `drop-healthcheck.timer` | Controllo ogni 3 min | `enabled` |
| `actions.runner.*` | CI/CD GitHub | `enabled` |

### Installazione (una tantum sulla Pi)

```bash
cd ~/Drop
git pull
sudo backend/scripts/install-raspberry-services.sh
```

Lo script:
- registra `drop-backend.service` (avvia il backend dopo Docker e rete)
- attiva un timer che verifica ogni 3 minuti backend e tunnel
- imposta `Restart=always` su `cloudflared`

### Verifica manuale

```bash
systemctl status drop-backend.service cloudflared drop-healthcheck.timer
docker compose -f ~/Drop/backend/docker-compose.yml ps
curl -I http://localhost:8083/docs
curl -I http://localhost:8090/auth/v1/health
curl -I https://api.drop-prj.xyz/docs
curl -I https://auth.drop-prj.xyz/auth/v1/health
```

### Test reboot

```bash
sudo reboot
# dopo ~2 minuti, da un altro dispositivo:
curl -I https://api.drop-prj.xyz/docs
curl -I https://auth.drop-prj.xyz/auth/v1/health
```

---

## Auth self-host sulla Raspberry

Drop non usa lo stack Supabase completo (Studio, Kong, Realtime, Storage). Sulla Pi restano tre container piccoli: **Postgres** (solo utenti), **GoTrue** (Auth), **Caddy** (prefisso `/auth/v1` che `supabase_flutter` si aspetta). Note e audio restano su FastAPI/SQLite.

### 1. Chiavi JWT (una tantum)

Sulla Raspberry, in `~/Drop/backend`:

```bash
cd ~/Drop/backend
cp .env.example .env   # se manca
python3 scripts/gen-jwt-keys.py
```

Copia `AUTH_POSTGRES_PASSWORD`, `JWT_SECRET`, `SUPABASE_JWT_SECRET` (uguale a `JWT_SECRET`), `ANON_KEY` e `SERVICE_ROLE_KEY` in `.env`. Non committare il file.

Poi:

```bash
docker compose up -d --build
curl -sf http://localhost:8090/auth/v1/health
```

### 2. Tunnel Cloudflare `auth.drop-prj.xyz`

Stesso `cloudflared` già usato per `api.drop-prj.xyz`. Nel dashboard Zero Trust → Tunnels, aggiungi un hostname pubblico:

| Hostname | Service |
|----------|---------|
| `auth.drop-prj.xyz` | `http://localhost:8090` |

Nella zona DNS `drop-prj.xyz` deve comparire il CNAME `auth` verso il tunnel Cloudflare (stesso pattern di `api`).

### 3. Google e GitHub OAuth

I Client ID/secret stanno nella console del provider, non sul progetto Supabase Cloud.

**Google Cloud Console** → APIs & Services → Credentials → OAuth 2.0 Client:

- Authorized JavaScript origins: `https://auth.drop-prj.xyz`, `https://app.drop-prj.xyz`
- Authorized redirect URI: `https://auth.drop-prj.xyz/auth/v1/callback`

**GitHub** → Developer settings → OAuth Apps:

- Homepage URL: `https://app.drop-prj.xyz`
- Authorization callback URL: `https://auth.drop-prj.xyz/auth/v1/callback`

In `~/Drop/backend/.env` sulla Pi:

```
GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID=...
GOTRUE_EXTERNAL_GOOGLE_SECRET=...
GOTRUE_EXTERNAL_GITHUB_CLIENT_ID=...
GOTRUE_EXTERNAL_GITHUB_SECRET=...
```

Poi `docker compose up -d`. Senza questo passo Google/GitHub non chiudono il login. Email/password funziona comunque (`GOTRUE_MAILER_AUTOCONFIRM=true`, niente SMTP).

### 4. Secret GitHub e rebuild app

In GitHub → Settings → Secrets and variables → Actions aggiorna:

| Secret | Valore |
|--------|--------|
| `SUPABASE_URL` | `https://auth.drop-prj.xyz` |
| `SUPABASE_ANON_KEY` | `ANON_KEY` generato al punto 1 |

Poi rebuild APK e PWA (push su `main` o workflow). L'UI di login non cambia.

Redirect ammessi da GoTrue (`GOTRUE_URI_ALLOW_LIST`): PWA `https://app.drop-prj.xyz/**`, localhost, schema mobile `com.drop.plaudclone.drop://**`.

### 5. Account già esistenti (remap `user_id`)

Il `user_id` delle note è lo UUID `sub` del JWT. Al primo login sul GoTrue nuovo l'UUID cambia: le note in SQLite restano agganciate al vecchio id.

Dopo il primo login self-host, sulla Pi (un solo utente = una riga):

```bash
cd ~/Drop/backend
# vecchio UUID Cloud, nuovo UUID da GoTrue (sub del JWT dopo login)
./scripts/remap-note-user.sh '<vecchio-uuid>' '<nuovo-uuid>'
```

Lo script aggiorna `notes`, `upload_jobs` e `upload_sessions`. Non importa gli utenti da supabase.com.

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
