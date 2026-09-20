#!/usr/bin/env bash
# Aggancia le note (e job/sessioni) al nuovo UUID GoTrue dopo il primo login self-host.
#
# Uso sulla Raspberry:
#   backend/scripts/remap-note-user.sh <vecchio_user_id> <nuovo_user_id>
#
# Il vecchio id e' lo UUID Cloud (sub JWT precedente). Il nuovo e' visibile
# dopo il primo login su auth.drop-prj.xyz (sub del JWT, o colonna auth.users).
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Uso: $0 <vecchio_user_id> <nuovo_user_id>" >&2
  exit 1
fi

OLD_ID="$1"
NEW_ID="$2"
DROP_DIR="${DROP_DIR:-/home/ares/Drop/backend}"
DB="${DROP_DB:-$DROP_DIR/data/drop_backend.db}"

if [[ ! -f "$DB" ]]; then
  echo "Database non trovato: $DB" >&2
  exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 non e' installato (apt install sqlite3)" >&2
  exit 1
fi

echo "Database: $DB"
echo "Remap user_id: $OLD_ID -> $NEW_ID"

sqlite3 "$DB" <<SQL
BEGIN;
UPDATE notes SET user_id = '${NEW_ID//\'/\'\'}' WHERE user_id = '${OLD_ID//\'/\'\'}';
UPDATE upload_jobs SET user_id = '${NEW_ID//\'/\'\'}' WHERE user_id = '${OLD_ID//\'/\'\'}';
UPDATE upload_sessions SET user_id = '${NEW_ID//\'/\'\'}' WHERE user_id = '${OLD_ID//\'/\'\'}';
COMMIT;
SQL

echo "Righe aggiornate:"
sqlite3 "$DB" <<SQL
SELECT 'notes', COUNT(*) FROM notes WHERE user_id = '${NEW_ID//\'/\'\'}'
UNION ALL
SELECT 'upload_jobs', COUNT(*) FROM upload_jobs WHERE user_id = '${NEW_ID//\'/\'\'}'
UNION ALL
SELECT 'upload_sessions', COUNT(*) FROM upload_sessions WHERE user_id = '${NEW_ID//\'/\'\'}';
SQL
