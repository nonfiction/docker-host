init: data network

data:
	mkdir -p /work
	mkdir -p /data/traefik
	mkdir -p /data/portainer
	touch /data/traefik/traefik.yml
	touch /data/traefik/acme.json
	chmod 600 /data/traefik/acme.json

network:
	docker network create --driver=overlay proxy

deploy: 
	docker stack deploy -c traefik.yml nf
	docker stack deploy -c hello-world.yml nf
	docker stack deploy -c portainer.yml nf
	docker stack deploy -c workspace.yml nf
