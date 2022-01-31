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
# 

pasta_backup="/backup_dominio"
dias_armazenamento="30"


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
    tar -zcf "${pasta_backup}/dados_$(date +"%d-%m-%Y_%s").tar.gz" "$pasta"  > /dev/null 2>&1
  done < /opt/sybase/SYBSsa16/instalacao.txt
  echo 'Backup efetuado com sucesso!'
  rotaciona_pasta_backup # Funcao
  exit 0
}

if [ "$(id -u)" != "0" ]; then
  echo 'Esse programa deve ser executado como root!'
  exit 1
fi

[[ -d "$pasta_backup" ]] || mkdir "$pasta_backup"

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
    exit 1
  fi
fi
