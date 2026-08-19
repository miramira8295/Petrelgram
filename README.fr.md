# Petrelgram

[English](README.md) · [简体中文](README.zh-CN.md) · [Русский](README.ru.md) · **Français**

[![Telegram](https://img.shields.io/badge/Telegram-Rejoindre%20le%20groupe-26A5E4?style=flat&logo=telegram&logoColor=white)](https://t.me/+khkR9mLZyoliODFl)
[![Release](https://img.shields.io/github/v/release/miramira8295/Petrelgram?style=flat)](https://github.com/miramira8295/Petrelgram/releases)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue?style=flat)](LICENSE)

Un **client Telegram non officiel et open source pour HarmonyOS NEXT**, écrit en
ArkTS/ArkUI au-dessus de [TDLib](https://core.telegram.org/tdlib), la
bibliothèque cliente de Telegram, reliée par un pont natif N-API.

## Fonctionnalités

- **Comptes** — connexion par téléphone avec 2FA, plusieurs comptes, bascule et
  déconnexion
- **Liste des discussions** — dossiers, archives, badges non lus, état de la
  connexion en direct
- **Messages** — texte enrichi, photos, albums, vidéos, fichiers, stickers
  (WEBP / TGS / WEBM), émojis personnalisés, réponses, transferts, réactions,
  fils de commentaires, messages épinglés et programmés, sélection multiple
- **Rédaction** — autocomplétion des mentions et commandes, médias, fichiers,
  messages vocaux, musique, position, contacts, sondages, dés
- **Appels** — audio et vidéo 1:1 chiffrés de bout en bout via tgcalls
- **Appels de groupe et directs** — audio multi-participants, caméra et partage
  d'écran, diffusions de chaînes, fenêtre flottante dans l'application
- **Sujets et stories** — listes de sujets de forum avec fils dédiés ; lecteur
  de stories en plein écran
- **Recherche** — recherche globale sur 11 catégories
- **Profils** — utilisateurs, bots, groupes et chaînes ; modification de
  l'avatar, de la bio et du nom d'utilisateur ; carte de visite QR
- **Réglages** — confidentialité et sécurité, notifications, stockage, sessions
  et appareils, dossiers de discussion, économie d'énergie, thème sombre

## Arborescence

```
AppScope/            configuration applicative (nom du paquet, icône)
entry/src/main/ets/
  tdkit/             pont TDLib N-API, client, service d'authentification
  store/             stores immuables + abonnements (discussions, messages, …)
  pages/             pages ArkUI (connexion, liste, discussion, profil, recherche …)
  services/          streaming média, tâches d'arrière-plan des directs, audio
  util/              analyse et formatage (texte enrichi, albums, dates …)
entry/src/main/cpp/  pont natif (libentry.so → libtdjson.so / libtgcalls_ohos.so)
entry/src/test/      tests unitaires (via scripts/run-local-tests.sh)
scripts/             récupération et compilation TDLib/tgcalls, contrôle local
```

## Compilation

### Prérequis

- **DevEco Studio 6.0+** avec son SDK/NDK OpenHarmony intégré
- `curl` et `file` (déjà présents sur macOS/Linux)

### 1. Bibliothèques natives

TDLib et tgcalls sont fournies précompilées dans `entry/libs/arm64-v8a/`
(~50 Mo, non versionnées). `libentry.so` se lie aux deux — **s'il en manque une,
la compilation s'arrête** sur le message ninja
`missing and no known rule to make it`.

**Option A — télécharger les binaires (recommandé) :**

```bash
bash scripts/fetch-libs.sh [tag]   # les deux bibliothèques, depuis les Releases
```

Sans argument, le script résout la dernière release. N'utilisez pas le tag
glissant `tdlib-latest` : son `libtdjson.so` reste à jour, mais son
`libtgcalls_ohos.so` est en retard sur les releases versionnées.

**Option B — compiler depuis les sources (10 à 15 min sur un Mac récent) :**

```bash
# nécessite clang (Xcode CLT), cmake, ninja, gperf, patchelf
export OHOS_NDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony
bash scripts/build-tdlib.sh
bash scripts/build-tgcalls-ohos.sh
```

`build-tdlib.sh` encapsule entièrement
[`ErBWs/tdlib-ohos-build`](https://github.com/ErBWs/tdlib-ohos-build) :
compilation croisée d'OpenSSL (statique, `1_1_1w`) et de TDLib (release
**1.8.65**) pour arm64-v8a, génération préalable des sources du schéma TL sur la
machine hôte (indispensable en compilation croisée), puis normalisation du
SONAME en `libtdjson.so` avec `patchelf` — sans cette dernière étape, le pont
natif échoue à se charger **silencieusement**. Le script est idempotent : on
peut le relancer sans risque.

`build-tgcalls-ohos.sh` télécharge et compile WebRTC au premier lancement, ce
qui est long. Versions figées et limites média actuelles dans
[`scripts/tgcalls/README.md`](scripts/tgcalls/README.md).

### 2. Identifiants de l'API Telegram

TDLib exige vos propres `api_id`/`api_hash` — ce dépôt n'en fournit aucun.

1. Enregistrez une application sur <https://my.telegram.org/apps>.
2. Copiez `entry/src/main/ets/tdkit/ApiCredentials.template.ets` en
   `ApiCredentials.ets` dans le même dossier.
3. Générez les constantes empaquetées et collez les trois valeurs affichées :

   ```bash
   node scripts/gen-creds.mjs <api_id> <api_hash>
   ```

`ApiCredentials.ets` est dans le gitignore — **ne validez jamais de véritables
identifiants** ; en cas de fuite, révoquez-les et régénérez-les immédiatement.
L'empaquetage est de l'obfuscation, pas du chiffrement : il ne fait qu'élever la
barre face à une extraction opportuniste depuis le paquet installé.

### 3. Signature

`signingConfigs` dans `build-profile.json5` est vide. Ouvrez le projet dans
DevEco Studio et utilisez **File > Project Structure > Signing Configs > Support
HarmonyOS Auto-Sign** (compte développeur Huawei requis) pour générer un
certificat de débogage local. Aucun élément de signature ne doit être validé ni
partagé.

### 4. Compiler et lancer

Ouvrez le projet dans DevEco Studio et lancez-le sur un appareil ou un émulateur
HarmonyOS NEXT, ou bien :

```bash
hvigorw assembleHap --no-daemon
```

Contrôle avant validation :

```bash
./scripts/run-local-tests.sh    # doit afficher "LOCAL TESTS: PASS"
```

Le script exécute la vérification i18n avant les tests unitaires : un contrôle
statique qui répond en une seconde ne doit pas attendre deux minutes de
compilation.

## Localisation

Tous les textes de l'interface vivent dans les fichiers de ressources. La langue
source (chinois simplifié) est dans
`entry/src/main/resources/base/element/string.json` ; les traductions vont dans
les dossiers qualifiés par langue (`fr/element/string.json`, etc.), les pluriels
dans `element/plural.json`. Le système fait correspondre la langue de l'appareil
et retombe sur `base`.

**`$r()` ou `str()`.** Tout ce qu'un composant affiche utilise
`$r('app.string.x')` : c'est une `Resource`, que ArkUI réévalue lors d'un
changement de configuration, donc le changement de langue prend effet
immédiatement. `str('x')` renvoie une chaîne ordinaire figée à la compilation —
à réserver aux cas où un `string` est réellement nécessaire : `@State` de type
`string`, champs de modèle, comparaisons, `.join()` et code hors interface. Si
un paramètre `@Builder` provoque un conflit de types, élargissez-le en
`ResourceStr` plutôt que de revenir à `str()` sur l'appelant.

**Une `const` au niveau du module ne peut pas contenir de texte.** Les constantes
sont construites au premier import, avant que la source des chaînes ne soit
prête, ce qui fige la langue à cet instant. Utilisez une fonction
(`fallbackCountries()`, pas `FALLBACK_COUNTRIES`).

**Ne comparez jamais du texte affiché.** `label.substring(0, 2)` ou
`text.includes('Réessayer')` cassent dès le changement de langue ; branchez sur
des champs structurés.

Les chaînes de diagnostic qui n'atteignent que `console.*` ne sont pas
traduites ; annotez-les avec `// i18n-exempt: <raison>`.

```bash
node scripts/i18n-extract.mjs               # textes encore codés en dur, par domaine
node scripts/i18n-extract.mjs --domain util # détails et suggestions de clés
node scripts/i18n-lit.mjs <file>            # littéraux avec numéros de ligne
node scripts/i18n-check.mjs                 # le contrôle (inclus dans run-local-tests.sh)
```

`i18n-check.mjs` vérifie cinq points : chaque clé référencée dans le code existe
dans `base` ; chaque clé de `base` est référencée quelque part ; **aucune source
de gabarit `${` ne subsiste dans une valeur de ressource, et la numérotation des
paramètres est identique d'une langue à l'autre** ; aucune clé orpheline hors de
`base`, et quelles entrées manquent à chaque langue ; **aucun littéral chinois ne
subsiste dans les dossiers déjà couverts**.

Le troisième point a été ajouté après coup : le contrôle, les tests et le
compilateur voient chacun une classe d'erreurs, mais aucun ne voit que la valeur
de `file_downloading` *est* la source du gabarit `${sizeLabel} ·
téléchargement`. Ce genre d'erreur n'apparaît que sur l'appareil.

`MIGRATED` dans `scripts/i18n-config.mjs` couvre désormais tous les dossiers
sources — les nouveaux dossiers doivent y être ajoutés, sinon le contrôle les
ignore silencieusement. Nommage des clés : `<domaine>_<composant>_<sens>`, par
exemple `chat_forward_title`.

## État et avertissement

- En développement actif ; l'interface vise à rester proche du client Android
  officiel.
- Il s'agit d'un client **non officiel**. Utilisez vos propres identifiants API
  et respectez les
  [conditions d'utilisation de l'API Telegram](https://core.telegram.org/api/terms).
- La recherche d'inconnus suit les règles de découvrabilité côté serveur de
  Telegram/TDLib : elle ne trouve généralement que les utilisateurs dotés d'un
  nom d'utilisateur public ou entrant dans le périmètre de recherche du serveur,
  et ne permet pas d'énumérer des numéros de téléphone arbitraires.

## Licence

[Apache License 2.0](LICENSE)
