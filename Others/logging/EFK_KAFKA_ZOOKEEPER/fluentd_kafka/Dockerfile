FROM reg.dhdc.com/loggingefk/fluentd:v1.0.1
COPY td-agent.conf /etc/td-agent/td-agent.conf
COPY start-fluentd.sh /start-fluentd.sh
RUN  td-agent-gem install fluent-plugin-kafka
ENTRYPOINT ["/bin/sh", "-c", "/start-fluentd.sh"]
