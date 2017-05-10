# 1.Kubelet 概述  
每个节点上都运行一个kubelet服务进程，默认监听10250端口，接收并执行master发来的指令，管理Pod及Pod中的容器。每个kubelet进程会在API Server上注册节点自身信息，定期向master节点汇报节点的资源使用情况，并通过cAdvisor监控节点和容器的资源。 
  
## 1.1 节点管理  
节点管理主要是节点自注册和节点状态更新：  
(1) Kubelet可以通过设置启动参数 --register-node 来确定是否向API Server注册自己；  
(2) 如果Kubelet没有选择自注册模式，则需要用户自己配置Node资源信息，同时需要告知Kubelet集群上的API Server的位置；  
(3) Kubelet在启动时通过API Server注册节点信息，并定时向API Server发送节点新消息，API Server在接收到新消息后，将信息写入etcd   
   
## 1.2 Pod管理  
### 1.2.1 获取Pod清单  
Kubelet以PodSpec的方式工作。PodSpec是描述一个Pod的YAML或JSON对象。 kubelet采用一组通过各种机制提供的PodSpecs（主要通过apiserver），并确保这些PodSpecs中描述的Pod正常健康运行。  
  
  向Kubelet提供节点上需要运行的Pod清单的方法：  
  (1) 文件：启动参数 --config 指定的配置目录下的文件(默认/etc/kubernetes/manifests/)。该文件每20秒重新检查一次（可配置）。  
  (2) HTTP endpoint (URL)：启动参数 --manifest-url 设置。每20秒检查一次这个端点（可配置）。  
  (3) API Server：通过API Server监听etcd目录，同步Pod清单。  
  (4) HTTP server：kubelet侦听HTTP请求，并响应简单的API以提交新的Pod清单。  
        
### 1.2.2 通过API Server获取Pod清单及创建Pod的过程  
Kubelet通过API Server Client(Kubelet启动时创建)使用Watch加List的方式监听"/registry/nodes/$当前节点名"和“/registry/pods”目录，将获取的信息同步到本地缓存中。  
  
  Kubelet监听etcd，所有针对Pod的操作都将会被Kubelet监听到。如果发现有新的绑定到本节点的Pod，则按照Pod清单的要求创建该Pod。 
    
  如果发现本地的Pod被修改，则Kubelet会做出相应的修改，比如删除Pod中某个容器时，则通过Docker Client删除该容器。  
  如果发现删除本节点的Pod，则删除相应的Pod，并通过Docker Client删除Pod中的容器。  
  
  Kubelet读取监听到的信息，如果是创建和修改Pod任务，则执行如下处理：  
  (1) 为该Pod创建一个数据目录；  
  (2) 从API Server读取该Pod清单；  
  (3) 为该Pod挂载外部卷；  
  (4) 下载Pod用到的Secret；  
  (5) 检查已经在节点上运行的Pod，如果该Pod没有容器或Pause容器没有启动，则先停止Pod里所有容器的进程。如果在Pod中有需要删除的容器，则删除这些容器；  
  (6) 用“kubernetes/pause”镜像为每个Pod创建一个容器。Pause容器用于接管Pod中所有其他容器的网络。每创建一个新的Pod，Kubelet都会先创建一个Pause容器，然后创建其他容器。  
  (7) 为Pod中的每个容器做如下处理：       
    a. 为容器计算一个hash值，然后用容器的名字去Docker查询对应容器的hash值。若查找到容器，且两者hash值不同，则停止Docker中容器的进程，并停止与之关联的Pause容器的进程；若两者相同，则不做任何处理；  
    b. 如果容器被终止了，且容器没有指定的restartPolicy，则不做任何处理；  
    c. 调用Docker Client下载容器镜像，调用Docker Client运行容器。
  
### 1.2.3 Static Pod  
所有以非API Server方式创建的Pod都叫Static Pod。Kubelet将Static Pod的状态汇报给API Server，API Server为该Static Pod创建一个Mirror Pod和其相匹配。Mirror Pod的状态将真实反映Static Pod的状态。当Static Pod被删除时，与之相对应的Mirror Pod也会被删除。  
      
## 1.3  容器健康检查  
Pod通过两类探针检查容器的健康状态:  
(1) LivenessProbe 探针：用于判断容器是否健康，告诉Kubelet一个容器什么时候处于不健康的状态。如果LivenessProbe探针探测到容器不健康，则Kubelet将删除该容器，并根据容器的重启策略做相应的处理。如果一个容器不包含LivenessProbe探针，那么Kubelet认为该容器的LivenessProbe探针返回的值永远是“Success”；  
(2)ReadinessProbe：用于判断容器是否启动完成且准备接收请求。如果ReadinessProbe探针探测到失败，则Pod的状态将被修改。Endpoint Controller将从Service的Endpoint中删除包含该容器所在Pod的IP地址的Endpoint条目。  
  Kubelet定期调用容器中的LivenessProbe探针来诊断容器的健康状况。LivenessProbe包含如下三种实现方式：  
  (1) ExecAction：在容器内部执行一个命令，如果该命令的退出状态码为0，则表明容器健康；  
  (2) TCPSocketAction：通过容器的IP地址和端口号执行TCP检查，如果端口能被访问，则表明容器健康；   
  (3) HTTPGetAction：通过容器的IP地址和端口号及路径调用HTTP GET方法，如果响应的状态码大于等于200且小于400，则认为容器状态健康。  
    
LivenessProbe探针包含在Pod定义的spec.containers.{某个容器}中。  
  
## 1.4 cAdvisor资源监控  
Kubernetes集群中，应用程序的执行情况可以在不同的级别上监测到，这些级别包括：容器、Pod、Service和整个集群。  
Heapster项目为Kubernetes提供了一个基本的监控平台，它是集群级别的监控和事件数据集成器(Aggregator)。Heapster以Pod的方式运行在集群中，Heapster通过Kubelet发现所有运行在集群中的节点，并查看来自这些节点的资源使用情况。Kubelet通过cAdvisor获取其所在节点及容器的数据。Heapster通过带着关联标签的Pod分组这些信息，这些数据将被推到一个可配置的后端，用于存储和可视化展示。支持的后端包括InfluxDB(使用Grafana实现可视化)和Google Cloud Monitoring。  
cAdvisor是一个开源的分析容器资源使用率和性能特性的代理工具，已集成到Kubernetes代码中。cAdvisor自动查找所有在其所在节点上的容器，自动采集CPU、内存、文件系统和网络使用的统计信息。cAdvisor通过它所在节点机的Root容器，采集并分析该节点机的全面使用情况。  
cAdvisor通过其所在节点机的4194端口暴露一个简单的UI。    
  








## 1.1 小细节记录
(1) LockFilePath  
Kubelet 需要一个文件作为 lock file 来与其他运行的 kubelet 进行通信.这个文件路径名就是 LockFilePath

(2) ExitOnLockContention  
ExitOnLockContention是一个标志，表示 kubelet 以“bootstrap”模式运行，设置这个参数为 true 时需要同时设置 LockFilePath. 设置该参数为 true 将使得 kubelet 监听 lock file 上的 inotify 事件，当其他进程试图打开该文件时则释放该文件锁并退出.

(3) 容器健康检查  
在创建了容器之后，Kubelet 要查看容器是否正常运行，如果容器运行出错，需要根据设置的重启策略进行处理。检查容器是否健康主要有两种方式：在容器中执行命令(获取 exit code)和通过 HTTP 访问预定义的 endpoint（获取 response code）.

(4) cAdvisor  
Kubelet 通过 cAdvisor 监控容器和节点资源.


(5) 容器配置清单  
Kubelet 从配置文件或者从 etcd server 上同步容器配置清单。容器配置清单是一个描述 pod 的文件。Kubelet 负责管理容器配置清单描述的容器的启动和持续运行。提供给 kubelet 容器清单的方式有如下几种：

    ① 文件： 通过命令行参数传递。每20s会重新检查一次文件的配置更新；
    ② HTTP URL:通过命令行参数传递HTTP URL参数。 此端点每20秒检查（也可配置）, 通过查询获得容器清单;
    ③ Etcd Server: Kubelet发现etcd服务器并watch相关的key，在观察到容器配置更新后立即采取相应的行动。
    
    

## Pod Manager  
(1) Manager 存储和管理对Pods的访问，维护Static Pod和Mirror Pod 之间的映射  
(2) kubelet 从3种 sources发现pod更新：file、http、APIServer。Source不是apiserver的pods称为static pods，API server不感知static pods的存在情况。为了监控Static Pods的状态，kubelet通过API server为每个static pod创建一个mirror pod  
(3) mirror pod具有与其static pod相同的pod全名(name和namespace)，但元数据不同(如UID等)。 通过利用kubelet使用pod全名报告pod状态的事实，mirror pod的状态总是反映static pod的实际状态。 当static pod被删除时，相关联的孤儿mirror pod也将被删除。

## Kubelet Container Cache  
Cache 存储pod的PodStatus，表示container runtime中“所有”可见的pods/containers。所有的缓存条目(cache entries)至少与全局时间戳记（由UpdateTime()设置）一样新或更新，而单个条目可能比全局时间戳稍微新。 如果一个pod没有runtime已知的状态，Cache将返回一个填充ID的空的PodStatus对象。  

Cache提供两种方法取回PodStatus：  
(1) 使用非阻塞的Get()方法  
(2) 使用阻塞的GetNewerThan()方法，这种方法调用时会阻塞直到对应的PodStatus的状态比指定时间更新的时候才会返回该状态  
负责填充cache的组件调用Delete()来显式释放高速缓存条目。  
   
   Cache的主要构成：  
   (1) 读写互斥锁RWMutex保护数据。RWMutex锁可以被任意多的reader或者单个writer持有。RWMutexes可以作为其他结构的一部分创建; RWMutex的零值是未锁定的互斥量。首次使用后，不得复制RWMutex。如果一个goroutine持有一个RWMutex进行读取，那么在第一个读锁定被释放之前，不能指望这个goroutine或者其他goroutine也可以获取读锁。 特别地，禁止递归读锁。 这是为了确保锁最终变得可用; 阻塞的锁调用会排除新reader获取锁定。  
   (2) Cache使用map的方式存储Pod的状态信息。  
   (3) 用全局timestamp表示缓存数据的fresh程度。所有缓存内容至少比此时间戳要更新。注意，初始化后的时间戳为零，只有在准备好服务缓存状态时，时间戳才会变为非零。  
   
   
## syncPod 
syncPod是用于同步单个pod的事务脚本(transaction script)，syncPod的主要流程如下：  
(1) 如果 pod被创建，记录pod worker启动延迟  
(2) 调用generateAPIPodStatus来为pod准备一个api.PodStatus  
(3) 如果pod被看作是第一次运行，则记录pod启动延迟  
(4) 更新状态管理器中的pod的状态  
(5) 如果Pod不应该运行，杀死该pod  
(6) 如果pod是一个静态pod且还没有对应的mirror pod，则创建mirror pod  
(7) 创建pod的数据目录(如果不存在)  
(8) 等待卷附加/挂载  
(9) 获取pod的pull secrets  
(10) 调用container runtime的SyncPod回调函数  
(11) 更新pod的入口和出口限制的流量  

  
syncPod的sync操作有四种类型：  
(1) SyncPodSync： 同步pod以达到期望的状态  
(2) SyncPodUpdate：从source更新pod  
(3) SyncPodCreate：从source创建pod  
(4) SyncPodKill：杀死pod  
  
## SyncPod 时计算Pod的container改变情况  
调用SyncPod()函数执行Pod同步的第一步就是计算pod中的container的改变情况，用podContainerChangesSpec来表示，包含如下字段：  
(1) StartInfraContainer，布尔型，如果是true，则需要启动新的Infra Container，旧的Infra Container则需要删除(如果在运行)。此外，如果startInfraContainer为true，则containersToKeep字段则必须为空；  
(2) InfraChanged，布尔型，  
(3) InfraContainerId，当且仅当startInfraContainer为false时，才必须设置infraContainerId。 它存储运行的Infra Container的dockerID；  
(4) InitFailed，布尔型，  
(5) InitContainersToKeep，存储所有init containers。  
(6) ContainersToStart，保存必须启动的容器Specs的indices，以及容器启动的原因。  
(7) ContainersToKeep，存储那些应当保持运行状态的容器的dockerID到容器的Specs的indices的映射。 如果startInfraContainer为false，那么它包含一个infraContainerId（映射到-1）的条目。不应该有ContainerToStart为空且ContainerToKeep仅包含InfraContainerId的情况。 在这种情况下，Infra Container应该被杀死，因此它从该map中删除。  
所有不在ContainersToKeep和InitContainersToKeep中的运行状态的containers需要被杀掉。  


  
## Init Container 和 Pet Set  
### 什么是Init Container？
从名字来看就是做初始化工作的容器。可以有一个或多个，如果有多个，这些Init Container按照定义的顺序依次执行，只有所有的Init Container执行完后，主容器才启动。由于一个Pod里的存储卷是共享的，所以InitContainer里产生的数据可以被主容器使用到。

Init Container可以在多种K8S资源里被使用到如Deployment、Daemon Set, Pet Set, Job等，但归根结底都是在Pod启动时，在主容器启动前执行，做初始化工作。

#### Init Container使用场景

第一种场景是等待其它模块Ready，比如我们有一个应用里面有两个容器化的服务，一个是Web Server，另一个是数据库。其中Web Server需要访问数据库。但是当我们启动这个应用的时候，并不能保证数据库服务先启动起来，所以可能出现在一段时间内Web Server有数据库连接错误。为了解决这个问题，我们可以在运行Web Server服务的Pod里使用一个InitContainer，去检查数据库是否准备好，直到数据库可以连接，Init Container才结束退出，然后Web Server容器被启动，发起正式的数据库连接请求。

第二种场景是做初始化配置，比如集群里检测所有已经存在的成员节点，为主容器准备好集群的配置信息，这样主容器起来后就能用这个配置信息加入集群。

还有其它使用场景，如将pod注册到一个中央数据库、下载应用依赖等。

这些东西能够放到主容器里吗？从技术上来说能，但从设计上来说，可能不是一个好的设计。首先不符合单一职责原则，其次这些操作是只执行一次的，如果放到主容器里，还需要特殊的检查来避免被执行多次。    
   ![](/home/wong/桌面/111.png)   
   
#### 什么是Pet Set？  
  在数据结构里Set是集合的意思，所以顾名思义PetSet就是Pet的集合，那什么是Pet呢？我们提到过Cattle和Pet的概念，Cattle代表无状态服务，而Pet代表有状态服务。具体在K8S资源对象里，Pet是一种需要特殊照顾的Pod。它有状态、有身份、当然也比普通的Pod要复杂一些。  
  ![](/home/wong/桌面/222.png)   
  具体来说，一个Pet有三个特征：  

一是有稳定的存储，通过PV/PVC来实现的。

二是稳定的网络身份，这是通过一种叫Headless Service的特殊Service来实现的。Service可以为多个Pod实例提供一个稳定的对外访问接口。这个稳定的接口是通过Cluster IP来实现的，Cluster IP是一个虚拟IP，不是真正的IP，所以稳定。K8S会在每个节点上创建一系列的IPTables规则，实现从Cluster IP到实际Pod IP的转发。同时还会监控这些Pod的IP地址变化，如果变了，会更新IP Tables规则，使转发路径保持正确。所以即使Pod IP有变化，外部照样能通过Service的ClusterIP访问到后面的Pod。

普通Service的Cluster IP是对外的，用于外部访问多个Pod实例。而HeadlessService的作用是对内的，用于为一个集群内部的每个成员提供一个唯一的DNS名字，这样集群成员之间就能相互通信了。所以Headless Service没有Cluster IP，这是它和普通Service的区别。

Headless Service为每个集群成员创建的DNS名字是什么样的呢？下图右下角是一个例子，第一个部分是每个Pet自己的名字，后面foo是Headless Service的名字，default是PetSet所在命名空间的名字，cluser.local是K8S集群的域名。对于同一个Pet Set里的每个Pet，除了Pet自己的名字，后面几部分都是一样的。所以要有一个稳定且唯一的DNS名字，就要求每个Pet的名字是稳定且唯一的。

三是序号命名规则。Pet是一种特殊的Pod，那么Pet能不能用Pod的命名规则呢？答案是不能，因为Pod的名字是不稳定的。Pod的命名规则是，如果一个Pod是由一个RC创建的，那么Pod的名字是RC的名字加上一个随机字符串。为什么要加一个随机字符串，是因为RC里指定的是Pod的模版，为了实现高可用，通常会从这个模版里创建多个一模一样的Pod实例，如果没有这个随机字符串，同一个RC创建的Pod之间就会由名字冲突。

如果说某个Pod由于某种原因死掉了，RC会新建一个来代替它，但是这个新建里的Pod名字里的随机字符串与原来死掉的Pod是不一样的。所以Pod的名字跟它的IP一样是不稳定的。

为了解决名字不稳定的问题，K8S对Pet的名字不再使用随机字符串，而是为每个Pet分配一个唯一不变的序号，比如Pet Set的名字叫mysql，那么第一个启起来的Pet就叫mysql-0，第二个叫mysql-1，如此下去。

当一个Pet down掉后，新创建的Pet会被赋予跟原来Pet一样的名字。由于Pet名字不变所以DNS名字也跟以前一样，同时通过名字还能匹配到原来Pet用到的存储，实现状态保存。
![](/home/wong/桌面/333.png)      

Pet Set相关的一些操作：  
(1) Peer discovery，这和我们上面的Headless Service有密切关系。通过Pet Set的Headless Service，可以查到该Service下所有的Pet的DNS名字。这样就能发现一个Pet Set里所有的Pet。当一个新的Pet起来后，就可以通过PeerDiscovery来找到集群里已经存在的所有节点的DNS名字，然后用它们来加入集群。  
(2)更新Replicas的数目、实现扩容和缩容。  
(3)更新Pet Set里Pet的镜像版本，实现升级。  
(4) 删除Pet Set。删除一个Pet Set会先把这个Pet Set的Replicas数目缩减为0，等到所有的Pet都被删除了，再删除Pet Set本身。注意Pet用到的存储不会被自动删除。这样用户可以把数据拷贝走了，再手动删除。

把这些特性和有状态集群服务关联起来串一下，可以用Pet Set来管理一个有状态服务集群，Pet Set里每个Pet对应集群的一个成员，集群的初始化可以用Init Container来完成。集群里每个成员的状态由Volume, Persistent Volume来存储，集群里每个Pet唯一的DNS名字通过Headless Service来提供，集群里的成员之间就可以通过这个名字，相互通信。
   
  
   
    
  
    
## Kubernetes 的 Events  
Kubernetes Events存储在Etcd里，记录了集群运行所遇到的各种大事件。  
Message属于Kubernetes的一种特殊的资源：Events。  
kubectl get一些资源的时候可以通过它的-o json参数得到该资源的json格式的信息描述，那么Events进行kubectl get events -o json > /tmp/events.json，得到了一个json数组，里面的每一条都对应着一个Events对象。  
在Kubernetes资源的数据结构定义中，一般都会包含一个metav1.TypeMeta和一个ObjectMeta成员，TypeMeta里定义了该资源的类别和版本，对应我们平时写json文件或者yaml文件时的kind: Pod和apiVersion: v1。OjbectMeta里定义了该资源的元信息，包括名称、命名空间、UID、创建时间、标签组等。  
Events的数据结构定义里同样包含了metav1.TypeMeta和ObjectMeta。  
Events的真名。仔细观察它的名字，发现它由三部分构成：”发生该Events的Pod名称” + “.” + “神秘数字串”。“神秘数字串”实际上是“t.UnixNano())”。  
终于找到了Events的真身，原来它是Kubelet负责用来记录多个容器运行过程中的事件，命名由被记录的对象和时间戳构成。  
  
  在DockerManager里定义了EventRecorder的成员，它的方法Event()、Eventf()、PastEventf()都可以用来构造Events实例，略有区别的地方是Eventf()调用了Sprintf()来输出Events message，PastEventf()可创建指定时间发生的Events。  
  
  一方面可以推测所有拥有EventsRecorder成员的Kubernetes资源定义都可以产生Events。经过暴力搜索发现，EventsRecorder主要被K8s的重要组件ControllerManager和Kubelet使用。比如，负责管理注册、注销等的NodeController，会将Node的状态变化信息记录为Events。DeploymentController会记录回滚、扩容等的Events。他们都在ControllerManager启动时被初始化并运行。与此同时Kubelet除了会记录它本身运行时的Events，比如：无法为Pod挂载卷、无法带宽整型等，还包含了一系列像docker_manager这样的小单元，它们各司其职，并记录相关Events。  
  另一方面在调查的时候发现，Events分为两类，并定义在kubernetes/pkg/api/types.go里，分别是EventTypeNormal和EventTypeWarning，它们分别表示该Events“仅表示信息，不会造成影响”和“可能有些地方不太对”。  
    
### Event来龙去脉
 Event由Kubernetes的核心组件Kubelet和ControllerManager等产生，用来记录系统一些重要的状态变更。ControllerManager里包含了一些小controller，比如deployment_controller，它们拥有EventBroadCaster的对象，负责将采集到的Event进行广播。Kubelet包含一些小的manager，比如docker_manager，它们会通过EventRecorder输出各种Event。当然，Kubelet本身也拥有EventBroadCaster对象和EventRecorder对象。

EventRecorder通过generateEvent()实际生成各种Event，并将其添加到监视队列。我们通过kubectl get events看到的NAME并不是Events的真名，而是与该Event相关的资源的名称，真正的Event名称还包含了一个时间戳。Event对象通过InvolvedObject成员与发生该Event的资源建立关联。Kubernetes的资源分为“可被描述资源”和“不可被描述资源”。当我们kubectl describe可描述资源，比如Pod时，除了获取Pod的相应信息，还会通过FieldSelector获取相应的Event列表。Kubelet在初始化的时候已经指明了该Event的Source为Kubelet。

EventBroadcaster会将收到的Event交于各个处理函数进行处理。接收Event的缓冲队列长为25，不停地取走Event并广播给各个watcher。watcher由StartEventWatcher()实例产生，并被塞入EventBroadcaster的watcher列表里，后实例化的watcher只能获取后面的Event历史，不能获取全部历史。watcher通过recordEvent()方法将Event写入对应的EventSink里，最大重试次数为12次，重试间隔随机生成。

在写入EventSink前，会对所有的Events进行聚合等操作。将Events分为相同和相似两类，分别使用EventLogger和EventAggregator进行操作。EventLogger将相同的Event去重为1个，并通过计数表示它出现的次数。EventAggregator将对10分钟内出现10次的Event进行分组，依据是Event的Source、InvolvedObject、Type和Reason域。这样可以避免系统长时间运行时产生的大量Event冲击etcd，或占用大量内存。EventAggregator和EventLogger采用大小为4096的LRU Cache，存放先前已产生的不重复Events。超出Cache范围的Events会被压缩。
  
  