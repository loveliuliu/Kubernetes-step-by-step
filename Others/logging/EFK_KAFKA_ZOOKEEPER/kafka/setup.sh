#!/bin/sh

cd  /opt
wget http://apache.fayea.com/kafka/0.10.0.0/kafka_2.10-0.10.0.0.tgz

tar -xf kafka_2.10-0.10.0.0.tgz
mv kafka_2.10-0.10.0.0 kafka
rm -rf kafka_2.10-0.10.0.0.tgz

mkdir -p  /opt/log/kafkalogs
