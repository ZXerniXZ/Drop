# Registro dei trattamenti

Registro interno ai sensi dell’articolo 30 del Regolamento (UE) 2016/679.
Non è un documento per gli utenti: l’informativa pubblica è su
https://app.drop-prj.xyz/privacy/.

Ultimo aggiornamento: 30 settembre 2026.

## Titolare

Federico Navoni  
Via Umberto I 47, 24054 Calcio (BG), Italia  
navonifederico777@gmail.com

Non è nominato un responsabile della protezione dei dati.

## Trattamenti

### Account e accesso

- Finalità: creare e mantenere l’account, autenticare l’utente, inviare l’email di conferma.
- Categorie di interessati: utenti registrati.
- Dati: email; impronta della password; identificativo e email da Google o GitHub se scelti; versione e data di accettazione delle condizioni; versione dell’avviso sulla registrazione.
- Base: esecuzione del contratto (art. 6.1.b).
- Destinatari: server Drop (GoTrue e Postgres sulla Raspberry, Italia); Cloudflare (transito); Brevo (email di conferma); Google o GitHub solo se usati per l’accesso.
- Conservazione: finché l’account esiste.
- Trasferimenti extra-SEE: Cloudflare, e Google o GitHub se scelti, possono trattare dati negli Stati Uniti (Data Privacy Framework o clausole contrattuali tipo).

### Note, audio e testi generati

- Finalità: conservare, trascrivere e riassumere le registrazioni, rispondere in chat sulla nota, applicare la quota audio.
- Categorie di interessati: utenti; eventuali terze persone la cui voce o parole sono nell’audio.
- Dati: file audio, durata, lingua, trascrizione, riassunto, titolo, testi strutturati, secondi fatturati sulla chiave del server. La chat resta sul dispositivo; il testo della chat e la trascrizione sono inviati al modello.
- Base: esecuzione del contratto (art. 6.1.b). Eventuali dati particolari presenti nell’audio sono trattati perché l’utente li invia per ottenere il servizio (art. 9.2.a, in quanto l’invio equivale a un consenso manifesto all’elaborazione di quel contenuto).
- Destinatari: server Drop (FastAPI e SQLite, file in `storage/`, Italia); Cloudflare (transito); OpenRouter (trascrizione, riassunto, chat).
- Conservazione: finché l’utente cancella la nota o l’account. Chat locale: finché cancella la nota o l’account da quel dispositivo.
- Trasferimenti extra-SEE: OpenRouter e Cloudflare, Stati Uniti (Data Privacy Framework o clausole contrattuali tipo).

### Link di condivisione

- Finalità: permettere a chi ha il token di importare una copia della nota.
- Dati: token, identificativo della nota, identificativo del proprietario, data di creazione e di revoca.
- Base: esecuzione del contratto (art. 6.1.b).
- Destinatari: server Drop; chi possiede il link.
- Conservazione: finché il link è revocato o l’account viene cancellato. Le copie già importate restano nell’account di chi le ha prese.

### Sicurezza e rete

- Finalità: far funzionare il sito, il tunnel e contrastare abusi.
- Dati: indirizzo IP e metadati di connessione visti da Cloudflare e dai log del server.
- Base: interesse legittimo (art. 6.1.f) alla sicurezza del servizio.
- Destinatari: Cloudflare; server Drop.
- Conservazione: non oltre 7 giorni. I container Docker tengono un tetto di dimensione sui file di log.
- Trasferimenti extra-SEE: Cloudflare, Stati Uniti.

## Misure

- Accesso alle API con JWT firmati.
- Traffico verso il server tramite tunnel HTTPS Cloudflare, senza porte aperte sul router.
- Password solo come impronta nel sistema di accesso.
- Cancellazione account: note, audio, condivisioni, quota e utente GoTrue.
- Export dei dati del server su richiesta dall’app.

## Destinatari / responsabili

| Soggetto | Ruolo | Dove |
|---|---|---|
| Server Drop (Raspberry) | titolare, infrastruttura propria | Italia |
| Cloudflare | fornitore (rete, hosting PWA, protezione) | UE / Stati Uniti |
| OpenRouter | fornitore (trascrizione e modelli) | Stati Uniti |
| Brevo | fornitore (email transazionali) | UE |
| Google, GitHub | identità, solo se scelti dall’utente | Stati Uniti |
