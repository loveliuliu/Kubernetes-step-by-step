FROM after4u/ubuntu-jdk8
COPY setup.sh /opt/setup.sh
RUN /opt/setup.sh
RUN mkdir -p /opt/logstash/conf
COPY logstash.conf /opt/logstash/conf/
COPY run.sh /opt/run.sh
ENTRYPOINT ["/bin/sh", "-c", "/opt/run.sh;while true; do sleep 60; done"]

