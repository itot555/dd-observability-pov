#! /bin/bash -e

set -e

exec > >(sudo tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

#------------------------------------------------------------------------------
# Wait for cloud-init / unattended-upgrades to release apt locks
# (Ubuntu の自動アップグレードが起動時に apt を握るため、user_data と衝突する)
#------------------------------------------------------------------------------

wait_for_apt() {
  local i=0
  while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
     || sudo fuser /var/lib/apt/lists/lock     >/dev/null 2>&1 \
     || sudo fuser /var/lib/dpkg/lock          >/dev/null 2>&1; do
    i=$((i+1))
    echo "apt is locked by another process. waiting... ($${i}/120)"
    sleep 5
    if [ "$i" -ge 120 ]; then
      echo "apt lock did not release within 10 minutes." >&2
      exit 1
    fi
  done
}

wait_for_apt
sudo systemctl stop unattended-upgrades.service 2>/dev/null || true
sudo systemctl disable unattended-upgrades.service 2>/dev/null || true

# ネットワーク確立を待ちつつ apt-get update をリトライ
apt_update_with_retry() {
  local i=0
  while ! sudo apt-get update; do
    i=$((i+1))
    echo "apt-get update failed (network not ready). retrying... ($${i}/30)"
    sleep 10
    if [ "$i" -ge 30 ]; then
      echo "apt-get update kept failing for 5 minutes." >&2
      exit 1
    fi
  done
}

#------------------------------------------------------------------------------
# Configure ssh key
#------------------------------------------------------------------------------

echo "${COMMON_PUBLIC_KEY}" >> /home/ubuntu/.ssh/authorized_keys
echo "${COMMON_PRIVATE_KEY}" > /home/ubuntu/.ssh/id_rsa
chmod 600 /home/ubuntu/.ssh/id_rsa
chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys
chown ubuntu:ubuntu /home/ubuntu/.ssh/id_rsa

#------------------------------------------------------------------------------
# Log directory
#------------------------------------------------------------------------------

sudo mkdir -p /var/log/${NAME_PREFIX} /var/log/app
sudo chown ubuntu:ubuntu /var/log/${NAME_PREFIX} /var/log/app

#------------------------------------------------------------------------------
# Tools installation
#------------------------------------------------------------------------------

echo "必要なツールのインストールを開始します。"

apt_update_with_retry
sudo apt-get install -y wget gpg coreutils gnupg lsb-release apt-transport-https ca-certificates \
  curl software-properties-common git awscli unzip acl net-tools build-essential jq

echo "共通ツールのインストールが完了しました。"

#------------------------------------------------------------------------------
# Java development environment
#------------------------------------------------------------------------------

echo "Java 開発環境のセットアップを開始します。"

sudo apt-get install -y openjdk-21-jdk maven
echo "export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64" >> /home/ubuntu/.bashrc
echo "export PATH=\$JAVA_HOME/bin:\$PATH" >> /home/ubuntu/.bashrc

echo "Java のインストールが完了しました。"

echo "Bootstrapping complete."
