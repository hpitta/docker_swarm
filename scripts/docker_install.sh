#!/bin/bash

# Redireciona logs
exec > >(tee /var/log/user_data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo ">>> INICIANDO CONFIGURACAO COM NFS <<<"

# Recebe as variaveis do Terraform (O Terraform substitui isso antes de rodar)
NFS_IP="${nfs_server_ip}"
NFS_PATH="${nfs_path}"

# Função de Retry (MANTIDA)
function dnf_retry() {
    local retries=10
    local count=0
    local success=0
    until [ $count -ge $retries ]; do
        dnf "$@" && success=1 && break
        count=$((count+1))
        echo ">>> DNF ocupado (Tentativa $count). Aguardando 15s..."
        sleep 15
    done
    if [ $success -eq 0 ]; then echo ">>> ERRO CRITICO DNF"; exit 1; fi
}

# 1. Instalações Básicas + NFS Utils (NOVO)
echo ">>> Instalando pacotes e cliente NFS..."
dnf_retry update -y
dnf_retry install -y dnf-utils zip unzip nfs-utils

# 2. Configuração do Docker (MANTIDO)
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
dnf remove -y runc podman buildah
dnf_retry install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
usermod -aG docker opc

# 3. Montagem do Volume NFS (NOVO)
echo ">>> Configurando montagem NFS em /mnt/swarm_vol..."
mkdir -p /mnt/swarm_vol

# Adiciona no fstab para montar no boot (Persistência)
echo "$NFS_IP:$NFS_PATH /mnt/swarm_vol nfs defaults,_netdev 0 0" >> /etc/fstab

# Monta agora
mount -a
if [ $? -eq 0 ]; then
    echo ">>> SUCESSO: NFS Montado em /mnt/swarm_vol"
    # Ajusta permissões para que o Docker consiga escrever
    chmod 777 /mnt/swarm_vol
else
    echo ">>> ERRO: Falha ao montar NFS. Verifique Security List (Portas 111, 2048-2050)"
fi

# 4. Firewall (MANTIDO + Regras de NFS)
firewall-cmd --zone=public --permanent --add-port=2377/tcp
firewall-cmd --zone=public --permanent --add-port=7946/tcp
firewall-cmd --zone=public --permanent --add-port=7946/udp
firewall-cmd --zone=public --permanent --add-port=4789/udp
firewall-cmd --zone=public --permanent --add-port=80/tcp
firewall-cmd --zone=public --permanent --add-port=443/tcp
# Libera cliente NFS no firewall local
firewall-cmd --permanent --add-service=mountd
firewall-cmd --permanent --add-service=rpc-bind
firewall-cmd --permanent --add-service=nfs
firewall-cmd --reload

echo ">>> CONFIGURACAO CONCLUIDA <<<"
