#!/bin/sh
set -e

echo "=== Starting Docker daemon ==="
# Start dockerd in the background using the container's entrypoint script
/usr/local/bin/dockerd-entrypoint.sh &

# Allow some time for the Docker daemon to come up
sleep 10

echo "=== Bootstrapping configuration files ==="
# Ensure the configuration directory exists
mkdir -p /custom-docker-configs

# Create or update config files
touch /custom-docker-configs/prometheus.yml
touch /custom-docker-configs/alert.rules
touch /custom-docker-configs/alertmanager.yml

# Set proper ownership and permissions
chown 1000:1000 /custom-docker-configs/prometheus.yml
chmod 644 /custom-docker-configs/prometheus.yml
chown 1000:1000 /custom-docker-configs/alert.rules
chmod 644 /custom-docker-configs/alert.rules
chown 1000:1000 /custom-docker-configs/alertmanager.yml
chmod 644 /custom-docker-configs/alertmanager.yml
chown -R 65534:65534 /custom-docker-configs/prometheus_data
chmod -R 775 /custom-docker-configs/prometheus_data

echo "=== Writing alert.rules configuration ==="
cat <<'EOF' > /custom-docker-configs/alert.rules
groups:
- name: demo
  rules:

  # Alert for any instance that is unreachable for >5 minutes.
  - alert: service_down
    expr: up == 0
    for: 5m
    labels:
      severity: page
    annotations:
      summary: "Instance {{ $labels.instance }} down"
      description: "{{ $labels.instance }} of job {{ $labels.job }} has been down for more than 2 minutes."

  - alert: high_load
    expr: node_load1 > 2.9
    for: 5m
    labels:
      severity: page
    annotations:
      summary: "Instance {{ $labels.instance }} under high load"
      description: "{{ $labels.instance }} of job {{ $labels.job }} is under high load."

  - alert: HostPhysicalComponentTooHot
    expr: node_hwmon_temp_celsius > 75
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Host physical component too hot (instance {{ $labels.instance }})"
      description: "Physical hardware component too hot\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"

  - alert: HostHighCpuLoad
    expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Host high CPU load (instance {{ $labels.instance }})"
      description: "CPU load is > 80%\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
EOF

echo "=== Writing alertmanager.yml configuration ==="
cat <<'EOF' > /custom-docker-configs/alertmanager.yml
route:
    receiver: 'default'

receivers:
- name: default
  slack_configs:
  - api_url: 'https://hooks.slack.com/services/XXXXXXXXXXXXXXXX'
    username: 'Alertmanager'
    channel: '#alert-manager'
    icon_url: https://lh3.googleusercontent.com/HhuDvidUsvztQYHv2Ah9PU6xTilfcJvlVqYGGJuxK0U0Tygwns5ZdCRhLxE-Bwf4KQ
    send_resolved: true
    title: |-
      [{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}] {{ .CommonLabels.alertname }} for {{ .CommonLabels.job }}
      {{- if gt (len .CommonLabels) (len .GroupLabels) -}}
        {{" "}}(
        {{- with .CommonLabels.Remove .GroupLabels.Names }}
          {{- range $index, $label := .SortedPairs -}}
            {{ if $index }}, {{ end }}
            {{- $label.Name }}="{{ $label.Value -}}"
          {{- end }}
        {{- end -}}
        )
      {{- end }}
    text: >-
      {{ with index .Alerts 0 -}}
        :chart_with_upwards_trend: *<{{ .GeneratorURL }}|Graph>*
        {{- if .Annotations.runbook }}   :notebook: *<{{ .Annotations.runbook }}|Runbook>*{{ end }}
      {{ end }}

      *Alert details*:

      {{ range .Alerts -}}
        *Alert:* {{ .Annotations.title }}{{ if .Labels.severity }} - `{{ .Labels.severity }}`{{ end }}
      *Description:* {{ .Annotations.description }}
      *Details:*
        {{ range .Labels.SortedPairs }} • *{{ .Name }}:* `{{ .Value }}`
        {{ end }}
      {{ end }}
EOF

echo "=== Writing prometheus.yml configuration ==="
cat <<'EOF' > /custom-docker-configs/prometheus.yml
global:
    scrape_interval: 20s
    external_labels:
        monitor: 'prometheus'

alerting:
  alertmanagers:
  - static_configs:
    - targets:
      - localhost:9093

rule_files:
  - "alert.rules"

scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 60s
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'cadvisori'
    scrape_interval: 60s
    static_configs:
      - targets: ['localhost:<PORT>']

  - job_name: 'node-exporter'
    scrape_interval: 60s
    static_configs:
      - targets: ['localhost:<PORT>']

  - job_name: 'win11'
    static_configs:
    - targets: ['localhost:<PORT>']

  - job_name: 'speedtest-exporter'
    scrape_interval: 5m
    scrape_timeout: 90s
    static_configs:
      - targets: ['localhost:<PORT>']

  - job_name: 'blackbox'
    metrics_path: /probe
    scrape_interval: 60s
    params:
      module: [http_2xx]
    static_configs:
      - targets:
        - https://www.google.com/
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: '<SERVER_IP>:<PORT>'
EOF

echo "=== Bootstrapping complete ==="

echo "Starting additional containers via docker-compose..."
docker-compose -p myproject up

