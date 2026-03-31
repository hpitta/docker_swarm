# 🐳 Infraestrutura Docker Swarm na Oracle Cloud (OCI)



Este repositório contém o código Terraform e scripts de automação para provisionar um cluster **Docker Swarm** de Alta Disponibilidade na Oracle Cloud Infrastructure (OCI).



## 🏗 Arquitetura



O projeto provisiona 3 máquinas virtuais (Compute Instances) com **IPs fixos** na rede privada, garantindo previsibilidade para o cluster.



| Hostname | IP Privado | Função Sugerida | Shape | SO |

| :--- | :--- | :--- | :--- | :--- |

| **cidk01** | `172.16.13.213` | Manager / Leader | VM.Standard.E5.Flex (1 OCPU, 4GB RAM) | Oracle Linux 9 |

| **cidk02** | `172.16.13.214` | Manager | VM.Standard.E5.Flex (1 OCPU, 4GB RAM) | Oracle Linux 9 |

| **cidk03** | `172.16.13.215` | Manager | VM.Standard.E5.Flex (1 OCPU, 4GB RAM) | Oracle Linux 9 |



> **Nota:** Todos os nós são configurados como **Managers** para garantir tolerância a falhas (HA).



---



## ⚙️ Pré-requisitos



Antes de executar o pipeline, certifique-se de que os seguintes recursos existem no Console da Oracle:



1.  **Compartment:** O ID (OCID) do compartimento onde as máquinas ficarão.

2.  **VCN e Subnet:** A rede virtual e a sub-rede privada configurada.

3.  **Tag Namespace:**

    * Namespace: `Ambiente_Datacenter`

    * Chave (Key): `AMBIENTE`

    * *Sem isso, o Terraform falhará ao tentar aplicar as tags.*



---



## 🔐 Configuração do Bitbucket (Variáveis)



As seguintes variáveis devem ser cadastradas em **Repository settings > Repository variables**:



| Variável | Descrição | Exemplo / Formato |

| :--- | :--- | :--- |

| `TF_VAR_tenancy_ocid` | OCID da sua Tenancy | `ocid1.tenancy.oc1...` |

| `TF_VAR_user_ocid` | OCID do usuário Terraform | `ocid1.user.oc1...` |

| `TF_VAR_fingerprint` | Fingerprint da API Key | `xx:xx:xx...` |

| `TF_VAR_region` | Região da OCI | `sa-saopaulo-1` |

| `TF_VAR_compartment_ocid` | OCID do Compartimento | `ocid1.compartment...` |

| `TF_VAR_subnet_ocid` | OCID da Subnet Privada | `ocid1.subnet...` |

| `TF_VAR_image_ocid` | ID da Imagem Oracle Linux 9 | `ocid1.image...` |

| `TF_VAR_private_key` | Chave Privada API (Base64) | Conteúdo do `.pem` convertido com `base64 -w 0` |

| `TF_VAR_ssh_public_key` | Chaves Públicas SSH | Conteúdo do `.pub`. Recomenda-se colocar a chave do Bastion (linha 1) e a dos Admins (linha 2). |



---



## 🚀 O Script de Automação (`user_data`)



As máquinas utilizam o script `scripts/docker_install.sh` via *Cloud-init* no primeiro boot.



**Principais funcionalidades do script:**

1.  **Instalação Blindada (Anti-Lock):** Utiliza uma função de *Retry* inteligente. Se o processo de atualização automática do Oracle Linux bloquear o `dnf`, o script aguarda e tenta novamente (até 10x), evitando falhas de provisionamento.

2.  **Limpeza:** Remove pacotes conflitantes nativos do Oracle Linux 9 (`podman`, `buildah`, `runc`).

3.  **Firewall:** Abre automaticamente as portas necessárias para o Swarm:

    * `2377/tcp`: Gerenciamento do Cluster.

    * `7946/tcp` e `udp`: Comunicação entre nós.

    * `4789/udp`: Rede Overlay (tráfego dos containers).

4.  **Permissões:** Adiciona o usuário `opc` ao grupo `docker`.



**Logs de Execução:**

Para debugar a instalação, acesse a máquina e verifique o log:

```bash

tail -f /var/log/user_data.log

```



---



## 🛠 Pós-Provisionamento (Configuração do Cluster)



Após o Terraform concluir a criação ("Apply"), o Cluster Swarm deve ser iniciado manualmente. Siga os passos:



### 1. Iniciar o Cluster (No Líder)

Acesse via SSH o nó **cidk01** (`172.16.13.213`) e execute:

```bash

docker swarm init --advertise-addr 172.16.13.213

```

*Copie o comando `docker swarm join --token ...` que será exibido.*



### 2. Adicionar os Nós (Nos Workers)

Acesse **cidk02** e **cidk03** e cole o comando copiado:

```bash

docker swarm join --token SWMTKN-1-xxxxx 172.16.13.213:2377

```



### 3. Promover a Managers (Alta Disponibilidade)

Para garantir HA, volte ao **cidk01** e promova os outros nós a gerentes:

```bash

docker node promote cidk02 cidk03

```



### 4. Verificação Final

Ainda no **cidk01**, verifique se todos estão como `Reachable` ou `Leader`:

```bash

docker node ls

```



---



## 🚨 Troubleshooting & Dicas



### Erro: "Permission denied (publickey)" no primeiro acesso

Se você recriou as máquinas, a "impressão digital" mudou. Limpe o histórico no Bastion:

```bash

ssh-keygen -R 172.16.13.213

ssh-keygen -R 172.16.13.214

ssh-keygen -R 172.16.13.215

```



### Erro de Chave SSH Antiga (RSA/SHA1)

O Oracle Linux 9 tem políticas de segurança rígidas. Se sua chave SSH for antiga e for rejeitada pelo servidor, acesse com uma chave válida (ex: Bastion) e execute na máquina alvo:

```bash

sudo update-crypto-policies --set DEFAULT:SHA1

sudo reboot

```



### Governança e Tags

As instâncias são criadas automaticamente com a seguinte Tag Definida para controle de custos e ambiente:

* **Namespace:** `Ambiente_Datacenter`

* **Chave:** `AMBIENTE`

* **Valor:** `PRODUCAO`



---



### 📝 Comandos Úteis



**Ver logs do Docker:**

```bash

sudo journalctl -u docker -f

```



**Listar serviços rodando no Swarm:**

```bash

docker service ls

```
