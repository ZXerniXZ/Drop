# Procedura in caso di violazione dei dati

Cosa fare se note, audio, account o credenziali di Drop sono compromessi o
dispersi. Riferimento: articoli 33 e 34 del Regolamento (UE) 2016/679.

Ultimo aggiornamento: 30 settembre 2026.

Titolare: Federico Navoni, Via Umberto I 47, 24054 Calcio (BG),
navonifederico777@gmail.com.

## Entro le prime ore

1. Isolare: revocare chiavi e password toccate (OpenRouter, Cloudflare, GoTrue
   `JWT_SECRET` / `SERVICE_ROLE_KEY`, SMTP Brevo, account GitHub se il codice
   o i secret sono esposti). Fermare i container se il server è ancora aperto.
2. Conservare le prove: log Docker, log Cloudflare, copia del database se
   ancora integra. Non cancellare i log prima di averli copiati.
3. Capire cosa è uscito: elenco utenti, email, audio, trascrizioni, riassunti,
   token di condivisione, chiavi.

## Entro 72 ore dalla scoperta

Valutare il rischio per le persone: dati di contatto da soli è un rischio
basso; audio e trascrizioni, soprattutto se contengono terze persone o dati
particolari, è un rischio alto.

Se il rischio non è basso, notificare il Garante per la protezione dei dati
personali (https://www.garanteprivacy.it) con:

- quando è accaduto e quando l’hai scoperto
- categorie di dati e numero approssimativo di persone
- conseguenze probabili
- misure già prese e da prendere
- contatto: navonifederico777@gmail.com

Se il rischio è basso, annotare internamente perché non si notifica, e
conservare la nota.

## Avviso alle persone

Se il rischio per gli interessati è alto, avvisarli senza ritardo ingiustificato
all’email dell’account, in linguaggio chiaro: cosa è successo, quali dati, cosa
possono fare (cambiare password, revocare i link di condivisione, cancellare
l’account) e il contatto del titolare.

## Dopo

Cambiare i secret, ricostruire il servizio, aggiornare questo documento se la
procedura non ha retto. Conservare la scheda dell’incidente (data, fatti,
decisioni, date di notifica) almeno tre anni.
