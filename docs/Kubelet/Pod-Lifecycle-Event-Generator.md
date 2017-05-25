# Kubelet: Pod Lifecycle Event Generator （PLEG）  
在Kubernetes中，Kubelet是运行在每个节点上的守护进程，用于管理节点上的pod，驱动pod状态以匹配其pod规范（specs）。 为了实现这一点，Kubelet需要对（1）pod规范和（2）容器状态的变化做出反应。 对于前者，Kubelet从多个来源 Wacth() pod规格的变化; 对于后者，Kubelet周期性(如 10s)轮询所有容器的最新状态。  
  
随着pod / container的数量增加，轮询的开销也在增加 ，并且因Kubelet的并行性开销加剧增加 ----每个pod一个worker（goroutine）单独查询容器运行时。 定期，并发，大量的请求导致CPU使用率高峰（即使没有Pod规范/状态更改）、性能差、以及由于容器运行时不堪重负而导致的可靠性问题。 最终，pod worker限制了Kubelet的可扩展性。  
  
## 目标和需求  
PLEG proposal 的目标是通过降低pod管理开销提高Kubelet的扩展性和性能。  

 * 在inactivity期间减少不必要的工作（无pod规格/容器状态更改）
 * 降低提交到容器运行时的并发请求的数量  
 
 设计方案需要通用以支持不同的容器运行时(如，Docker 和 rkt)  
 
## 设计方案概述
PLEG proposal目标是使用 pod  lifecycle event watch机制代替周期性论询机制。  
  
  ![](/home/wong/桌面/github_picture/pleg.png)   
    
## Pod Lifecycle Event
 Pod Lifecycle Event 在 pod级别抽象底层容器状态更改，使其与container runtime无关。 这层抽象将Kubelet与runtime细节隔离开来。  
   
	type PodLifeCycleEventType string

	const (
		ContainerStarted      PodLifeCycleEventType = "ContainerStarted"
		ContainerStopped      PodLifeCycleEventType = "ContainerStopped"	
		NetworkSetupCompleted PodLifeCycleEventType = "NetworkSetupCompleted"
		NetworkFailed         PodLifeCycleEventType = "NetworkFailed"
	)

	// PodLifecycleEvent is an event reflects the change of the pod state.
	type PodLifecycleEvent struct {
		// The pod ID.
		ID types.UID
		// The type of the event.
		Type PodLifeCycleEventType
		// The accompanied data which varies based on the event type.
		Data interface{}
	}
  
以使用Docker为例，启动 POD infra 容器被转换成NetworkSetupCompleted 的 Pod Lifecycle Event。  

## 通过Relisting 发现容器状态改变
为了生成pod生命周期事件，PLEG需要发现容器状态的变化。 可以通过定期 relisting所有的容器（例如，docker ps）来实现。 虽然目前与Kubelet的轮询类似，但它只能由单个线程（PLEG）执行。这样的好处是不会让索引的pod  worker 都会并发地与 container runtime 交互。 此外，只有相关的pod worker才会被唤醒以执行 pod 同步操作。  

relisting 的优势在于它与容器运行时无关，且无需外部依赖。

### Relist 周期
Relist周期越短，Kubelet就可以越早发现容器的状态变化。Relist周期越短也导致更高的CPU使用量。 此外，Relist 延迟取决于底层容器运行时，并且通常随着容器/ pod的数量的增加而增加。 应该根据测量值设置一个默认的relist周期。 不管relist周期设置为何值，都可能会显著短于当前的pod同步时间（10秒），也就是说相对于Pod状态的变化，Kubelet会更早地检测到容器的变化。  

## 对Pod Worker 控制流程的影响
Kubelet负责根据pod ID向相应的pod worker发送一个Event。 每个Event只会唤醒一个pod Worker。  

当前，Kubelet中的pod同步协程(syncing routine)是幂等的，因为它总是检查pod状态和规范(spec)，并尝试通过执行一系列操作来驱动状态以匹配规范。 本proposoal并不打算改变这个特性----不管Event类型如何，sync pod 协程都将执行必要的检查。 这为可靠性牺牲了一些效率，并且不需要构建与不同运行时兼容的状态机。  

## 利用上游容器事件 (Leverage Upstream Container Events)
除了依赖 relisting，PLEG可以利用提供容器事件的其他组件，并将这些事件转换成pod生命周期事件。 这将进一步提高Kubelet的响应速度，减少频繁 relisting 造成的资源浪费。  

上游容器事件可以是如下的来源：  
(1) 每个容器运行时提供的事件流  
Docker 的 API 公开了一个 event stream。但 rkt 还不支持这种 API，但 rkt 最终会支持。  
(2) cAdvisor cgroup的事件流  
cAdvisor集成在Kubelet中以提供容器统计信息。 它使用inotify监视cgroups容器并公开事件流。 虽然cAdvisor还不支持rkt，但是应该会直接添加这种支持。  

选项（1）可以提供更丰富的事件集，但是选项（2）具有跨运行时通用的优点，只要容器运行时使用cgroups即可。 不管现在选择实现什么，容器事件流应该使用明确定义的接口以插件的形式实现。  
请注意，由于有缺少事件的可能性，不能仅仅依靠上游容器事件。 PLEG可以低频率使用 relist，以确保不会丢失任何事件。

## 生成期望的事件
*对于只执行 relisting 的PLEG而言，本部分是可选的，但对监视上游事件的PLEG，本部分的内容则是必需的。*  

Pod worker 的行为可能产生 pod 生命周期事件（例如，创建/杀死一个容器），但 pod worker直到后来才会观察到。 pod worker应该忽略这些事件，以避免不必要的工作。  

例如，假设一个pod有两个容器A和B. Pod  worker

* 创建容器A
* 接收事件（ContainerStopped，B）
* 接收事件（ContainerStarted，A）

pod worker 应该忽略（ContainerStarted，A）事件，因为它是预期的。按理说，在观察到A的创建之前，pod worker 在收到（ContainerStopped，B）事件之时立即处理。但是，在 pod worker 的视角来看，最好等到预期的事件（ContainerStarted，A）被观察到以保持每个pod（per-pod）的一致。 因此，单个 pod worker 的控制流程应遵循以下规则：  
  
1. Pod Worker 应该按顺序处理事件。  
2. Pod Worker 应当直到它观察到上一次同步中自己的操作的结果才开始同步Pod操作，以保持一致的视图。

换句话说，Pod Worker 应该记录预期的事件，并且直到满足所有期望情况才唤醒以执行下一个同步操作。  

* 创建容器A，记录一个预期事件（ContainerStarted，A）
* 接收（ContainerStopped，B）; 存储事件并返回到sleep状态
* 接收（ContainerStarted，A）; 清除期望状态，前往处理（ContainerStopped，B）。

应该为每个预期事件设置一个超期时间，以防止Pod worker由于缺少事件而无限期地停滞。  

## v1.2 版本的 TODOs
对于v1.2，将添加一个通用的PLEG，周期性进行relisting，并留下采集容器事件以进一步处理。 不会对生成和过滤预期事件时最大限度地减少冗余同步做优化。  

* 使用 relisting 增加一个通用PLEG。 修改容器运行时接口以提供所有必需的信息，以调用GetPods（）发现容器状态的改变。  
* 对docker进行测试以调整 relisting 频率。
* 修复/调整依赖于频繁、周期性的pod同步的功能。
    * Liveness/Readiness探测：使用明确的容器探测周期创建一个单独的探测管理器。
    * 指示pod worker在同步失败时设置唤醒回调，以便可以重试。

