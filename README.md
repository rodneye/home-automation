# Home-Automation

This repo is dedicated to my home automation setup , docker files and knowledge.

## Portainer Setup
Run the below on your hardware of choice to deploy portainer.

```
docker run --name portainer --restart=unless-stopped -d -p 8000:8000 -p 9000:9000 -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer
```
Once running connect to the container IP and Port (8000) format `http://IP:PORT` and go through the setup process.

More info: `https://docs.portainer.io/start/install-ce/server/docker/linux`

