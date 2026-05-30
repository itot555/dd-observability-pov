#! /bin/bash -e

set -e

exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

#------------------------------------------------------------------------------
# Configure SSH key (ec2-user は AL2023 のデフォルトユーザー)
#------------------------------------------------------------------------------

echo "${COMMON_PUBLIC_KEY}" >> /home/ec2-user/.ssh/authorized_keys
echo "${COMMON_PRIVATE_KEY}" > /home/ec2-user/.ssh/id_rsa
chmod 600 /home/ec2-user/.ssh/id_rsa
chown ec2-user:ec2-user /home/ec2-user/.ssh/authorized_keys
chown ec2-user:ec2-user /home/ec2-user/.ssh/id_rsa

#------------------------------------------------------------------------------
# Log directory
#------------------------------------------------------------------------------

mkdir -p /var/log/${NAME_PREFIX} /var/log/app
chown ec2-user:ec2-user /var/log/${NAME_PREFIX} /var/log/app

#------------------------------------------------------------------------------
# Common tools
#------------------------------------------------------------------------------

echo "共通ツールのインストールを開始します。"

dnf install -y wget git unzip jq net-tools awscli

echo "共通ツールのインストールが完了しました。"

#------------------------------------------------------------------------------
# Java development environment (Amazon Corretto 21)
#------------------------------------------------------------------------------

echo "Java 開発環境のセットアップを開始します。"

dnf install -y java-21-amazon-corretto-devel maven

echo "export JAVA_HOME=/usr/lib/jvm/java-21-amazon-corretto" >> /home/ec2-user/.bashrc
echo "export PATH=\$JAVA_HOME/bin:\$PATH" >> /home/ec2-user/.bashrc

echo "Java のインストールが完了しました。"

#------------------------------------------------------------------------------
# Python development environment
# psycopg2-binary を使用するため postgresql-devel は不要
#------------------------------------------------------------------------------

echo "Python 開発環境のセットアップを開始します。"

dnf install -y python3 python3-pip python3-devel gcc

echo "Python のインストールが完了しました。"

echo "Bootstrapping complete."
