# Monitoring the 3D studio with Grafana — Prometheus metrics, dashboard and alert

Code for module 3 of the “Click by Click” series **Building an agent-ready AI service: the 3D studio**
(also published in French as « Clic par clic » and in German as « Klick für Klick »).

Video: {{video}}

## Goal

A service called by agents never gets tired of being asked: an agent can send dozens of requests
in a row, retry in a loop, or ask for the status of a render every two seconds. This repository
makes the module 2 studio **observable**, to see the load and the health of the service, and to
spot an agent that is too chatty, before the outage:

- the **MCP server** and the **workers** publish Prometheus metrics (`studio/metrics.py`): calls
  per MCP tool, render duration, wait in the queue, results, queue length, renders running,
  distinct users of the hour;
- **no personal data** in the metrics: the user's address is never a label; distinct users are
  counted in Redis (HyperLogLog), only the number goes out;
- **Prometheus** discovers the studio pods through the Kubernetes API (the workers come and go,
  from zero to four) and reads them every five seconds; it is only allowed to list the pods of the
  `studio3d` namespace;
- **Grafana** is provisioned from files, versioned with the code: data source, dashboard and the
  “Studio queue too long” alert (more than five requests waiting for thirty seconds). Nothing is
  set up with the mouse.

## Contents

| File | Role |
|---|---|
| `studio/metrics.py` | **New.** Metrics shared by the server and the workers: counter `studio_requests_total` (label `tool`), histograms `studio_render_duration_seconds` and `studio_wait_seconds`, counter `studio_renders_total` (label `result`: `done`, `error`, `interrupted`), collector that reads Redis when Prometheus comes by (`studio_queue_waiting`, `studio_renders_running`, `studio_users_hour`) |
| `studio/api.py` | Module 2 MCP server, plus: each tool counts its call, distinct users counted in Redis, `/metrics` route (internal to the cluster) |
| `studio/worker.py` | Module 2 worker, plus: metrics page on port 9101, wait measured, timer around the render, result counted |
| `studio/common.py`, `studio/render.py` | Unchanged since module 2 (only the list of Redis keys in the docstring grows) |
| `studio/Dockerfile` | Image `studio3d:3`: the module 2 image, plus the Prometheus client (`prometheus-client==0.26.0`) |
| `k8s-scale.yaml` | Module 2 manifest, plus: image `studio3d:3`, `prometheus.io/scrape` and `prometheus.io/port` annotations on the pods, port `9101` of the workers |
| `observability/k8s.yaml` | `observability` namespace, Prometheus service account and `Role` (list the pods of `studio3d`, nothing else), Prometheus v3.13.4, Grafana 13.2.3, `Ingress` `grafana.localhost` |
| `observability/prometheus.yml` | A single job: discovery of the `studio3d` pods, annotated pods kept, port read from the annotation |
| `observability/grafana/sources.yaml` | Prometheus data source (`uid: prometheus`), not editable |
| `observability/grafana/dashboards.yaml` | Dashboard provider: the JSON files of the folder, changes with the mouse refused |
| `observability/grafana/alerts.yaml` | “Studio queue too long” rule: `max(studio_queue_waiting) > 5` for 30 s, evaluated every 10 s |
| `observability/dashboards/studio3d.json` | `studio3d` dashboard (English titles; `.fr.json` and `.de.json`: French and German, same panels) |
| `observability/deploy.sh` | Files → ConfigMaps, administrator secret, manifest, restart |
| `test/catalog-agent.sh` | Simulates the “catalog agent” of the video: twelve requests, then the status of each one every two seconds |
| `open-webui/` | Identity header of the MCP connection and system prompt of the “Studio 3D” model (unchanged) |
| `.env.example` | Variables to fill in (token, Redis password, Grafana administrator password), without any value |

## Prerequisites

- The scaled studio of **module 2** (repository
  [`clic-par-clic-studio3d-02-echelle`](https://github.com/guilhem-/clic-par-clic-studio3d-02-echelle)):
  Redis, KEDA 2.21, `studio` secret, “Studio 3D” connection in Open WebUI.
- Docker, `kubectl` and a Kubernetes cluster. The video uses **k3d** (cluster `tterm`, Traefik
  published on port 8080 of the machine); `grafana.localhost` resolves to the machine by itself.
- On top of module 2: about 0.2 CPU and 512 MB of memory for Prometheus and Grafana.

## Step-by-step installation

1. **Image** of the studio, with the metrics:

   ```bash
   docker build -t studio3d:3 studio
   k3d image import studio3d:3 -c tterm      # k3d; otherwise, push the image to your registry
   ```

2. **Studio**: the manifest carries the `studio3d:3` image and the Prometheus annotations.

   ```bash
   kubectl apply -f k8s-scale.yaml
   kubectl -n studio3d rollout status deployment/studio-api
   ```

   Check, from a pod of the cluster or through a local access:

   ```bash
   kubectl -n studio3d port-forward svc/studio 8000:8000 &
   curl -s http://127.0.0.1:8000/metrics | grep ^studio_
   ```

3. **Observability.** Copy `.env.example` to `.env`, fill in `GRAFANA_ADMIN` (for example
   `openssl rand -hex 18`), then:

   ```bash
   set -a; . ./.env; set +a
   ./observability/deploy.sh              # en-US by default; fr-FR or de-DE as argument
   ```

   The dashboard opens without an account (anonymous read access):
   `http://grafana.localhost:8080/d/studio3d` (add `?kiosk` for full screen).
   Prometheus stays internal to the cluster; to look at it:
   `kubectl -n observability port-forward svc/prometheus 9090:9090`.

4. **Try it.** With the local access of step 2 and `STUDIO_TOKEN` in the environment:

   ```bash
   ./test/catalog-agent.sh
   ```

   At the same time, ask for three renders from Open WebUI. On the dashboard: the queue jumps,
   KEDA starts the workers, the alert switches to “Pending”, then to “Firing” thirty seconds later;
   the “Requests per MCP tool” panel shows `render_status` called hundreds of times per minute.
   When the queue goes back under five, the alert drops back; about thirty seconds after the last
   render, the workers stop.

## Good to know

- **`max()`, never `sum()`** for the queue: both copies of the server publish the same length,
  read in Redis. The call counters, on the other hand, add up (`sum by (tool)`).
- **Short-lived workers**: Prometheus finds them through the Kubernetes API
  (`kubernetes_sd_configs`); a stopped worker simply disappears from the list. The histograms stay
  readable for five minutes (`rate(…[5m])`).
- **Network rules**: those of module 2 only filter the egress of the studio pods; Prometheus can
  therefore read them. If you add an ingress rule, allow the `observability` namespace.
- **`/metrics`** is published by no `Ingress`: only `/r/…` (signed renders) is.
- **Temporary storage** (`emptyDir`): restarting Prometheus and Grafana resets the curves and the
  alert history. Metrics retention: one day.
- **Notification**: the alert is visible in Grafana; to notify the team (email, chat), add a
  contact point and a notification policy, which can also be provisioned from files.

## For production

These simple manifests are meant to be understood. In production, prefer the
`kube-prometheus-stack` Helm chart (pinned version: Prometheus operator, Alertmanager, cluster
exporters) or a managed service, persistent storage, a suitable retention, and add to the studio a
**quota per user** and a **notification when a render is finished** rather than letting agents
poll in a loop.

## Next in the series

- Previous module: **Scaling up the studio** — repository
  [`clic-par-clic-studio3d-02-echelle`](https://github.com/guilhem-/clic-par-clic-studio3d-02-echelle).
- Next module: **Marking AI-generated renders** (IPTC and XMP metadata, optional visible notice) —
  repository
  [`clic-par-clic-studio3d-04-marquage`](https://github.com/guilhem-/clic-par-clic-studio3d-04-marquage).

## License

MIT, see [`LICENSE`](LICENSE). Blender is distributed under the GPL license by the Blender Foundation;
Redis, KEDA, Prometheus and Grafana are independent projects (Grafana: Grafana Labs). This series is
independent of the publishers of the software shown.
