# Home-Automation

This repo is dedicated to my home automation setup , docker files and knowledge.

## Portainer Setup

Run the below on your hardware of choice to deploy portainer.

```
docker run --name portainer --restart=unless-stopped -d -p 8000:8000 -p 9000:9000 -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer
```
Once running connect to the container IP and Port (8000) format `http://IP:PORT` and go through the setup process.

More info: `https://docs.portainer.io/start/install-ce/server/docker/linux`

## Use the service yml files to deploy the stacks in portainer

## Compose file is located 
- demo/ha-compose/docker-compose.yml

## For the demo

## URLS
- http://localhost:3000/?orgId=1&from=now-6h&to=now&timezone=browser
- http://localhost:9090/query
- http://localhost:9093/#/alerts
- http://localhost:9115/
- http://localhost:9798/metrics
- http://localhost:3001/install.html
- http://localhost:8123/onboarding.html
- http://localhost:81/login

