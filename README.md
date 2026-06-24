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
