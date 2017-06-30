FROM after4u/ubuntu-jdk8
COPY setup.sh /opt/setup.sh
RUN /opt/setup.sh
COPY ./package/commons-codec-1.9.jar  /opt/kafka/libs/  
COPY ./package/httpasyncclient-4.1.1.jar  /opt/kafka/libs/
COPY ./package/kafka-connect-elasticsearch-3.2.0-SNAPSHOT.jar  /opt/kafka/libs/
COPY ./package/commons-lang3-3.4.jar  /opt/kafka/libs/  
COPY ./package/httpclient-4.5.1.jar  /opt/kafka/libs/
COPY ./package/commons-logging-1.2.jar  /opt/kafka/libs/
COPY ./package/httpcore-4.4.4.jar   /opt/kafka/libs/
COPY ./package/httpcore-nio-4.4.4.jar  /opt/kafka/libs/
COPY ./package/gson-2.4.jar  /opt/kafka/libs/
COPY ./package/jest-2.0.0.jar  /opt/kafka/libs/        
COPY ./package/guava-18.0.jar  /opt/kafka/libs/        
COPY ./package/jest-common-2.0.0.jar   /opt/kafka/libs/
COPY ./package/slf4j-simple-1.7.5.jar   /opt/kafka/libs/
COPY server.properties /opt/kafka/config/server.properties
COPY elasticsearch-connect.properties /opt/kafka/config/elasticsearch-connect.properties
COPY connect-standalone.properties /opt/kafka/config/connect-standalone.properties
COPY run.sh /opt/run.sh
ENTRYPOINT ["/bin/sh", "-c", "/opt/run.sh;while true; do sleep 60; done"]

