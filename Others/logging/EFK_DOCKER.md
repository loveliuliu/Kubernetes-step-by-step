# 基于 Docker images 和 Docker run 构建 K8s 集群的 EFK 日志系统
# 1 整体架构
 EFK分别表示日志系统的存储（Elasticsearch）、采集（Fluentd）、展示（Kibana）三个组件：

 Fluentd ------>ElasticSearch <------ Kibana

(1) Fluentd：日志采集端，每个节点(物理节点，虚拟节点)部署一个，采集该节点上的指定文件，进行相应的格式转换和过滤后讲日志记录发送到相应的存储目的地（如 ElasticSearch）;

(2) ElasticSearch：存储 Fluentd 采集的日志数据，并对数据进行索引，以支持对日志数据的实时查询;

(3) Kibana: 可视化日志展示端 WebUI，提供 ElasticSearch 中日志数据查询的接口，并支持可定制的 dashboard.

Fluentd 的运行需要ElasticSearch 的支持，Fluentd 先于 ElasticSearch 运行会导致其无法发送数据到 ElasticSearch 而频繁重启服务。
Kibana 的运行也需要 ElasticSearch 的支持，甚至需要 Fluentd 的支持. Kibana 先于 ElasticSearch 运行会导致无法在 ElasticSearch 中建立 .kibana 索引从而无法正常运行；Kibana 在 ElasticSearch 运行之后、Fluentd 运行之前运行，会导致无法创建 index pattern，从而无法通过 kibana 查看任何日志信息.



# 2 相关镜像及配置文件
## 2.1 ElasticSearch 镜像及其相关配置文件
ElasticSearch 对应镜像及相关的配置在路径 EFK_Docker/esimage/ 下.


### 2.1.1 Dockerfile
以家镇的 ElasticSearch 镜像 reg.dhdc.com/dhc_cloud/elasticsearch:1.0 为基础镜像构建，具体 Dockerfile 内容如下：
```
FROM reg.dhdc.com/dhc_cloud/elasticsearch:1.0

RUN mkdir -p /usr/elasticsearch/elasticsearch-2.4.1/config/templates
COPY template-k8s-logstash.json /usr/elasticsearch/elasticsearch-2.4.1/config/templates/template-k8s-logstash.json

COPY start_es.sh /start_es.sh
COPY elasticsearch.yml  /usr/elasticsearch/elasticsearch-2.4.1/config/elasticsearch.yml

EXPOSE 9200 9300

ENTRYPOINT ["/bin/sh", "-c"]
```
### 2.1.2 索引映射模板文件 template-k8s-logstash.json
索引映射模板文件 template-k8s-logstash.json 主要用于在向 ElasticSearch 索引日志数据的时候解析出日志相关的 kubernetes 元数据，如:  
```
 kubernetes.namespace_name  
 kubernetes.pod_name  
 kubernetes.container_name  
```

Notes：实际测试中对应的索引模板文件并没有生效，可以通过 2.1.6 说明的方法手动更新索引映射模板.


### 2.1.3 配置文件 elasticsearch.yml
配置文件 elasticsearch.yml 主要配置 ElasticSearch 相关的配置，主要设置绑定特定 IP 地址的参数，以支持直接使用 host 的 IP 地址访问 ES：
```
//绑定特定 IP 地址
network.host: 0.0.0.0
```  

### 2.1.4 启动 ElasticSearch 服务的脚本
脚本 start_es.sh 用于启动 ElasticSearch 服务，在 ElasticSearch 容器正常启动后，可以在容器中通过该脚本启动 ElasticSearch 服务.


### 2.1.5 Makefile 编译 ElasticSearch 镜像
Makefile 文件用于编译 ElasticSearch 镜像，针对不同的环境，需要设置不同的镜像仓库名称和镜像 Tag.


### 2.1.6 更新索引映射模板的脚本
脚本文件 es_mapping.sh 用于更新 ElasticSearch 默认的索引模板，以支持索引日志数据的时候解析出日志相关的 kubernetes 元数据，并且对 kubernetes 的相关元数据字段不再分词以达到精确匹配的效果.如对名称为 test001-app001 的 Pod 进行查询时，只会以 “test001-app001” 作为关键字查询，而不会拆分成“test001”、“app001” 和 “test001-app001” 三个关键字进行查询.

该脚本无需放在 ElasticSearch 镜像中：

(1) 如果需要放到 ElasticSearch 镜像中，则可以将脚本中的 http://172.25.3.194:9200 对应的 IP 设置为 localhost 或者 127.0.0.1.

(2) 如果不放到 ElasticSearch 镜像中，则需要在执行脚本前将脚本中的 http://172.25.3.194:9200 对应的 IP 设置为 ElasticSearch 安装的节点对应的 IP.

Notes: 执行更新索引映射模板的操作需要在 Fluentd 开始往 ElasticSearch 写数据之前，因为更新索引映射模板不会对已创建的说句索引产生影响.执行方式是在 ElasticSearch 容器正常运行之后，直接执行 es_mapping.sh 文件即可.


## 2.2 Fluentd 镜像及其相关配置文件
Fluentd 对应镜像及相关的配置在路径 EFK_Docker/fluentdimage/ 下.


### 2.2.1 Dockerfile
以 kubernetes 1.4 版本的 fluentd-elasticsearch：1.12 镜像重新打 tag 的 reg.dhdc.com/loggingefk/fluentd-elasticsearch:v1.0.2 镜像为基础镜像构建（对应的 fluentd 的版本为 0.12.29），具体 Dockerfile 内容如下：
```
FROM reg.dhdc.com/loggingefk/fluentd-elasticsearch:v1.0.2
COPY td-agent.conf /etc/td-agent/td-agent.conf
COPY start-fluentd.sh /start-fluentd.sh
ENTRYPOINT ["/bin/sh", "-c"]
```

### 2.2.2 Fluentd 配置文件 td-agent.conf
Fluentd 的配置文件 td-agent.conf 主要配置了 fluentd 采集的日志文件路径（source，配置日志采集的源文件）、对日志文件的预处理（filter，过滤出日志相关的 kubernetes 元数据）、采集的日志的输出目的地（match，输出到 ElasticSearch）.
对配置文件 td-agent.conf 需要注意一下几个地方的具体配置：
(1) 输入插件 source 部分
```
time_format %Y-%m-%dT%H:%M:%S.%N%Z   // 定义日志时间戳的格式和精度  
format  json        //定义日志的存储格式  
time_key key3       //定义从第几个 key 获取作为时间字段（key）的value，需要通过输入的日志源文件确认  
enable_watch_timer true   //开启额外的 watch 机制，避免 inotify 机制异常导致停止采集日志  
read_lines_limit 200   //单次 I/O 读取的日志的条数，过大容易导致 Fluentd buffer 故障重启  
```
(2) 输出插件 match 部分
```
host 172.25.3.194    // ElasticSearch 的节点的 IP 地址   
buffer_type file     // 指定使用磁盘 file 文件作为 buffer，是最安全的使用方式，但高流量日志的情况下影响性能，不设置该参数则默认使用内存作为 buffer，有宕机导致数据丢失的风险  
buffer_path /var/log/fluentd.buffer.file   //如果指定 buffer 类型为file，则需要制定对应的 file 路径名  
buffer_chunk_limit 4M    // buffer 中一个 chunk 的大小，要大于单次 I/O 最大读取的日志的大小  
buffer_queue_limit 256   // buffer 最多包含的 chunk 的数量  
request_timeout 60   // 某些场景下，fluentd 发送数据到 ElasticSearch 后等待 HTTP 请求的返回超时时间，如果超时时间到达没有返回，则会重发数据，导致日志数据记录重复，数量不一致.  
```

(3) filter 插件解析 k8s 元数据部分
```
<filter kubernetes.**>
  type kubernetes_metadata
  kubernetes_url http://172.25.3.194:8080  # 指定 Apiserver 的 URL，如果以 daemonset 方式部署则可以不设置
</filter>
```

### 2.2.3 启动 FLuentd 服务的脚本
脚本 start-fluentd.sh 用于启动 Fluentd 服务，在 Fluentd 容器正常启动后，可以在容器中通过该脚本启动 Fluentd 服务.


### 2.2.4 Makefile 编译 ElasticSearch 镜像
Makefile 文件用于编译 Fluentd 镜像，针对不同的环境，需要设置不同的镜像仓库名称和镜像 Tag.


## 2.3 Kibana 镜像
Kibana 镜像直接使用家镇的 kibana 镜像：

    reg.dhdc.com/dhc_cloud/kibana  
    
打 tag 转为

    reg.dhdc.com/loggingefk/kibana:v1.0.0


# 3. 基于 Docker 的 EFK 日志系统部署
根据前面的说明，部署的步骤是：
(1) 部署 ElasticSearch
(2) 部署 Fluentd
(3) 部署 Kibana

## 3.1 部署 ElasticSearch
### 3.1.1 部署并启动 ElasticSearch 服务 （适用于 v1.0.0 版本镜像）
第一次部署时，在宿主机(如 172.25.3.194)上建立 ES 数据存储空间：
```
mkdir /es/data
chmod 777  -R /es  
```    
使用如下命令部署 ElasticSearch
```
docker run -it -p 127.0.0.1:9200:9200 --net=host -v /es/data:/usr/elasticsearch/elasticsearch-2.4.1/data    reg.dhdc.com/loggingefk/elasticsearch:v1.0.0  bash
```
ElasticSearch 镜像成功运行后，进入容器后执行如下命令启动 ElasticSearch 服务
```
./start_es.sh
```


### 3.1.2 更新 ElasticSearch 的索引映射模板 （适用于 v1.0.0 版本镜像）
在集群任意节点执行(执行前需要修改对应的 ElasticSearch host)  
```
./es_mapping.sh
```
 
也可以将该脚本文件放到 ElasticSearch 的镜像中，在对应的容器中运行该脚本.但需要注意的是，如果是该脚本放到镜像中，对应的 IP 段需要写成 localhost 或者 127.0.0.1.

### 3.1.3 v1.0.1 及更新版本的镜像, 使用如下部署方式
第一次部署时，在宿主机(如 172.25.3.194)上建立 ES 数据存储空间：
```
mkdir /es/data
chmod 777  -R /es
```
使用如下命令部署 ElasticSearch
```
docker run -it -p 127.0.0.1:9200:9200 --net=host --restart=always -v /es/data:/usr/elasticsearch/elasticsearch-2.4.1/data    reg.dhdc.com/loggingefk/elasticsearch:v1.0.1
```
镜像创建的容器启动后会自动完成 ES 创建, 映射模板更新的工作

## 3.2 部署 Fluentd 并启动 Fluentd 服务

Fluentd 需要在每个采集节点部署一个镜像实例.

### 3.2.1 v1.0.0 版本部署操作
在需要采集日志的节点执行如下操作部署 Fluentd 实例：
```
docker run -it --net=host  -v /var/log/containers:/var/log/containers  -v /var/lib/docker:/var/lib/docker reg.dhdc.com/loggingefk/fluentd:v1.0.0   bash
```
Fluentd 容器正常运行后，进入容器后执行如下命令启动服务
```
 ./start-fluentd.sh
```
Notes： 如果需要采集容器日志之外的其他日志，需要对应的额外增加其他 source 配置部分。

### 3.2.2 v1.0.1及以上版本部署操作

在需要采集日志的节点执行如下操作部署 Fluentd 实例：
```
docker run -it --net=host --restart=always -v /var/log/containers:/var/log/containers  -v /var/lib/docker:/var/lib/docker reg.dhdc.com/loggingefk/fluentd:v1.0.1
```
镜像创建的容器启动后会自动完成 Fluentd 的启动工作

## 3.3 部署 Kibana 并启动 Kibana 服务
Kibana 只需要部署一个实例.
### 3.3.1  v1.0.0 版本的kibana镜像部署
在 ElasticSearch 所在的主机(172.25.3.194)上执行如下命令部署 Kibana：
```
docker run -it -p 127.0.0.1:5601:5601 --net=host reg.dhdc.com/loggingefk/kibana:v1.0.0  bash
```
Kibana 容器正常运行后，进入容器后执行如下命令启动服务
```
    /usr/kibana/kibana-4.6.1-linux-x86_64/bin
```


### 3.3.2  v1.0.1 及以上版本的kibana镜像部署
在 ElasticSearch 所在的主机(172.25.3.194)上执行如下命令部署 Kibana：
```
docker run -it -p 127.0.0.1:5601:5601 --net=host --restart=always reg.dhdc.com/loggingefk/kibana:v1.0.1
```

Kibana 容器正常运行后会自动完成 Kibana 的启动工作

## 3.4 ElasticSearch 及 Kibana 访问 UI
ElasticSearch：
```
http://172.25.3.194:9200/_plugin/head/
```

KIbana：
```
http://172.25.3.194:5601
```


# 4. 目前遇到的坑和需要注意的问题
EFK 目前遇到的坑和需要注意的问题：

(1) 在 Elasticsearch 的安装目录配置文件的  config/templates/ 中增加索引映射模板文件时，对应的模板文件不会生效，解决方式是在 ES 启动成功后手都修改映射模板（执行 es_mapping.sh 文件）

(2) ES 采集的日志中，日志消息本体的 @timestamp 字段被解析，但是日志消息本体的 time 字段并没有动态解析出来，手动修改映射信息后，虽然可以增加 time 字段，但对应的字段在 ES 的 record 中并不显示。后来找出问题原因是输入插件的 source 部分需要制定时间格式 time_format 和 时间字段的取值选择 time_key.具体可以参考本文档 2.2.2 部分的内容


# 5.  Fluentd->Kafka->Connetctor->Es->Kibana  的 FKEK 日志Docker 环境部署
## 5.1  构建编译 Kafka 到 Elasticsearch 的 Connector
### 5.1.1  安装 Maven
(1)  下载 apache-maven-3.5.0-bin.tar.gz
```
cd  /opt
wget http://mirror.bit.edu.cn/apache/maven/maven-3/3.5.0/binaries/apache-maven-3.5.0-bin.tar.gz
```

(2) 安装 Maven
```
tar -xf apache-maven-3.5.0-bin.tar.gz
```
修改环境变量，在/etc/profile中添加以下几行
```
export M2_HOME=/opt/apache-maven-3.5.0
export PATH=$M2_HOME/bin:$PATH
```

执行source /etc/profile使环境变量生效。

(3) 验证 Maven
最后运行 mvn -v验证 maven是否安装成功，

### 5.1.2  编译 Kafka 连接 Elasticsearch 的插件
特别提醒（我自己在这个地方被坑了大半天）： 不能用 root 用户编译，否则编译 test 的时候无法成功
(1) 下载插件  kafka-connect-elasticsearch
```
git clone -b 0.10.0.0 https://github.com/confluentinc/kafka-connect-elasticsearch.git
```
(2) 用 maven 编译插件
注意： 不能用 root 用户编译，否则编译 test 的时候无法成功(推测是 elasticsearch 不能以root 用户运行的原因，暂时未深究原因)
```
cd kafka-connect-elasticsearch
mvn clean package
```

(3) 确定编译成功
编译成功之后会在当前目录下生成  target 目录，如果   target/kafka-connect-elasticsearch-3.2.0-SNAPSHOT-package/share/java/kafka-connect-elasticsearch/ 目录中有文件（都是 jar 包文件），则编译成功。


## 5.2  将 Kafka 到 Elasticsearch 的 Connector 插件安装到 Kafka
### 5.2.1  安装插件
将前面编译的   kafka-connect-elasticsearch/target/kafka-connect-elasticsearch-3.2.0-SNAPSHOT-package/share/java/kafka-connect-elasticsearch/ 目录中所有文件（都是 jar 包文件）拷贝到每个 kafka 安装目录的 libs 目录下。

### 5.2.2 插件配置文件
使用 kafka 的 bin/connect-standalone.sh 以 Standalone 模式运行 connector。需要两个配置文件：
(1) elasticsearch-connect.properties 文件；
(2) connect-standalone.properties 文件；
这两个配置文件都需要放到 Kafka 安装目录的 config 目录下

### 5.2.3  配置文件 elasticsearch-connect.properties 的配置内容及说明
使用以下内容创建 elasticsearch-connect.properties 文件：

```
name=elasticsearch-sink
connector.class=io.confluent.connect.elasticsearch.ElasticsearchSinkConnector
tasks.max=1
topics=logs
topic.index.map=logs:logs_index
connection.url=http://localhost:9200
type.name=log
key.ignore=true
schema.ignore=true
```
配置文件的解释：
(1) 使用 io.confluent.connect.elasticsearch.ElasticsearchSinkConnector 作为 sink 来负责发送数据到 ElasticSearch；
(2) name=elasticsearch-sink： 将 sink 名称设置为 elasticsearch-sink，且名称应当唯一；
(3) tasks.max=1： 为该 connector 创建单个 task (tasks.max) 来处理工作，但如果不能达到指定的并行等级，kafka可以创建少数几个 tasks ；
(4) topics=logs： 从 kafka 的名为 logs 的 topics 中读取数据；
(5) topic.index.map=logs:logs_index:  从 kafka 的名为 logs 的 topics 中读取的数据存储到名为 logs_index的索引中。
(6) connection.url=http://localhost:9200： 使用本地 ElasticSearch 实例；
(7) type.name=log:存储到 ES 中的数据使用 log 类型；
(8) key.ignore=true： 让 Kafka 忽略 key；
(9) schema.ignore=true： 让 Kafka 忽略 key；  

其中 (8)和(9) 的设置目的是使用 Elasticsearch 中的模板来控制数据结构和分析。如果都改为 flase ，则  kafka 报错
```
ERROR Task elasticsearch-sink-0 threw an uncaught and unrecoverable exception (org.apache.kafka.connect.runtime.WorkerTask:142)
```

### 5.2.4 配置文件 connect-standalone.properties 的配置内容及说明
注意：这里是以 Standalone 模式运行 Kafka Connect Elasticsearch 的配置为例

```
bootstrap.servers=localhost:9092
key.converter=org.apache.kafka.connect.json.JsonConverter
value.converter=org.apache.kafka.connect.json.JsonConverter
key.converter.schemas.enable=false
value.converter.schemas.enable=false
internal.key.converter=org.apache.kafka.connect.json.JsonConverter
internal.value.converter=org.apache.kafka.connect.json.JsonConverter
internal.key.converter.schemas.enable=false
internal.value.converter.schemas.enable=false
offset.storage.file.filename=/tmp/connect.offsets
offset.flush.interval.ms=10000
```


文件 connect-standalone.properties 定义了 Kafka brokers 列表、key 和 value 转换器、是否应当使用 schemas，等等。

## 5.3  物理节点上 Kafka 及组件启动相关
各个组件的安装可以参考后面各个组件Docker 化的 setup.sh 代码
### 5.3.1  启动zookeeper
进入zookeeper 的安装目录的 bin/目录下，使用下面的命令启动zookeeper：
```
./zkServer.sh  start
```


### 5.3.2  启动kafka
进入 kafka 的安装目录，使用下面的命令启动kafka：
```
bin/kafka-server-start.sh config/server.properties &
```


### 5.3.3  在kafka中创建名称为 logs 的 topic
进入 kafka 的安装目录，创建 topic (第一次需要，后续不需要)：
```
bin/kafka-topics.sh --create --zookeeper localhost:2181 --replication-factor 1 --partitions 1 --topic syslog-topic &
```

### 5.3.4  启动kafka连接 Elasticsearch 的连接器
进入 kafka 的安装目录，使用下面的命令启动kafka连接器（不稳定，如果ES断开，往往连接器也会异常），运行前要确保 kafka 已运行并创建了对应的 topic (之前配置文件中设置为 logs)：
```
bin/connect-standalone.sh config/connect-standalone.properties config/elasticsearch-connect.properties  &
```
该命令以Kafka 所在节点上一个单独的 JVM 进程的方式启动运行，Kafka 中指定 topic 中的数据都会传输到 ElasticSearch。


## 5.4  Docker 化部署 FKEK (Fluentd->Kafka->ElasticSearch->Kibana)
### 5.4.1 Zookeeper 镜像制作
#### 5.4.1.1 Dockerfile
Dockerfile 文件内容如下：
```
FROM after4u/ubuntu-jdk8
COPY setup.sh /opt/setup.sh
RUN /opt/setup.sh
COPY zoo.cfg /opt/zookeeper/conf/zoo.cfg
COPY run.sh /opt/run.sh
ENTRYPOINT ["/bin/sh", "-c", "/opt/run.sh;while true; do sleep 1; done"]
```
其中 setup.sh 用于安装 zookeeper，run.sh 用于启动运行 zookeeper

#### 5.4.1.2  setup.sh
安装 zookeeper 的操作脚本内容如下：
```
#!/bin/sh

cd  /opt
wget http://apache.claz.org/zookeeper/zookeeper-3.4.10/zookeeper-3.4.10.tar.gz

tar -xf zookeeper-3.4.10.tar.gz
mv zookeeper-3.4.10  zookeeper
rm -rf zookeeper-3.4.10

mkdir -p /opt/data/zookeeperdata
makdir -p /opt/log/zookeeplogs
```

#### 5.4.1.3 run.sh
运行 zookeeper 的操作脚本如下：
```
#!/bin/sh

/opt/zookeeper/bin/zkServer.sh start
```

#### 5.4.1.4 zoo.cfg
配置文件 zoo.cfg 的内容如下：
```
ticketTime=2000
clientPort=2181
dataDir=/opt/data/zookeeperdata
dataLogDir=/opt/log/zookeeplogs

#initLimit=10
#syncLimit=5
#server.1=master:2888:3888
#server.2=slave01:2888:3888
#server.3=slave02:2888:3888
```
其中被注释的部分是多节点 zookeeper 需要的一部分配置参数

#### 5.4.1.5 Makefile
Makefile  内容如下：
```
TAG = v0.1
REGISTRY = reg.dhdc.com
USER = loggingefk
IMAGE = zookeeper

build:
	docker build -t $(REGISTRY)/$(USER)/$(IMAGE):$(TAG) .
push:
	docker push $(REGISTRY)/$(USER)/$(IMAGE):$(TAG)
```

### 5.4.2 Kafka 镜像制作
kafka 镜像是不包含导入数据到 ES 的连接器，实现的功能是启动 kafka 并运行。

#### 5.4.2.1 Dockerfile
Dockerfile 文件内容如下：
```
FROM after4u/ubuntu-jdk8
COPY setup.sh /opt/setup.sh
RUN /opt/setup.sh
COPY server.properties /opt/kafka/config/server.properties
COPY run.sh /opt/run.sh
ENTRYPOINT ["/bin/sh", "-c", "/opt/run.sh;while true; do sleep 1; done"]
```

#### 5.4.2.2 setup.sh
安装 kafka 的操作脚本内容如下：
```
#!/bin/sh

cd  /opt
wget http://apache.fayea.com/kafka/0.10.0.0/kafka_2.10-0.10.0.0.tgz

tar -xf kafka_2.10-0.10.0.0.tgz
mv kafka_2.10-0.10.0.0 kafka
rm -rf kafka_2.10-0.10.0.0
rm -rf kafka_2.10-0.10.0.0.tgz

mkdir -p  /opt/log/kafkalogs
```

#### 5.4.2.3 run.sh
运行 kafak的操作脚本如下：
```
#!/bin/sh

#/opt/kafka/bin/kafka-server-start.sh config/server.properties
#启动kafka
/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties  &
sleep 15

#创建 topic
/opt/kafka/bin/kafka-topics.sh --create --zookeeper localhost:2181 --replication-factor 1 --partitions 1 --topic logs &

#查看topic列表
#/opt/kafka/bin/kafka-topics.sh --list --zookeeper localhost:2181

#查看kafka中数据是否进入
#/opt/kafka/bin/kafka-console-consumer.sh --zookeeper localhost:2181 --topic logs
```

#### 5.4.2.4 Makefile
Makefile  内容如下：
```
TAG = v0.1
REGISTRY = reg.dhdc.com
USER = loggingefk
IMAGE = kafka

build:
	docker build -t $(REGISTRY)/$(USER)/$(IMAGE):$(TAG) .
push:
	docker push $(REGISTRY)/$(USER)/$(IMAGE):$(TAG)
```

#### 5.4.2.5 配置文件 server.properties
配置文件 server.properties 的内如如下：
```
broker.id=0
port=9092
num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
log.dirs=/opt/log/kafkalogs
num.partitions=1
num.recovery.threads.per.data.dir=1
log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000
log.cleaner.enable=false
zookeeper.connect=localhost:2181
zookeeper.connection.timeout.ms=6000
```
其中 zookeeper.connect 对应的 localhost 设置为对应 zookeeper 所在节点的节点名或 IP 地址，如果 zookeeper 与 kafka 同节点则无需修改。


### 5.4.3 kafka_es 镜像制作  
kafka_es 镜像是包含了 ES 连接器并启动运行该连接器，比 kafka 镜像需要多连接器部分的操作，详细内如如下所述。

#### 5.4.3.1 Dockerfile
Dockerfile 文件内容如下：
```
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
```

#### 5.4.3.2 setup.sh
安装 kafka 的操作脚本内容如下：
```
#!/bin/sh

cd  /opt
wget http://apache.fayea.com/kafka/0.10.0.0/kafka_2.10-0.10.0.0.tgz

tar -xf kafka_2.10-0.10.0.0.tgz
mv kafka_2.10-0.10.0.0 kafka
rm -rf kafka_2.10-0.10.0.0
rm -rf kafka_2.10-0.10.0.0.tgz

mkdir -p  /opt/log/kafkalogs
```

#### 5.4.3.3 run.sh
运行 kafak 及连接器的操作脚本如下：
```
#!/bin/sh

#/opt/kafka/bin/kafka-server-start.sh config/server.properties
#启动kafka 创建 topic
/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties  &
sleep 15
/opt/kafka/bin/kafka-topics.sh --create --zookeeper localhost:2181 --replication-factor 1 --partitions 1 --topic logs &
sleep 15
# 启动连接器
/opt/kafka/bin/connect-standalone.sh /opt/kafka/config/connect-standalone.properties /opt/kafka/config/elasticsearch-connect.properties &
#查看topic列表
#/opt/kafka/bin/kafka-topics.sh --list --zookeeper localhost:2181

#查看kafka中数据是否进入
#/opt/kafka/bin/kafka-console-consumer.sh --zookeeper localhost:2181 --topic logs
```

#### 5.4.3.4 Makefile
Makefile  内容如下：
```
TAG = v0.1
REGISTRY = reg.dhdc.com
USER = loggingefk
IMAGE = kafka_es

build:
	docker build -t $(REGISTRY)/$(USER)/$(IMAGE):$(TAG) .
push:
	docker push $(REGISTRY)/$(USER)/$(IMAGE):$(TAG)
```

#### 5.4.3.5 配置文件 server.properties
配置文件 server.properties 的内如如下：
```
broker.id=0
port=9092
num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
log.dirs=/opt/kafkalogs
num.partitions=1
num.recovery.threads.per.data.dir=1
log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000
log.cleaner.enable=false
zookeeper.connect=localhost:2181
zookeeper.connection.timeout.ms=6000
```
其中 zookeeper.connect 对应的 localhost 设置为对应 zookeeper 所在节点的节点名或 IP 地址，如果 zookeeper 与 kafka 同节点则无需修改。

#### 5.4.3.6 连接器配置文件及依赖包
配置文件 connect-standalone.properties、elasticsearch-connect.properties 见 5.2.3 和 5.2.4 小节的
依赖包 package 及其下的 13 个 jar 包来自 5.1.2 节之后的内容。

### 5.4.4 fluentd_kafka 镜像制作
#### 5.4.4.1 Dockerfile
Dockerfile 文件内容如下：
```
FROM reg.dhdc.com/loggingefk/fluentd:v1.0.1
COPY td-agent.conf /etc/td-agent/td-agent.conf
COPY start-fluentd.sh /start-fluentd.sh
RUN  td-agent-gem install fluent-plugin-kafka
ENTRYPOINT ["/bin/sh", "-c", "/start-fluentd.sh"]
```

#### 5.4.4.2 start-fluentd.sh
运行 fluentd 的操作脚本内容如下：
```
#!/bin/bash
/usr/sbin/td-agent 2>&1 >> /var/log/fluentd.log &

while true
do
	sleep 10
done
```

#### 5.4.4.3 fluentd 配置文件 td-agent.conf
配置文件 td-agent.conf 如下（改变之处主要是输出到了 Kafka）：
```
# Do not directly collect fluentd's own logs to avoid infinite loops.
<match fluentd.**>
  type null
</match>

<match fluent.**>
  type null
</match>

# Example:
# {"log":"[info:2016-02-16T16:04:05.930-08:00] Some log text here\n","stream":"stdout","time":"2016-02-17T00:04:05.931087621Z"}
<source>
  type tail
  path /var/log/containers/*.log
  exclude_path /var/log/containers/fluentd-elasticsearch*.log
  pos_file /var/log/es-containers.log.pos
  time_format %Y-%m-%dT%H:%M:%S.%N%Z
  tag kubernetes.*
  format  json
  time_key key3
  read_from_head true
  enable_watch_timer true
#  refresh_interval 5
  read_lines_limit 200
  rotate_wait 5
</source>


<filter kubernetes.**>
  type kubernetes_metadata
  kubernetes_url http://172.25.3.194:8080
</filter>

<match **>
  @type kafka
  brokers localhost:9092
  zookeeper localhost:2181
  default_topic logs
  output_data_type json
  # Brokers: you can choose either brokers or zookeeper.
  #brokers        10.35.48.172:9092  # Set brokers directly
#  zookeeper      10.35.48.172:2181 # Set brokers via Zookeeper
#  zookeeper_path <broker path in zookeeper> :default => /brokers/ids # Set path in zookeeper for kafka

#  default_topic  mykafka
#  default_partition_key (string) :default => nil
#  default_message_key   (string) :default => nil
  output_data_type       json
  output_include_tag     true
  output_include_time    false
  exclude_topic_key      flase
  exclude_partition_key  false

  # ruby-kafka producer options
#  max_send_retries    (integer)     :default => 1
#  required_acks       (integer)     :default => -1
#  ack_timeout         (integer)     :default => nil (Use default of ruby-kafka)
#  compression_codec   (gzip|snappy) :default => nil
#  max_buffer_size     (integer)     :default => nil (Use default of ruby-kafka)
#  max_buffer_bytesize (integer)     :default => nil (Use default of ruby-kafka)
</match>
```
其中 brokers 和 zookeeper 对应的 localhost 设置为对应 kafka、zookeeper 所在节点的节点名或 IP 地址，如果 zookeeper 与 kafka 同节点则无需修改。如果是 kafka 或 zookeeper 集群，则对应的各个hostIP:Port 之间以逗号隔开，如：
```
brokers 192.168.0.1:9092，192.168.0.2:9092，192.168.0.3:9092
zookeeper 192.168.1.1:2181，192.168.1.2:2181，192.168.1.3:2181
```

#### 5.4.4.4 Makefile
Makefile  内容如下：
```
TAG = v0.1
REGISTRY = reg.dhdc.com
USER = loggingefk
IMAGE = fluentd_kafka

build:
	docker build -t $(REGISTRY)/$(USER)/$(IMAGE):$(TAG) .
push:
	docker push $(REGISTRY)/$(USER)/$(IMAGE):$(TAG)
```


### 5.4.5 Docker 化部署 FKEK (Fluentd->Kafka->ElasticSearch->Kibana)
#### 5.4.5.1 启动 zookeeper 容器
使用如下命令启动 zookeeper ：

```
mkdir -p /mnt/zookeeperdata /mnt/zookeeperlog
docker run -dit --net=host --restart=always -v /mnt/zookeeperdata:/opt/data/zookeeperdata:rw -v /mnt/zookeeperlog:/opt/log/zookeeplogs:rw reg.dhdc.com/loggingefk/zookeeper:v0.1
```

#### 5.4.5.2 启动 kafka 容器
使用如下命令启动 kafka ：

```
mkdir -p /mnt/kafkalog
docker run -dit --net=host --restart=always -v /mnt/kafkalog:/opt/log/kafkalogs:rw reg.dhdc.com/loggingefk/kafka:v0.1
```

如果要启动连接到 ES 的 kafka 容器，则将上述 kafka:v0.1 镜像替换为 kafka_es:v0.1

#### 5.4.5.3 启动 Elasticsearch 容器
第一次部署时，在宿主机(如 172.25.3.194)上建立 ES 数据存储空间：
```
    mkdir /es/data
    chmod 777  -R /es
```
使用如下命令启动 ElasticSearch 容器

```
    docker run -it -p 127.0.0.1:9200:9200 --net=host --restart=always -v /es/data:/usr/elasticsearch/elasticsearch-2.4.1/data    reg.dhdc.com/loggingefk/elasticsearch:v1.0.1
```

#### 5.4.5.4 启动 kibana 容器
使用如下命令启动 Kibana 容器
```
docker run -it -p 127.0.0.1:5601:5601 --net=host --restart=always reg.dhdc.com/loggingefk/kibana:v1.0.1
```

#### 5.4.5.5 启动 fluentd_kafka 容器
使用如下命令启动 fluentd_kafka 容器:
```
docker run -it --net=host --restart=always -v /var/log/containers:/var/log/containers  -v /var/lib/docker:/var/lib/docker reg.dhdc.com/loggingefk/fluentd_kafka:v0.1
```



# 6.  Fluentd->Kafka->Logstash->Es->Kibana  的 FKLEK 日志Docker 环境部署
## 6.1 fluentd_kafka 镜像构建
Fluentd 输出数据到 Kafka 对应的镜像 fluentd_kafka:v0.1 的构建如 5.4.4 节所述，需要的注意的是配置文件中对应的 brokers 和 zookeeper 对应的IP地址或主机名需要根据实际情况修改；

## 6.2 kafka 镜像构建
Kafka 对应的镜像 kafka:v0.1 的构建如 5.4.2 节所述，需要的注意的是配置文件中参数 zookeeper.connect 对应的IP地址或主机名需要根据实际情况修改；

## 6.3 zookeeper 镜像构建
zookeeper 对应的镜像 zookeeper:v0.1 的构建如 5.4.1 节所述，需要的注意的是如果是多节点的 zookeeper，需要增加相应的配置参数；

## 6.4 elasticsearch 镜像构建  
直接使用镜像 reg.dhdc.com/loggingefk/elasticsearch:v1.0.1

## 6.5 kibana 镜像构建  
直接使用镜像 reg.dhdc.com/loggingefk/kibana:v1.0.1

## 6.6 Logstash 镜像构建  
###  6.6.1 Dockerfile  
Dockerfile 文件内容如下：
```
FROM after4u/ubuntu-jdk8
COPY setup.sh /opt/setup.sh
RUN /opt/setup.sh
RUN mkdir -p /opt/logstash/conf
COPY logstash.conf /opt/logstash/conf/
COPY run.sh /opt/run.sh
ENTRYPOINT ["/bin/sh", "-c", "/opt/run.sh;while true; do sleep 60; done"]
```
其中 setup.sh 用于安装 logstash，run.sh 用于启动运行 logstash

### 6.6.2 setup.sh  
安装 logstash 的操作脚本内容如下：
```
#!/bin/sh

cd  /opt
curl -O https://download.elasticsearch.org/logstash/logstash/logstash-2.4.1.tar.gz

tar -xf logstash-2.4.1.tar.gz
mv logstash-2.4.1 logstash
rm -rf logstash-2.4.1.tar.gz
```

### 6.6.3 run.sh  
运行 logstash 的操作脚本如下：
```
#!/bin/sh

#启动 logstash
/opt/logstash/bin/logstash  -f /opt/logstash/conf/logstash.conf &
```

### 6.6.4 配置文件conf/logstash.conf  
配置文件 conf/logstash.conf 的内容如下：
```
input{
    kafka {
        codec => "plain"
        group_id => "logstash1"
        auto_offset_reset => "smallest"
        reset_beginning => true
        topic_id => "logs"
        #white_list => ["hello"]
        #black_list => nil
        zk_connect => "localhost:2181" # zookeeper的地址
	codec => json
   }

}

filter {
    json {
        source => "message"
        #target => "doc"
        remove_field => ["message"]
    }
}

output {
  # for debugging
#  stdout {
#  }

  elasticsearch {
    hosts => "localhost:9200"
#    index => "logwong"
  }
}

```


### 6.6.5 Makefile  
Makefile  内容如下：
```
TAG = v0.1
REGISTRY = reg.dhdc.com
USER = loggingefk
IMAGE = logstash

build:
	docker build -t $(REGISTRY)/$(USER)/$(IMAGE):$(TAG) .
push:
	docker push $(REGISTRY)/$(USER)/$(IMAGE):$(TAG)
```

## 6.7 部署 FKLEK 日志Docker 环境部署  
步骤如下：

### 6.7.1 部署 ES 容器  
第一次部署时，在宿主机(如 172.25.3.194)上建立 ES 数据存储空间：
```
mkdir /es/data        #第一次运行时需要创建对应目录
chmod 777  -R /es
```
使用如下命令部署 ElasticSearch
```
docker run -it -p 127.0.0.1:9200:9200 --net=host --restart=always -v /es/data:/usr/elasticsearch/elasticsearch-2.4.1/data    reg.dhdc.com/loggingefk/elasticsearch:v1.0.1
```
镜像创建的容器启动后会自动完成 ES 创建, 映射模板更新的工作

###6.7.2 部署 Kibana 容器  
在 ElasticSearch 所在的主机(172.25.3.194)上执行如下命令部署 Kibana：
```
docker run -it -p 127.0.0.1:5601:5601 --net=host --restart=always reg.dhdc.com/loggingefk/kibana:v1.0.1
```
Kibana 容器正常运行后会自动完成 Kibana 的启动工作

### 6.7.3 部署 zookeeper 容器
使用如下命令启动 zookeeper ：

```
mkdir -p /mnt/zookeeperdata /mnt/zookeeperlog   #第一次运行时需要创建对应目录
docker run -dit --net=host --restart=always -v /mnt/zookeeperdata:/opt/data/zookeeperdata:rw -v /mnt/zookeeperlog:/opt/log/zookeeplogs:rw reg.dhdc.com/loggingefk/zookeeper:v0.1
```

### 6.7.4 部署 kafka 容器  
使用如下命令启动 kafka ：

```
mkdir -p /mnt/kafkalog   #第一次运行时需要创建对应目录
docker run -dit --net=host --restart=always -v /mnt/kafkalog:/opt/log/kafkalogs:rw reg.dhdc.com/loggingefk/kafka:v0.1
```
### 6.7.5 部署 logstash 容器  
使用如下命令启动 kafka ：
docker run -it  --net=host  --restart=always reg.dhdc.com/loggingefk/logstash:v0.1

### 6.7.6 部署 fluentd_kafka 容器  
使用如下命令启动 fluentd_kafka 容器:
```
docker run -it --net=host --restart=always -v /var/log/containers:/var/log/containers  -v /var/lib/docker:/var/lib/docker reg.dhdc.com/loggingefk/fluentd_kafka:v0.1
```





## 附录：命令行操作
### 启动zk
```
  bin/zookeeper-server-start.sh config/zookeeper.properties &
```

### 启动kafka
```
  bin/kafka-server-start.sh config/server.properties
```
### 创建名称为 logs 的 topic
```
  bin/kafka-topics.sh --create --zookeeper localhost:2181 --replication-factor 1 --partitions 1 --topic logs
```

### 查看topic列表
```
  bin/kafka-topics.sh --list --zookeeper localhost:2181
```

### 查看kafka中对应的 topic 中是否有数据进入
```
  bin/kafka-console-consumer.sh --zookeeper localhost:2181 --topic syslog-topic
```

### 启动 logstash
```
  ./bin/logstash  -f conf/logstash.conf
```  
  
    
    



##  TODO： 以 分布式 模式运行 Kafka Connect Elasticsearch
参考链接： https://sematext.com/blog/2017/03/06/kafka-connect-elasticsearch-how-to/

以 Standalone 模式和分布式模式运行 Connector 的区别是 Kafka Connect 在哪里存储配置文件、怎样分配 work、在哪里存储偏移和任务状态

### 配置文件 connect-distributed.properties

```
bootstrap.servers=localhost:9092
key.converter=org.apache.kafka.connect.json.JsonConverter
value.converter=org.apache.kafka.connect.json.JsonConverter
key.converter.schemas.enable=false
value.converter.schemas.enable=false
internal.key.converter=org.apache.kafka.connect.json.JsonConverter
internal.value.converter=org.apache.kafka.connect.json.JsonConverter
internal.key.converter.schemas.enable=false
internal.value.converter.schemas.enable=false
offset.flush.interval.ms=10000
group.id=connect-cluster
offset.storage.topic=connect-offsets
config.storage.topic=connect-configs
status.storage.topic=connect-status
```

新配置项的解释：
(1) group.id=connect-cluster ： Kafka Connect group 的集群识别符。应该是唯一的，不能干扰消费者从给定的Kafka群集中读取数据。  
(2) offset.storage.topic=connect-offsets ：Kafka Connect 用来存储偏移信息的 topic 的名字；理论上该 topic 后面有多个分区，被复制和配置用于压缩。  
(3) config.storage.topic=connect-configs： Kafka Connect 用来存储配置信息的 topic 的名字；理论上该 topic 配置是有单个分区，并且高度复制。  
(4) status.storage.topic=connect-status：Kafka Connect 用来存储 work status 信息的 topic 的名字；理论上该 topic 有多个分区、副本并且被压缩。 

### 以分布式模式启动 connector
命令如下：
```
  bin/connect-distributed.sh config/connect-distributed.properties
```
当以分布式模式运行 Kafka Connect 的时候，需要使用 REST API 创建 connectors 。
