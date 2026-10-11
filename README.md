# Observer le studio 3D avec Grafana — mesures Prometheus, tableau de bord et alerte

Code de la démonstration du module 3 de la série « Clic par clic » **Créer un service d'IA
compatible agentique : le studio 3D**.

Vidéo : {{video}}

## But

Un service appelé par des agents ne se fatigue pas d'être sollicité : un agent peut envoyer des
dizaines de demandes d'affilée, réessayer en boucle, ou demander l'état d'un rendu toutes les deux
secondes. Ce dépôt rend le studio du module 2 **observable**, pour voir la charge et la santé du
service, et repérer un agent trop bavard, avant la panne :

- le **serveur MCP** et les **workers** publient des mesures Prometheus (`studio/metriques.py`) :
  appels par outil MCP, durée des rendus, attente dans la file, résultats, longueur de la file,
  rendus en cours, utilisateurs distincts de l'heure ;
- **aucune donnée personnelle** dans les mesures : l'adresse de l'utilisateur n'est jamais une
  étiquette ; les utilisateurs distincts sont comptés dans Redis (HyperLogLog), seul le nombre sort ;
- **Prometheus** découvre les pods du studio par l'API Kubernetes (les workers vont et viennent,
  de zéro à quatre) et les lit toutes les cinq secondes ; il n'a que le droit de lister les pods de
  l'espace `studio3d` ;
- **Grafana** est provisionné par fichiers, versionnés avec le code : source de données, tableau
  de bord et alerte « File du studio trop longue » (plus de cinq demandes en attente pendant
  trente secondes). Rien ne se règle à la souris.

## Contenu

| Fichier | Rôle |
|---|---|
| `studio/metriques.py` | **Nouveau.** Mesures partagées par le serveur et les workers : compteur `studio_demandes_total` (étiquette `outil`), histogrammes `studio_rendu_duree_secondes` et `studio_attente_secondes`, compteur `studio_rendus_total` (étiquette `resultat`), collecteur qui lit Redis au passage de Prometheus (`studio_file_attente`, `studio_rendus_en_cours`, `studio_utilisateurs_heure`) |
| `studio/api.py` | Serveur MCP du module 2, plus : chaque outil compte son appel, utilisateurs distincts comptés dans Redis, route `/metrics` (interne au cluster) |
| `studio/travailleur.py` | Worker du module 2, plus : page des mesures sur le port 9101, attente mesurée, chronomètre autour du rendu, résultat compté |
| `studio/commun.py`, `studio/rendu.py` | Inchangés depuis le module 2 (seule la liste des clés Redis du docstring s'enrichit) |
| `studio/Dockerfile` | Image `studio3d:3` : celle du module 2, plus le client Prometheus (`prometheus-client==0.26.0`) |
| `k8s-echelle.yaml` | Manifeste du module 2, plus : image `studio3d:3`, annotations `prometheus.io/scrape` et `prometheus.io/port` sur les pods, port `9101` des workers |
| `observabilite/k8s.yaml` | Espace `observabilite`, compte de service et `Role` de Prometheus (lister les pods de `studio3d`, rien d'autre), Prometheus v3.13.4, Grafana 13.2.3, `Ingress` `grafana.localhost` |
| `observabilite/prometheus.yml` | Une seule tâche : découverte des pods de `studio3d`, pods annotés gardés, port lu dans l'annotation |
| `observabilite/grafana/sources.yaml` | Source Prometheus (`uid: prometheus`), non modifiable |
| `observabilite/grafana/tableaux.yaml` | Fournisseur de tableaux : les fichiers JSON du dossier, modifications à la souris refusées |
| `observabilite/grafana/alertes.yaml` | Règle « File du studio trop longue » : `max(studio_file_attente) > 5` pendant 30 s, évaluée toutes les 10 s |
| `observabilite/tableaux/studio3d.json` | Tableau de bord `studio3d` (titres en français ; `.en.json` et `.de.json` : anglais et allemand, mêmes panneaux) |
| `observabilite/deployer.sh` | Fichiers → ConfigMaps, secret de l'administrateur, manifeste, redémarrage |
| `essai/agent-catalogue.sh` | Simule l'« agent catalogue » de la vidéo : douze demandes, puis l'état de chacune toutes les deux secondes |
| `open-webui/` | En-tête d'identité de la connexion MCP et prompt système du modèle « Studio 3D » (inchangés) |
| `.env.example` | Variables à renseigner (jeton, mot de passe Redis, mot de passe de l'administrateur de Grafana), sans valeur |

## Prérequis

- Le studio à l'échelle du **module 2** (dépôt
  [`clic-par-clic-studio3d-02-echelle`](https://github.com/guilhem-/clic-par-clic-studio3d-02-echelle)) :
  Redis, KEDA 2.21, secret `studio`, connexion « Studio 3D » dans Open WebUI.
- Docker, `kubectl` et un cluster Kubernetes. La vidéo utilise **k3d** (cluster `tterm`, Traefik
  publié sur le port 8080 de la machine) ; `grafana.localhost` se résout tout seul vers la machine.
- En plus du module 2 : environ 0,2 processeur et 512 Mo de mémoire pour Prometheus et Grafana.

## Installation pas à pas

1. **Image** du studio, avec les mesures :

   ```bash
   docker build -t studio3d:3 studio
   k3d image import studio3d:3 -c tterm      # k3d ; sinon, poussez l'image dans votre registre
   ```

2. **Studio** : le manifeste porte l'image `studio3d:3` et les annotations Prometheus.

   ```bash
   kubectl apply -f k8s-echelle.yaml
   kubectl -n studio3d rollout status deployment/studio-api
   ```

   Contrôle, depuis un pod du cluster ou par un accès local :

   ```bash
   kubectl -n studio3d port-forward svc/studio 8000:8000 &
   curl -s http://127.0.0.1:8000/metrics | grep ^studio_
   ```

3. **Observabilité.** Copiez `.env.example` en `.env`, renseignez `GRAFANA_ADMIN` (par exemple
   `openssl rand -hex 18`), puis :

   ```bash
   set -a; . ./.env; set +a
   ./observabilite/deployer.sh            # fr-FR par défaut ; en-US ou de-DE en argument
   ```

   Le tableau de bord s'ouvre sans compte (lecture anonyme) :
   `http://grafana.localhost:8080/d/studio3d` (ajoutez `?kiosk` pour le plein écran).
   Prometheus reste interne au cluster ; pour le consulter :
   `kubectl -n observabilite port-forward svc/prometheus 9090:9090`.

4. **Essai.** Avec l'accès local de l'étape 2 et `STUDIO_JETON` dans l'environnement :

   ```bash
   ./essai/agent-catalogue.sh
   ```

   En même temps, demandez trois rendus depuis Open WebUI. Sur le tableau de bord : la file bondit,
   KEDA démarre les workers, l'alerte passe à « Pending » puis « Firing » trente secondes plus tard ;
   le panneau « Demandes par outil MCP » montre `etat_rendu` appelé des centaines de fois par minute.
   Quand la file repasse sous cinq, l'alerte retombe ; une trentaine de secondes après le dernier
   rendu, les workers s'arrêtent.

## Points à connaître

- **`max()`, jamais `sum()`** pour la file : les deux copies du serveur publient la même longueur,
  lue dans Redis. Les compteurs d'appels, eux, s'additionnent (`sum by (outil)`).
- **Workers éphémères** : Prometheus les retrouve par l'API Kubernetes (`kubernetes_sd_configs`) ;
  un worker arrêté disparaît simplement de la liste. Les histogrammes restent lisibles cinq minutes
  (`rate(…[5m])`).
- **Règles réseau** : celles du module 2 ne filtrent que la sortie des pods du studio ; Prometheus
  peut donc les lire. Si vous ajoutez une règle d'entrée, autorisez l'espace `observabilite`.
- **`/metrics`** n'est publié par aucun `Ingress` : seuls `/r/…` (rendus signés) le sont.
- **Stockage temporaire** (`emptyDir`) : redémarrer Prometheus et Grafana remet courbes et
  historique d'alerte à zéro. Conservation des mesures : un jour.
- **Notification** : l'alerte est visible dans Grafana ; pour prévenir l'équipe (courriel,
  messagerie), ajoutez un point de contact et une politique de notification, eux aussi provisionnables
  par fichiers.

## Pour la production

Ces manifestes simples servent à comprendre. En production, préférez le chart Helm
`kube-prometheus-stack` (version épinglée : opérateur Prometheus, Alertmanager, exportateurs du
cluster) ou un service géré, un stockage persistant, une conservation adaptée, et ajoutez au studio
un **quota par utilisateur** et une **notification de fin de rendu** plutôt que de laisser les
agents interroger en boucle.

## Suite de la série

- Module précédent : **Passer le studio à l'échelle** — dépôt
  [`clic-par-clic-studio3d-02-echelle`](https://github.com/guilhem-/clic-par-clic-studio3d-02-echelle).
- Module suivant : **Marquer les rendus générés par IA** (métadonnées IPTC et XMP, mention visible
  au choix) — dépôt
  [`clic-par-clic-studio3d-04-marquage`](https://github.com/guilhem-/clic-par-clic-studio3d-04-marquage).

## Licence

MIT, voir [`LICENSE`](LICENSE). Blender est distribué sous licence GPL par la Blender Foundation ;
Redis, KEDA, Prometheus et Grafana sont des projets indépendants (Grafana : Grafana Labs). Cette
série est indépendante des éditeurs des logiciels présentés.
