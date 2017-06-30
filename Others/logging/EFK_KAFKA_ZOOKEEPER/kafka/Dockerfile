FROM after4u/ubuntu-jdk8
COPY setup.sh /opt/setup.sh
RUN /opt/setup.sh
COPY server.properties /opt/kafka/config/server.properties
COPY run.sh /opt/run.sh
ENTRYPOINT ["/bin/sh", "-c", "/opt/run.sh;while true; do sleep 1; done"]

