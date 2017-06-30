#!/bin/sh

#启动kafka 创建 topic
/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties  &
sleep 15
/opt/kafka/bin/kafka-topics.sh --create --zookeeper localhost:2181 --replication-factor 1 --partitions 1 --topic logs &
sleep 15
# 启动连接器
/opt/kafka/bin/connect-standalone.sh /opt/kafka/config/connect-standalone.properties /opt/kafka/config/elasticsearch-connect.properties &
#查看topic列表
#/opt/kafka/bin/kafka-topics.sh --list --zookeeper localhost:2181

#查看kafka中数据是否进入
#/opt/kafka/bin/kafka-console-consumer.sh --zookeeper localhost:2181 --topic logs
