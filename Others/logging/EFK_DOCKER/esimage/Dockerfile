#FROM reg.dhdc.com/dhc_cloud/elasticsearch:1.0
FROM reg.dhdc.com/loggingefk/elasticsearch:v1.0.0

#RUN mkdir -p /usr/elasticsearch/elasticsearch-2.4.1/config/templates
#COPY template-k8s-logstash.json /usr/elasticsearch/elasticsearch-2.4.1/config/templates/template-k8s-logstash.json

COPY start_es.sh /start_es.sh
COPY es_mapping.sh /es_mapping.sh

COPY elasticsearch.yml  /usr/elasticsearch/elasticsearch-2.4.1/config/elasticsearch.yml

#RUN useradd --no-create-home --user-group elasticsearch \
#    && mkdir /data \
#    && chown -R elasticsearch:elasticsearch /elasticsearch

EXPOSE 9200 9300

#CMD /start_es.sh

ENTRYPOINT ["/bin/sh", "-c", "/start_es.sh"]
