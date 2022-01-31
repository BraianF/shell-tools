#!/bin/bash
# 
# backup-db-dominio.sh - Realiza o backup do banco de dados do sistema domínio
# 
# Autor:        Braian Antoniolli <braian@embracore.com.br>
# 
# -----------------------------------------------------------------------------
# Este programa realiza o backup do banco de dados do sistema domínio
# na pasta /backup_dominio.
# 
# Para evitar encher o armazenamento, backups antigos são removidos
# 
# Por padrão, o programa busca o banco de dados em 
# /opt/sybase/SYBSsa16/instalacao.txt.
# -----------------------------------------------------------------------------
# 
# 
# Histórico
# 
#   v1.0    2022-01-28, Braian Antoniolli:
#       - Versão inicial 
#   v2.0    2022-01-31, Braian Antoniolli:
#       - Adicionada função de envio para outro servidor através do Rsync
#       - Removido os "exits"
# 

### CHAVES
# 0 = DESLIGADO --- 1 = LIGADO
envia_para_storage="0"



### VARIAVEIS
pasta_backup="/backup_dominio/"
dias_armazenamento="30"

ip_storage=''
porta_storage=''
pasta_storage=''



### FUNCOES
function para_database () {
  echo 'Terminando a execução do banco de dados'
  systemctl stop sisdominio.service
  sleep 10
}


function rotaciona_pasta_backup () {
  echo "Limpando arquivos de backup com mais de ${dias_armazenamento} dias"
  find "$pasta_backup" -type f -mtime +${dias_armazenamento} -exec rm -rf {} \;
  echo "Limpeza concluída"
}


function compacta_arquivos () {
  while read -r instalacao; do
    echo "Efetuando o backup do banco de dados: $instalacao"
    pasta="${instalacao%/[cC]ontabil.db}"
    tar -zcvf "${pasta_backup}/dados_$(date +"%d-%m-%Y_%s").tar.gz" "$pasta" #  > /dev/null 2>&1
  done < /opt/sybase/SYBSsa16/instalacao.txt
  echo 'Backup efetuado com sucesso!'
  
  rotaciona_pasta_backup # Funcao
  [[ "$envia_para_storage" -eq 1 ]] && envia_para_storage # Funcao
}


function envia_para_storage () {
  if testa_conexao_ssh $ip_storage $porta_storage ; then
    rsync -avhPu --delete -e "ssh -p $porta_storage" "$pasta_backup/" root@"${ip_storage}:${pasta_storage}/"
    verificar_retorno "$?"
  fi
}


function testa_conexao_ssh(){
  local endereco_ip="$1"
  local porta_ssh="$2"
  echp "Testando conexão com o storage"
	# Comando retorna 0 (sucesso) caso consiga se conectar e outro valor caso não consiga
	# Como só quero o código de retorno, mando todo o resto pro seu null
	ssh -q -o StrictHostKeyChecking=no -o PubkeyAuthentication=yes -o PasswordAuthentication=no -o ConnectTimeout=10 -p "${porta_ssh}" root@"${endereco_ip}" "ls >/dev/null </dev/null"
	 # shellcheck disable=SC2181
  if [ $? -eq 0 ] ;then
		echo "Conexao com o storage, de IP $endereco_ip funcional. Prosseguindo."
		return 0
	else
		log "Não foi possivel conectar ao storage, de IP ${endereco_ip}. A cópia do backup não será realizada"
		return 1
	fi
	return 1
}


# Verifica o retorno do comando rsync
# Parâmetros:
# 	1 - Codigo(s) de retorno 
function verificar_retorno(){
  local codigos_retorno="$1"
  local msg_erro="Arquivos de backup não foram copiados"
	for cod_retorno in $codigos_retorno ; do
    case "$cod_retorno" in
      '0') echo -e "SUCESSO! \nArquivos de backup copiados com sucesso.";;
      '1') echo -e "ERRO DE SINTAXE \n${msg_erro}.";;
      '2') echo -e "ERRO IMCOMPATIBILIDADE DE PROTOCOLO \n${msg_erro}.";;
      '3') echo -e "ERRO AO SELECIONAR ARQUIVOS OU PASTAS \n${msg_erro}.";;
      '10') echo -e "ERRO DE SOCKET I/O \n${msg_erro}.";;
      '12') echo -e "ERRO NO STREAM DE DADOS DO PROTOCOLO RSYNC \n${msg_erro}.";;
      '23') echo -e "TRANSFERENCIA PARCIAL DEVIDO A ERRO \n${msg_erro} completamente.";;
      '30') echo -e "ERRO - TIMEOUT NO ENVIO/RECEBIMENTO DE DADOS \n${msg_erro}.";;
      '35') echo -e "ERRO - TIMEOUT NA CONEXÃO DO DAEMON \n${msg_erro}.";;
      '255') echo -e " ERRO NA CONEXAO SSH | TIMEOUT OU BROKEN PIPE \n${msg_erro}.";;
      *) echo -e "ERRO $cod_retorno \n${msg_erro}.";;
    esac
  done
}



### TESTES E VALIDACOES

if [ "$(id -u)" != "0" ]; then
  echo 'Esse programa deve ser executado como root!'
  
fi

if [ "$envia_para_storage" -eq 1 ] ; then
  [[ -z "$ip_storage" ]] && echo "O envio para o storage está ativo, a variável ip_storage não pode ser vazia!"
  [[ -z "$porta_storage" ]] && echo "O envio para o storage está ativo, a variável porta_storage não pode ser vazia!"
  [[ -z "$pasta_storage" ]] && echo "O envio para o storage está ativo, a variável pasta_storage não pode ser vazia!"
fi

[[ -d "$pasta_backup" ]] || mkdir "$pasta_backup"



### EXECUCAO DO PROGRAMA

para_database # Funcao

if [[ -z $(pgrep dbsrv16) ]]; then
  compacta_arquivos # Funcao
else
  echo "O banco de dados não foi finalizado, tentando finalizar novamente..."
  killall -w -s TERM dbsrv16 > /dev/null 2>&1
  if [[ -z $(pgrep dbsrv16) ]]; then
    compacta_arquivos # Funcao
  else
    echo "Não foi possível realizar o backup. Finalizando procedimento..."
    sleep 10
    systemctl start sisdominio
  fi
fi

systemctl start sisdominio
