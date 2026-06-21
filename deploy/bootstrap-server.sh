#!/usr/bin/env bash
# ============================================================
#  OgunLearn — Bootstrap serveur Ubuntu 22.04+ / Debian 12+
#  
#  À exécuter UNE SEULE FOIS sur le serveur, en root ou via sudo.
#  
#  Usage sur le serveur :
#    wget https://raw.githubusercontent.com/<TON_REPO>/main/deploy/bootstrap-server.sh
#    sudo bash bootstrap-server.sh
#  
#  Ou en SSH depuis ta machine :
#    scp deploy/bootstrap-server.sh root@ogunlearn.com:/tmp/
#    ssh root@ogunlearn.com 'bash /tmp/bootstrap-server.sh'
# ============================================================
set -euo pipefail

# ---- Configuration ----
DOMAIN="ogunlearn.com"
DEPLOY_USER="deploy"
DEPLOY_PATH="/var/www/ogunlearn"
EMAIL_ADMIN="admin@${DOMAIN}"  # Pour Let's Encrypt

# ---- Couleurs ----
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${BLUE}[bootstrap]${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }

# ---- Vérif root ----
if [[ $EUID -ne 0 ]]; then
  echo "Ce script doit être exécuté en root (ou sudo)"
  exit 1
fi

# ============================================================
# 1. SYSTÈME — mise à jour + paquets
# ============================================================
log "Mise à jour des paquets..."
apt-get update -qq
apt-get upgrade -y -qq

log "Installation des paquets essentiels..."
apt-get install -y -qq \
  nginx \
  ufw \
  fail2ban \
  certbot \
  python3-certbot-nginx \
  curl \
  wget \
  git \
  rsync \
  unattended-upgrades \
  apt-listchanges
ok "Paquets installés"

# ============================================================
# 2. UTILISATEUR DEPLOY (non-root pour les déploiements)
# ============================================================
if ! id "${DEPLOY_USER}" &>/dev/null; then
  log "Création utilisateur ${DEPLOY_USER}..."
  useradd -m -s /bin/bash "${DEPLOY_USER}"
  
  # Permettre sudo sans mot de passe pour reload Nginx uniquement
  cat > "/etc/sudoers.d/${DEPLOY_USER}" <<EOF
${DEPLOY_USER} ALL=(ALL) NOPASSWD: /bin/systemctl reload nginx, /bin/systemctl restart nginx
EOF
  chmod 0440 "/etc/sudoers.d/${DEPLOY_USER}"
  ok "Utilisateur ${DEPLOY_USER} créé avec sudo limité"
else
  ok "Utilisateur ${DEPLOY_USER} existe déjà"
fi

# Préparer SSH pour deploy
mkdir -p "/home/${DEPLOY_USER}/.ssh"
chmod 700 "/home/${DEPLOY_USER}/.ssh"
touch "/home/${DEPLOY_USER}/.ssh/authorized_keys"
chmod 600 "/home/${DEPLOY_USER}/.ssh/authorized_keys"
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "/home/${DEPLOY_USER}/.ssh"

warn "AJOUTE TA CLÉ SSH PUBLIQUE : nano /home/${DEPLOY_USER}/.ssh/authorized_keys"

# ============================================================
# 3. ARBORESCENCE /var/www/ogunlearn
# ============================================================
log "Création de l'arborescence ${DEPLOY_PATH}..."
mkdir -p "${DEPLOY_PATH}/releases"
mkdir -p /var/www/certbot

# Page d'accueil temporaire (le temps du premier déploiement)
mkdir -p "${DEPLOY_PATH}/releases/00000000-initial"
cat > "${DEPLOY_PATH}/releases/00000000-initial/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>OgunLearn — Bientôt disponible</title>
<style>
  body { font-family: system-ui, sans-serif; background: #F5EFE6; color: #1A1A1F; 
         display: grid; place-items: center; min-height: 100vh; margin: 0; }
  div { text-align: center; max-width: 480px; padding: 40px; }
  h1 { font-size: 48px; margin: 0 0 16px; }
  p { color: #6E6E78; }
  span { color: #E85D3C; font-style: italic; }
</style>
</head>
<body>
<div>
  <h1><span>OgunLearn</span></h1>
  <p>Plateforme en cours de déploiement.</p>
</div>
</body>
</html>
EOF

ln -sfn "${DEPLOY_PATH}/releases/00000000-initial" "${DEPLOY_PATH}/current"
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${DEPLOY_PATH}"
chown -R www-data:www-data /var/www/certbot
ok "Arborescence prête : ${DEPLOY_PATH}"

# ============================================================
# 4. FIREWALL UFW
# ============================================================
log "Configuration du firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable
ok "Firewall actif (22, 80, 443)"

# ============================================================
# 5. FAIL2BAN
# ============================================================
log "Configuration fail2ban..."
cat > /etc/fail2ban/jail.d/ogunlearn.local <<EOF
[sshd]
enabled = true
port = ssh
maxretry = 3
bantime = 3600

[nginx-http-auth]
enabled = true

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 10
EOF
systemctl restart fail2ban
ok "fail2ban actif"

# ============================================================
# 6. NGINX — config initiale HTTP (avant SSL)
# ============================================================
log "Configuration Nginx initiale (HTTP, avant SSL)..."

# Désactiver la config par défaut
rm -f /etc/nginx/sites-enabled/default

cat > /etc/nginx/sites-available/ogunlearn.com <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};

    root ${DEPLOY_PATH}/current;
    index index.html;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        try_files \$uri \$uri.html \$uri/ =404;
    }
}
EOF

ln -sfn /etc/nginx/sites-available/ogunlearn.com /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
ok "Nginx HTTP servant ${DEPLOY_PATH}/current"

# ============================================================
# 7. SSL Let's Encrypt
# ============================================================
log "Obtention du certificat SSL Let's Encrypt..."
warn "Assure-toi que les DNS A/AAAA de ${DOMAIN} et www.${DOMAIN} pointent vers ce serveur"
read -p "Les DNS sont-ils configurés ? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  certbot --nginx \
    -d "${DOMAIN}" \
    -d "www.${DOMAIN}" \
    --non-interactive \
    --agree-tos \
    --email "${EMAIL_ADMIN}" \
    --redirect
  ok "SSL actif"
else
  warn "SSL non configuré. Lance plus tard : certbot --nginx -d ${DOMAIN} -d www.${DOMAIN}"
fi

# Renouvellement automatique
log "Configuration du renouvellement SSL auto..."
systemctl enable certbot.timer
systemctl start certbot.timer
ok "Renouvellement SSL automatique"

# ============================================================
# 8. SÉCURITÉ SSH (durcissement)
# ============================================================
log "Durcissement SSH..."
SSH_CONFIG="/etc/ssh/sshd_config.d/99-ogunlearn.conf"
cat > "${SSH_CONFIG}" <<EOF
# Durcissement SSH OgunLearn
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
warn "PasswordAuthentication désactivé. Assure-toi que ta clé SSH est dans /home/${DEPLOY_USER}/.ssh/authorized_keys"
warn "Pour activer ces règles : systemctl restart sshd (à faire MANUELLEMENT après avoir testé)"

# ============================================================
# 9. MISES À JOUR DE SÉCURITÉ AUTOMATIQUES
# ============================================================
log "Activation des mises à jour de sécurité automatiques..."
dpkg-reconfigure -plow unattended-upgrades || true
ok "Unattended-upgrades configuré"

# ============================================================
# 10. RÉCAPITULATIF
# ============================================================
echo
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Bootstrap terminé !${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo "Prochaines étapes :"
echo "  1. Ajoute ta clé SSH publique :"
echo "     nano /home/${DEPLOY_USER}/.ssh/authorized_keys"
echo
echo "  2. Teste la connexion depuis ta machine de dev :"
echo "     ssh ${DEPLOY_USER}@${DOMAIN}"
echo
echo "  3. Active le durcissement SSH (après avoir testé la clé) :"
echo "     systemctl restart sshd"
echo
echo "  4. Depuis ta machine de dev, lance le premier déploiement :"
echo "     DEPLOY_HOST=${DOMAIN} ./deploy/deploy.sh"
echo
echo "  Logs Nginx :"
echo "     /var/log/nginx/ogunlearn.access.log"
echo "     /var/log/nginx/ogunlearn.error.log"
