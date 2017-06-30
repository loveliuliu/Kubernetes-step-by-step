#!/bin/sh

cd  /opt
curl -O https://download.elasticsearch.org/logstash/logstash/logstash-2.4.1.tar.gz

tar -xf logstash-2.4.1.tar.gz
mv logstash-2.4.1 logstash
rm -rf logstash-2.4.1.tar.gz

