#!/bin/sh

cd  /opt
wget http://apache.claz.org/zookeeper/zookeeper-3.4.10/zookeeper-3.4.10.tar.gz

tar -xf zookeeper-3.4.10.tar.gz
mv zookeeper-3.4.10  zookeeper
rm -rf zookeeper-3.4.10

mkdir -p /opt/data/zookeeperdata
makdir -p /opt/log/zookeeplogs

