#!/bin/bash

# 启动ES
/usr/elasticsearch/elasticsearch-2.4.1/bin/elasticsearch &

# 用于检查ES是否正常启动成功
Status=0

# 用于检查ES是否是初次启动,初次启动则需要更新默认映射
LogIndexNum=0

# 用以记录检查ES是否正常启动成功的次数,5分钟未成功则放弃设置更新ES
count=0

while [ "$Status" -ne 1 ]
do
        sleep 5
	Status=`curl -XGET  'http://localhost:9200' | grep "You Know, for Search" | wc -l`
        if [ $Status -eq 1 ];then    
                echo "ElasticSearch is Ready and Running....."
		# 初次运行修改默认的映射模板	
                Inum=`curl -XGET 'http://localhost:9200/_cat/indices?pretty' | grep logstash | wc -l`
                if [ $Inum -eq $LogIndexNum ];then
                   	echo "This is the first time running the ES cluster, update the  default mappings....."
			./es_mapping.sh
                fi
        else
                echo "ElasticSearch is Not Ready. Recheck 5s later....."
                let "count++"
        fi

	# 最多尝试5分钟,如果5分钟ES还未就绪，则退出
        if  [ $count  -gt 59 ];then
                break
        fi
done

if [ $count  -eq 60 ];then
	echo "ElasticSearch not ready for 300s since starting. Existing......."
	exit 1	
fi

while  true 
do 
	sleep 10
done 
