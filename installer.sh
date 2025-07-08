#!/usr/bin/env bash

cd "`dirname \"$0\"`"
REPOROOT=$(pwd)
#echo $REPOROOT

sudo apt-get  install  -y libtool m4 automake gcc-12 build-essential  autotools-dev  autotools-dev libtool m4 automake autoconf autogen    git daemon   socat unzip net-tools p7zip-full unzip
set -e

function patch_libsodium() {
  patchFile="./libsodium/src/libsodium/crypto_generichash/blake2/ref/blake2.h"
  sed -i 's/ALIGN( 64 ) typedef struct blake2s_state_/typedef struct ALIGN( 64 ) blake2s_state_/g'  $patchFile
  sed -i 's/ALIGN( 64 ) typedef struct blake2b_state_/typedef struct ALIGN( 64 ) blake2b_state_/g'  $patchFile
  sed -i 's/#ifndef DEFINE_BLAKE2B_STATE/#ifdef DEFINE_BLAKE2B_STATE/g' $patchFile
  #cat $patchFile |grep "ALIGN( 64 ) typedef struct blake2s_state_"
}

# unzip shadowvpn.zip
tmpdir=$(mktemp -d)
cd $tmpdir
git clone --recursive https://github.com/hw-1/ShadowVPN.git
cd ShadowVPN
./autogen.sh
./configure --prefix=/opt/shadowvpn --sysconfdir=/opt/shadowvpn/etc
patch_libsodium
make
sudo make install


# 1314 - 60 = 1254
# cmd执行 ping -4  -c 1  -f -l 1500 google.com
# 逐步加大或者减少该值，直到恰好不会出现DF拆包的提示。记下这个mtu
# 例如，记下的mtu是1492，计算得到 1492 (Ethernet) - 20 (IPv4, or 40 for IPv6) - 8 (UDP) - 32 (ShadowVPN) = 1254（这是ipv4，对ipv6再减20,）
# 注意：mtu减去多少，取决于你的shadowvpn版本，详细看server.conf里面的mtu注释
# 那么在服务端的server.1254
# 客户端也一致填写1254

function  getmtu(){
  mtu=1472
  tmpfile=$(mktemp)
  # echo $tmpfile
  echo "is not enough to hold preload" > $tmpfile
  while [[ "$(cat $tmpfile |grep "is not enough to hold preload")" != "" ]];do
    mtu=$(( mtu - 1 ))
    # echo $mtu
    output=$(sudo ping -4    -c 1  -f -l $mtu google.com  2>&1)
     echo "$output"  > $tmpfile
    # cat $tmpfile
  done
  rm -rf $tmpfile
  mtu=$(( mtu - 60 ))
  echo  $mtu
}
mtu=$(getmtu)
password=$(cat /dev/urandom | tr -dc '0-9' | head -c7)
server=$(ifconfig eth0 | grep 'inet ' | awk '{print $2}')

#1123
sed  -i "s/^port=.*$/port=8000/g" /opt/shadowvpn/etc/shadowvpn/server.conf
sed  -i "s/^mtu=.*$/mtu=${mtu}/g" /opt/shadowvpn/etc/shadowvpn/server.conf
sed  -i "s/^up=.*$/up=\/opt\/shadowvpn\/etc\/shadowvpn\/server_up.sh/g" /opt/shadowvpn/etc/shadowvpn/server.conf
sed  -i "s/^down=.*$/down=\/opt\/shadowvpn\/etc\/shadowvpn\/server_down.sh/g" /opt/shadowvpn/etc/shadowvpn/server.conf
sed  -i "s/^password=.*$/password=${password}/g" /opt/shadowvpn/etc/shadowvpn/server.conf

echo shadowvpn 安装成功
echo -------配制信息如下------------
echo server:$server
echo port:8000
echo password:$password
echo IP:10.7.0.2
echo subnetmask:255.255.255.0
echo mtu:$mtu
echo ------------------------------


ps aux|grep shadowvpn|grep -v grep|awk '{print $2}' |while read var;do echo $var;kill -9 $var;done
echo start ShadowVPN
sudo /opt/shadowvpn/bin/shadowvpn -c /opt/shadowvpn/etc/shadowvpn/server.conf -s start
# sudo /opt/shadowvpn/bin/shadowvpn -c /opt/shadowvpn/etc/shadowvpn/server.conf -s stop

echo set shadowvpn to crontab
shadowvpnsh=$(cat <<EOF
if [[ "\$(netstat -na|grep 8000)" == "" ]];then
     sudo /opt/shadowvpn/bin/shadowvpn -c /opt/shadowvpn/etc/shadowvpn/server.conf -s start
fi
EOF
)
echo   "${shadowvpnsh}" >  /opt/shadowvpn/bin/shadowvpn.sh

function installcron() {
blj=$1
( crontab -l | grep -v -F "$blj" ; echo "$blj") | crontab -
}
installcron "* * * * * bash  /opt/shadowvpn/bin/shadowvpn.sh"

rm -rf $tmpdir
exit 0
# user_token=7e335d67f1dc2c01,ff593b9e6abeb2a5,e3c7b8db40a96105
