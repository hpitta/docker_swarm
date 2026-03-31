**Playbook de Implantação – Docker Swarm (3 nós) + Traefik + OCI Load Balancer + BookStack**

_Ambiente corporativo – passo a passo e automação (scripts)_

Data: 13/01/2026

Autor: Hercules

# 1\. Objetivo

Este documento descreve, do zero, como preparar 3 máquinas Linux na Oracle OCI, criar um cluster Docker Swarm com alta disponibilidade, publicar um Traefik como Ingress/Reverse Proxy e disponibilizar aplicações (ex.: BookStack) atrás de um Load Balancer público da OCI. Ao final, você terá um conjunto de scripts para repetir o deploy sem refazer tudo manualmente.

# 2\. Visão geral da arquitetura

- DNS público: culturainglesa.com.br (ex.: bookstack.culturainglesa.com.br).
- OCI Load Balancer (público): termina TLS com certificado wildcard (\*.culturainglesa.com.br).
- Backend do LB: nós do Swarm (ports 80/443 publicados em modo host pelo Traefik).
- Traefik (no Swarm): roteia por Host/Path para as stacks (BookStack, etc.).
- Rede overlay 'traefik_proxy' para as aplicações publicarem seus routers/services via labels.

Observação sobre TLS: como o certificado wildcard ficará no Load Balancer, o caminho mais simples e comum é terminar TLS no LB e encaminhar HTTP para o Traefik (porta 80). Se você quiser criptografia ponta-a-ponta, é possível recriptografar até o Traefik (TLS no Traefik também), mas isso adiciona complexidade e, na prática, o link LB->backend costuma estar em rede controlada (VCN).

# 3\. Pré-requisitos

## 3.1 Infraestrutura (OCI)

- 3 VMs Linux (ex.: Oracle Linux / Rocky / Ubuntu) na mesma VCN/subnet privada.
- IP público apenas via Load Balancer (recomendado).
- Security Lists/NSG liberando do Load Balancer para os nós: TCP 80 e TCP 443 (backend).
- Acesso administrativo (SSH) aos nós.
- File Storage (FSS) opcional para persistir configs (traefik dynamic/, acme/, stacks/).

## 3.2 Sistema operacional

- Hostname e resolução DNS interna ajustados (ou /etc/hosts) entre os nós.
- Sincronismo de horário (chrony/ntpd).
- Usuário com sudo (ou root) para instalação/configuração.
- Portas locais: 2377/tcp (Swarm management), 7946/tcp+udp (gossip), 4789/udp (VXLAN).

## 3.3 Convenções usadas neste playbook

Exemplo de nós (ajuste conforme seu ambiente):

- cidk01 – manager (leader)
- cidk02 – worker
- cidk03 – worker

Caminho de stacks em FSS (ajuste se necessário): /mnt/fss/stacks/

# 4\. Preparação dos nós (do zero)

## 4.1 Atualização e pacotes básicos

Execute em TODOS os nós:

sudo dnf -y update || sudo apt-get update && sudo apt-get -y upgrade  
sudo dnf -y install curl wget jq vim tar unzip git rsync || true  

## 4.2 Ajuste de hostname e hosts

Em cada nó, defina hostname (exemplo):

sudo hostnamectl set-hostname cidk01  

Garanta que os nós se resolvam (exemplo em /etc/hosts):

172.16.13.213 cidk01  
172.16.13.214 cidk02  
172.16.13.215 cidk03  

## 4.3 Instalação do Docker Engine

A forma exata depende da distro. Exemplo para Oracle Linux/RHEL-like (ajuste conforme seu repositório):

sudo dnf -y install dnf-utils  
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo  
sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin  
sudo systemctl enable --now docker  
sudo docker version  

Valide que o Docker iniciou sem erros:

sudo systemctl status docker --no-pager  

## 4.4 Firewall/Security (Swarm)

Se houver firewall local (firewalld/ufw), libere as portas do Swarm. Exemplo firewalld:

sudo firewall-cmd --permanent --add-port=2377/tcp  
sudo firewall-cmd --permanent --add-port=7946/tcp  
sudo firewall-cmd --permanent --add-port=7946/udp  
sudo firewall-cmd --permanent --add-port=4789/udp  
sudo firewall-cmd --permanent --add-port=80/tcp  
sudo firewall-cmd --permanent --add-port=443/tcp  
sudo firewall-cmd --reload  

## 4.5 (Opcional) Montar OCI File Storage (FSS) em /mnt/fss

Se você usa FSS, monte-o em TODOS os nós, no mesmo caminho. Exemplo NFS:

sudo mkdir -p /mnt/fss  
\# Exemplo genérico (ajuste servidor/export):  
\# sudo mount -t nfs -o vers=3,hard,timeo=600,retrans=2 &lt;FSS_IP&gt;:/&lt;export&gt; /mnt/fss  
\# Persistir no /etc/fstab após validar a montagem.  

Crie a estrutura base:

sudo mkdir -p /mnt/fss/stacks/traefik/{dynamic,acme}  
sudo mkdir -p /mnt/fss/stacks/apps  
sudo chmod -R 755 /mnt/fss/stacks  

# 5\. Criação do Swarm

## 5.1 Inicializar Swarm no manager (cidk01)

No cidk01:

sudo docker swarm init --advertise-addr 172.16.13.213  
sudo docker node ls  

Capture o token de join:

sudo docker swarm join-token worker  

## 5.2 Entrar com os workers (cidk02/cidk03)

Nos workers, execute o comando retornado pelo join-token. Exemplo:

sudo docker swarm join --token &lt;TOKEN_WORKER&gt; 172.16.13.213:2377  

## 5.3 Validar cluster

sudo docker node ls  
sudo docker info | egrep -i 'Swarm|NodeID|Is Manager'  

# 6\. Rede overlay para o Traefik e apps

Crie uma rede overlay externa (uma vez, no manager):

sudo docker network create --driver=overlay --attachable traefik_proxy  
sudo docker network ls | grep traefik_proxy  

# 7\. Traefik (Ingress) no Swarm

## 7.1 Arquivos de configuração (dynamic)

Os arquivos abaixo ficam em /mnt/fss/stacks/traefik/dynamic/ e são montados no container em /etc/traefik/dynamic.

1) auth.yml (BasicAuth do dashboard) – gere o hash com htpasswd (bcrypt):

docker run --rm httpd:2-alpine htpasswd -nbB admin '$Info1000$'  
\# Saída exemplo:  
\# admin:$2y$05$YHthyVrWIBLOyAAfKea7JOXxjzWE3vafZnCD8i6o6eZxRBPFqJs8K  

Crie/edite /mnt/fss/stacks/traefik/dynamic/auth.yml:

http:  
middlewares:  
dashboard-auth:  
basicAuth:  
users:  
\- " admin:$2y$05$YHthyVrWIBLOyAAfKea7JOXxjzWE3vafZnCD8i6o6eZxRBPFqJs8K"  

2) dashboard.yml – redirect HTTP->HTTPS e expõe dashboard/api somente em HTTPS com auth:

## http: middlewares: redirect-to-https: redirectScheme: scheme: https permanent: true routers: redirect-web-to-websecure: entryPoints: - web rule: "HostRegexp(\`{host:.+}\`)" middlewares: - redirect-to-https service: noop@internal traefik-dashboard: entryPoints: - websecure rule: "Host(\`traefik.local\`) && (PathPrefix(\`/api\`) || PathPrefix(\`/dashboard\`))" middlewares: - dashboard-auth service: api@internal tls: {} 7.2 stack.yml do Traefik (completo)

Salve como: /mnt/fss/stacks/traefik/stack.yml

version: "3.9"

networks:

proxy:

external: true

name: traefik_proxy

services:

traefik:

image: traefik:latest

networks:

\- proxy

ports:

\# Publicação em modo host para o OCI LB apontar diretamente para os nós

\- target: 80

published: 80

protocol: tcp

mode: host

\- target: 443

published: 443

protocol: tcp

mode: host

volumes:

\- /var/run/docker.sock:/var/run/docker.sock:ro

\- /mnt/fss/stacks/traefik/dynamic:/etc/traefik/dynamic:ro

\- /mnt/fss/stacks/traefik/acme:/acme

command:

\# Providers

\- --providers.swarm=true

\- --providers.swarm.exposedbydefault=false

\- --providers.swarm.endpoint=unix:///var/run/docker.sock

\- --providers.file.directory=/etc/traefik/dynamic

\- --providers.file.watch=true

\# EntryPoints

\- --entrypoints.web.address=:80

\- --entrypoints.websecure.address=:443

\- --entrypoints.websecure.http.tls=true

\# API/Dashboard (exposto via file provider)

\- --api.dashboard=true

\- --api.insecure=false

\# Logs

\- --log.level=INFO

\- --accesslog=true

\# (Opcional) Ping/Healthcheck interno

\- --ping=true

\- --entrypoints.traefik.address=:8080

deploy:

mode: global

placement:

constraints:

\- node.platform.os == linux

restart_policy:

condition: on-failure

update_config:

parallelism: 1

order: stop-first

labels:

\- traefik.enable=false  
<br/>

## 7.3 Deploy do Traefik

No manager (cidk01):

sudo docker stack deploy -c /mnt/fss/stacks/traefik/stack.yml traefik  
sudo docker stack ps traefik --no-trunc  
sudo docker service logs --tail 100 traefik_traefik  

Testes locais (exemplo):

\# HTTP deve redirecionar para HTTPS (308)  
curl -sI -H 'Host: traefik.local' http://127.0.0.1/dashboard/ | egrep -i 'HTTP/|location:'  
<br/>\# Acesso HTTPS com basic auth (exemplo)  
curl -sk -u 'admin:$Info1000$' -H 'Host: traefik.local' https://127.0.0.1/api/rawdata | head  

# 8\. Publicando aplicações no Swarm

## 9.1 Exemplo whoami (teste)

Arquivo whoami.yml (exemplo) – observe que você pode escolher expor via web (80) ou websecure (443).

version: "3.9"  
<br/>networks:  
proxy:  
external: true  
name: traefik_proxy  
<br/>services:  
whoami:  
image: traefik/whoami  
networks:  
\- proxy  
deploy:  
labels:  
\- traefik.enable=true  
\- traefik.http.routers.whoami.rule=Host(\`whoami.local\`)  
\- traefik.http.routers.whoami.entrypoints=websecure  
\- traefik.http.routers.whoami.tls=true  
\- traefik.http.services.whoami.loadbalancer.server.port=80  

Deploy:

sudo docker stack deploy -c /mnt/fss/stacks/traefik/whoami.yml apps  
curl -s -H 'Host: whoami.local' http://127.0.0.1/
