# Kubelet: Runtime Pod Cache
该proposal建立在Pod Lifecycle Event Generator（PLEG）之上。 它假定Kubelet订阅pod生命周期事件流，以消除对pod状态的周期性轮询。  

Runtime Pod Cache是存储所有pod的状态的内存缓存，由PLEG维护。 它作为内部pod状态的唯一真正来源，将Kubelet从查询容器运行时的操作中解放出来。  

## 动机
使用PLEG，Kubelet不再需要周期性对所有pod进行全面的状态检查。 当pod状态发生变化时，Kubelet指示pod worker开启同步操作。 然而，在每次同步期间，由于缺少先前状态的缓存，pod worker仍然需要通过检查pod中的所有容器（无论容器是死是活）来构建pod状态。 使用集成pod cache功能，可以进一步提高Kubelet的CPU使用率：  

1. 降低对container runtime 的并发请求，因为pod workers 不再需要单独查询 runtime；
2. 降低 inspect 请求的数量，因为在无状态改变的情况下无需 inspect 容器  

Runtime Cache 用以优化减少 pod workers 调用GetPods() 的次数，但是：  

* 该 Cache 不存储pod  worker完成同步所需的所有信息（例如，docker inspect）。 pod worker 仍然需要单独inspect容器以生成api.PodStatus。  
* pod worker有时需要绕过cache才能检索最新的pod状态。  

本 proposal 推荐使用cache并指示PLEG填充cache，以保证cache内容始终最新。  

**为什么每个pod worker不能缓存自己的pod状态？**

简短的答案是每个 pod worker 可以缓存自己的 pod 状态。 完善答案是本地化缓存限制了缓存内容的使用----其他组件无法访问，导致在多个地方缓存和/或传递对象，使控制流程复杂化。  

## Runtime Pod Cahe
Pod Cache 存储节点上所有 pods 的 `PodStatus` ，`PodStatus`包含从容器运行时生成 pod 的 `api.PodStatus` 所需的所有信息。  

![](/home/wong/github_picture/pod-cache.png)   

```go
// PodStatus表示pod及其容器的状态。
// api.PodStatus可以通过PodStatus和api.Pod得到。
type PodStatus struct {
    ID types.UID
    Name string
    Namespace string
    IP string
    ContainerStatuses []*ContainerStatus
}

// ContainerStatus 表示一个容器的状态
type ContainerStatus struct {
    ID ContainerID
    Name string
    State ContainerState
    CreatedAt time.Time
    StartedAt time.Time
    FinishedAt time.Time
    ExitCode int
    Image string
    ImageID string
    Hash uint64
    RestartCount int
    Reason string
    Message string
}
```
`PodStatus` 在Container Runtime Interface 接口中定义，因此对运行时不可知。  

PLEG 负责更新 pod cache entry，总是保持cache在最新状态：  
1. 识别容器状态的改变；  
2. inspect  pod 的详细信息  
3. 使用新的 PodStatus 更新 pod cache  

  * 如果 pod entry 没有真正改变，则不执行任何操作
  * 否则，产生并发送对应的 pod lifecycle event  
  
  注意在上面的（3）中，PLEG可以检查旧的和新的pod entry之间是否存在差异，以便根据需要过滤掉重复的Events。

### 逐出 cache entry
Pod cache表示容器运行时已知的所有pods /containers。 如果 pod 对容器运行时不再可见，则逐出该 pod 的cache entry。 PLEG负责删除cache 中的entries。  

### 生成 `api.PodStatus`
因为pod cache存储pod的最新PodStatus，所以Kubelet可以随时通过解释cache entry来生成api.PodStatus。 为了避免发送中间状态（例如，pod worker正在重新启动容器），将指示pod worker 在每次同步开始时生成一个新的状态。  

### Cache 竞争
当pod的数量很小时，缓存竞争不是问题。 当Kubelet扩展时，可以随时使用ID分割pods，以减少缓存竞争。  

### Disk 管理
pod cache不能满足容器/image垃圾回收器的需求，因为可能需要多于pod级别的信息。 这些组件仍然需要时间直接查询容器运行时。 可能会考虑为这些使用场景扩展缓存，但这些超出了本proposal的范围。  

## 对 Pod Worker 控制流的影响
Pod worker在同步期间可能执行各种操作（例如，启动/终止容器）。Pod worker 期望在下一次同步中看到这些操作的结果反映在缓存中。 或者，Pod worker 可以绕过缓存并直接查询容器运行时以获取最新的状态。 但不希望这么做，因为引入缓存能精确消除不必要的并发查询。 因此，应该阻塞 pod worker，直到PLEG将所有预期的结果更新到缓存。  

根据使用的PLEG类型，检查是否满足要求所用的方法可能不同。 对于仅依赖于relisting的PLEG，pod worker可以简单地等待，直到 relist 时间戳比pod  worker 上一次同步的结束时间更新。 另一方面，如果pod worker知道期望的事件是什么，那么也可以阻塞直到事件被观察到。  

需要注意的是，`api.PodStatus`只能在缓存更新后由pod worker生成。 这意味着Kubelet的感知响应能力（查询API Server）将受到缓存多久可以填充的影响。 对于纯 relisting （pure-relisting）的PLEG，relist 周期可能成为瓶颈。 另一方面，观察上游事件流（并知道预期的事件）的PLEG不受这些周期的限制，应该提高Kubelet的感知响应能力。

## v1.2 版本的 TODOs
* 重新定义container runtime 类型：引入 `PodStatus`。重构 dockertools 和 rkt 使用新的类型；
* 增加缓存并指示PLEG填充它；
* 重构 Kubelet 使用 cache

## Pod Cache
Cache 存储pod的PodStatus，表示container runtime中“所有”可见的pods/containers。所有的缓存条目(cache entries)至少与全局时间戳记（由UpdateTime()设置）一样新或更新，而单个条目可能比全局时间戳稍微新。 如果一个pod没有runtime已知的状态，Cache将返回一个填充ID的空的PodStatus对象。  

### 从 Pod  Cache 获取 PodStatus 的方法
Cache提供两种方法取回PodStatus：  
(1) 使用非阻塞的Get()方法  
(2) 使用阻塞的GetNewerThan()方法，这种方法调用时会阻塞直到对应的PodStatus的状态比指定时间更新的时候才会返回该状态（pod worker 在更新Pod的时候就是使用这种阻塞的GetNewerThan()方法）  
负责填充cache的组件 PLEG调用Delete()来显式释放cache entry。  
   
### Pod Cache 的主要构成   
   Cache的主要构成：  
   
* (1)读写互斥锁RWMutex保护数据。  
	RWMutex锁可以被任意多的reader或者单个writer持有。RWMutexes可以作为其他结构的一部分创建; RWMutex的零值是未锁定的互斥量。首次使用后，不得复制RWMutex。如果一个goroutine持有一个RWMutex进行读取，那么在第一个读锁定被释放之前，不能指望这个goroutine或者其他goroutine也可以获取读锁。禁止递归读锁。 这是为了确保锁最终变得可用; 阻塞的锁调用会排斥新reader获取锁定。  

* (2)Cache使用map的方式存储Pod的状态信息。  
* (3)用全局timestamp表示缓存数据的fresh程度。  

所有缓存内容至少比此时间戳要更新。注意，初始化后的时间戳为零，只有在准备好服务缓存状态时，时间戳才会变为非零。  
