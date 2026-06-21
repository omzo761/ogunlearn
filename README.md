# OgunLearn — Landing & Plateforme

> La forge des défenseurs cyber africains.

Site officiel d'**OgunLearn** (https://ogunlearn.com), école de cybersécurité pour les entreprises africaines. Initiative du groupe **OgunSec**.

---

## 🏗️ Stack technique

- **Framework** : [Astro 4](https://astro.build/) — SSG (Static Site Generation), 0 JS par défaut
- **Styling** : CSS pur + design tokens centralisés
- **Typographie** : Fraunces (display), Inter (body), JetBrains Mono (code)
- **Hébergement cible** : VPS Linux + Nginx + Let's Encrypt
- **Stratégie de déploiement** : releases datées + symlink (zero-downtime)

**Performance attendue** : Lighthouse 100/100/100/100, bundle < 50 ko.

---

## 📁 Structure du projet

```
ogunlearn/
├── astro.config.mjs          Configuration Astro (site, intégrations, build)
├── package.json
├── public/                   Assets servis tels quels
│   ├── favicon.svg
│   └── robots.txt
├── src/
│   ├── pages/
│   │   └── index.astro       Page d'accueil (assemblage des sections)
│   ├── components/           Composants réutilisables (1 par section)
│   │   ├── TopBar.astro
│   │   ├── Nav.astro
│   │   ├── Logo.astro
│   │   ├── Hero.astro
│   │   ├── LogosCarousel.astro
│   │   ├── SectionWhy.astro
│   │   ├── SectionFormations.astro
│   │   ├── SectionProfiles.astro
│   │   ├── SectionMentors.astro
│   │   ├── SectionQuote.astro
│   │   ├── SectionCareers.astro
│   │   ├── SectionSchool.astro
│   │   ├── SectionFunding.astro
│   │   └── Footer.astro
│   ├── layouts/
│   │   └── Layout.astro      Shell HTML (meta, OG, fonts)
│   └── styles/
│       ├── tokens.css        🎯 SOURCE DE VÉRITÉ des couleurs/typo/etc.
│       └── global.css        Reset + composants de base
└── deploy/
    ├── bootstrap-server.sh   Setup serveur initial (à lancer 1 fois)
    ├── deploy.sh             Déploiement (à lancer à chaque release)
    └── nginx.conf            Config Nginx production complète
```

---

## 🚀 Démarrage rapide (développement local)

```bash
# Installer les dépendances
npm install

# Lancer le serveur de dev
npm run dev
# → http://localhost:4321

# Build production (génère dist/)
npm run build

# Prévisualiser le build
npm run preview
```

---

## 🌐 Déploiement en production

### Étape 1 — Bootstrap serveur (une seule fois)

Depuis ton serveur VPS (root) :

```bash
# Upload le script bootstrap
scp deploy/bootstrap-server.sh root@ogunlearn.com:/tmp/

# Exécution
ssh root@ogunlearn.com 'bash /tmp/bootstrap-server.sh'
```

Le script :
1. Installe Nginx, UFW, fail2ban, certbot
2. Crée l'utilisateur `deploy` avec sudo limité (reload Nginx seulement)
3. Prépare `/var/www/ogunlearn/{releases,current}`
4. Configure le firewall (22/80/443 uniquement)
5. Obtient un certificat SSL Let's Encrypt
6. Durcit la config SSH

⚠️ **Avant de lancer** : vérifie que les DNS A/AAAA de `ogunlearn.com` et `www.ogunlearn.com` pointent bien vers ton VPS.

⚠️ **Après le bootstrap** : ajoute ta clé SSH publique dans `/home/deploy/.ssh/authorized_keys`, puis active le durcissement SSH avec `systemctl restart sshd`.

### Étape 2 — Activer la config Nginx complète

```bash
# Copie la config Nginx complète
scp deploy/nginx.conf deploy@ogunlearn.com:/tmp/
ssh deploy@ogunlearn.com 'sudo mv /tmp/nginx.conf /etc/nginx/sites-available/ogunlearn.com'
ssh deploy@ogunlearn.com 'sudo nginx -t && sudo systemctl reload nginx'
```

### Étape 3 — Déploiement (à chaque release)

Depuis ta machine de dev :

```bash
# Variables d'environnement (à mettre dans ton .bashrc/.zshrc)
export DEPLOY_HOST=ogunlearn.com
export DEPLOY_USER=deploy

# Déploiement
./deploy/deploy.sh
# ou
npm run deploy
```

Le script :
1. Build local (`npm run build` → `dist/`)
2. Crée une release datée : `/var/www/ogunlearn/releases/20260601-143052/`
3. Upload via rsync
4. Bascule atomique du symlink `current/`
5. Reload Nginx
6. Conserve 5 dernières releases (rollback facile)
7. Smoke test (HTTP 200 ?)

### Rollback en urgence

```bash
ssh deploy@ogunlearn.com
cd /var/www/ogunlearn
ls releases/                                       # voir les versions dispo
ln -sfn releases/20260601-120000 current.new       # pointer vers une version antérieure
mv -Tf current.new current
sudo systemctl reload nginx
```

---

## 🎨 Design system

**Tous les tokens visuels sont dans un seul fichier** : `src/styles/tokens.css`.

```css
:root {
  /* Surfaces */
  --paper: #F5EFE6;       /* fond principal */
  --card:  #FFFFFF;
  
  /* Encre */
  --ink:      #1A1A1F;
  --ink-mute: #6E6E78;
  
  /* Signature */
  --coral: #E85D3C;       /* couleur primaire */
  --indigo: #1E2A4A;
  --gold:   #D4A647;
  
  /* Typo */
  --font-display: 'Fraunces', serif;
  --font-body:    'Inter', sans-serif;
  --font-mono:    'JetBrains Mono', monospace;
}
```

**Pour changer la charte** : modifie uniquement ce fichier, tout le site suit.

---

## 🛣️ Roadmap

### Phase 1 — Landing (actuel)
- [x] Page d'accueil
- [ ] Page formations (catalogue détaillé)
- [ ] Pages parcours individuels (1 par formation)
- [ ] Page mentors
- [ ] Page financement
- [ ] Blog (MDX)
- [ ] Page contact + formulaire

### Phase 2 — Plateforme LMS (Q3 2026)
- [ ] Déploiement **Open edX** sur sous-domaine `app.ogunlearn.com`
- [ ] Thème OgunLearn appliqué à Open edX
- [ ] SSO entre landing et plateforme
- [ ] Paiement Stripe (CB, mobile money via Wave/Orange Money)
- [ ] Espace RSSI entreprise (dashboard équipe)
- [ ] Certificats PDF générés à la volée

### Phase 3 — Expansion (2027)
- [ ] Application mobile (React Native)
- [ ] Marketplace de cours tiers
- [ ] API publique pour intégrations RH

---

## 🔒 Sécurité

OgunLearn vend de la cybersécurité. Le site DOIT être exemplaire :

- ✅ HTTPS forcé partout (HSTS preload activé)
- ✅ Headers de sécurité stricts (CSP, X-Frame-Options, etc.)
- ✅ Pas de tracker tiers en dehors de Plausible Analytics (privacy-friendly)
- ✅ SSH par clé uniquement
- ✅ Firewall UFW + fail2ban
- ✅ Mises à jour automatiques (unattended-upgrades)
- ✅ Pas de password en clair, jamais

**Pentest interne** prévu avant lancement public.

---

## 📞 Contact technique

- **Domaine** : ogunlearn.com (IONOS)
- **Hébergement** : à définir (recommandé : OVH Performance, Scaleway, ou Hetzner)
- **DNS** : à configurer chez IONOS
- **Email** : admin@ogunlearn.com

---

## 📄 Licence

Propriétaire — Tous droits réservés OgunSec © 2026.
