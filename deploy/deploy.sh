#!/usr/bin/env bash
# ============================================================
#  OgunLearn — Script de déploiement zero-downtime
#  
#  Usage local (depuis ta machine de dev) :
#    DEPLOY_HOST=ogunlearn.com DEPLOY_USER=deploy ./deploy/deploy.sh
#  
#  Stratégie : releases datées + symlink "current"
#  Permet rollback rapide en cas de problème.
# ============================================================
set -euo pipefail

# ---- Configuration ----
DEPLOY_HOST="${DEPLOY_HOST:-ogunlearn.com}"
DEPLOY_USER="${DEPLOY_USER:-deploy}"
DEPLOY_PATH="${DEPLOY_PATH:-/var/www/ogunlearn}"
KEEP_RELEASES="${KEEP_RELEASES:-5}"

# ---- Couleurs ----
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()   { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
err()   { echo -e "${RED}✗${NC} $*" >&2; }

# ---- Vérifications préalables ----
[[ -d "node_modules" ]] || { err "node_modules absent. Lance d'abord : npm install"; exit 1; }
command -v rsync >/dev/null || { err "rsync n'est pas installé"; exit 1; }
command -v ssh >/dev/null || { err "ssh n'est pas installé"; exit 1; }

# ---- Build local ----
log "Build de production..."
npm run build
[[ -d "dist" ]] || { err "dist/ absent après build"; exit 1; }
ok "Build terminé ($(du -sh dist | cut -f1))"

# ---- Préparation de la release ----
RELEASE_NAME="$(date +%Y%m%d-%H%M%S)"
RELEASE_PATH="${DEPLOY_PATH}/releases/${RELEASE_NAME}"

log "Création de la release distante : ${RELEASE_NAME}"
ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "
  set -e
  mkdir -p '${DEPLOY_PATH}/releases'
  mkdir -p '${RELEASE_PATH}'
"

# ---- Upload ----
log "Upload des fichiers..."
rsync -avz --delete \
  --exclude='.DS_Store' \
  --exclude='*.map' \
  dist/ \
  "${DEPLOY_USER}@${DEPLOY_HOST}:${RELEASE_PATH}/"

ok "Upload terminé"

# ---- Bascule du symlink ----
log "Bascule du symlink current → ${RELEASE_NAME}"
ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "
  set -e
  cd '${DEPLOY_PATH}'
  ln -sfn 'releases/${RELEASE_NAME}' current.new
  mv -Tf current.new current
"
ok "Symlink mis à jour"

# ---- Nettoyage anciennes releases ----
log "Conservation des ${KEEP_RELEASES} dernières releases..."
ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "
  cd '${DEPLOY_PATH}/releases'
  ls -1t | tail -n +$((KEEP_RELEASES + 1)) | xargs -r rm -rf
"

# ---- Reload Nginx (sans interruption) ----
log "Reload Nginx..."
ssh "${DEPLOY_USER}@${DEPLOY_HOST}" "sudo systemctl reload nginx" || {
  warn "Reload Nginx requiert sudo. Configure NOPASSWD pour 'systemctl reload nginx' dans /etc/sudoers.d/"
}

# ---- Smoke test ----
log "Test de la production..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://${DEPLOY_HOST}/" || echo "000")
if [[ "${HTTP_CODE}" == "200" ]]; then
  ok "Production OK (HTTP ${HTTP_CODE})"
else
  err "La production renvoie HTTP ${HTTP_CODE}"
  warn "Pour rollback : ssh ${DEPLOY_USER}@${DEPLOY_HOST} 'cd ${DEPLOY_PATH} && ln -sfn releases/<PREV> current'"
  exit 1
fi

echo
ok "Déploiement terminé : https://${DEPLOY_HOST}"
echo "  Release : ${RELEASE_NAME}"
echo "  Path    : ${RELEASE_PATH}"
