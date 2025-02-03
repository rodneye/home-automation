## Start grafana, loki , tempo
docker-compose up -d

# start otel test dice app
bash run-test.sh

# Generate traffic
bash generate_traffic.sh
