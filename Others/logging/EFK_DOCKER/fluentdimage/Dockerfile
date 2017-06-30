FROM reg.dhdc.com/loggingefk/fluentd:v1.0.0
COPY td-agent.conf /etc/td-agent/td-agent.conf
COPY start-fluentd.sh /start-fluentd.sh
ENTRYPOINT ["/bin/sh", "-c", "/start-fluentd.sh"]
