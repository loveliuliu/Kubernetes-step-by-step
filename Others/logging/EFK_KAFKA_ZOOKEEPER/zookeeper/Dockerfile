FROM after4u/ubuntu-jdk8
COPY setup.sh /opt/setup.sh
RUN /opt/setup.sh
COPY zoo.cfg /opt/zookeeper/conf/zoo.cfg
COPY run.sh /opt/run.sh
ENTRYPOINT ["/bin/sh", "-c", "/opt/run.sh;while true; do sleep 1; done"]

