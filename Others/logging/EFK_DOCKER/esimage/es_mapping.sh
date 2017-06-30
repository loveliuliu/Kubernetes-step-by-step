#!/bin/bash

curl -i -XPUT 'http://localhost:9200/_template/logstash_template' -d '
{
  "template" : "logstash-*",
  "settings" : {
    "index.refresh_interval" : "5s"
  },
  "mappings" : {
    "_default_" : {
      "dynamic_templates" : [ {
        "kubernetes_labels" : {
          "path_match" : "kubernetes.labels",
          "mapping" : {
            "type" : "object",
            "dynamic_templates" : [ {
              "match_mapping_type": "string",
              "path_match" : "*",
              "mapping" : {
                "type" : "string",
                "index" : "not_analyzed"
              }
            } ]
          }
        }
      }, {
        "kubernetes_field" : {
          "match_mapping_type": "string",
          "path_match" : "kubernetes.*",
          "mapping" : {
            "type" : "string",
            "index" : "not_analyzed"
          }
        }
      } ]
    }
  }
}
'

