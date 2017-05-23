# Kubelet Eviction Policy  （Kubelet逐出策略）
## 逐出背景
节点需要一个机制在可用计算资源低的时候保持节点稳定性。对于处理不可压缩的计算资源（如memory或disk）尤其重要。memory或者disk资源任一个耗尽，节点则不可用。   
  
 
Kubelet支持通过让系统OOM killer看到更高的OOM score来影响响应系统OOM的行为，调整(调高)相对于其他container的请求消耗了最大数量的内存的container的OOM score。系统OOM事件是计算密集型的，可能暂停节点(stall node)直到 OOM killing程序完成。此外，由于由OOM score高而被杀死的容器在节点上重新启动或新的pod被安排到节点上，所以系统容易返回到不稳定状态。  
  
  
因此，更希望系统中kubelet可以主动监视并防止计算资源的完全消耗，并且在可能发生的情况下，主动地杀掉一个或多个pod，因此当/如果该Pod的后备控制器创建一个新的pod时，该工作负载可以移动并调度到其他节点上。    
  

目前支持基于内存和磁盘的 Eviction Policy。  

## Eviction Signals （逐出信号）  
kubelet通过如下信号触发Eviction决策：  

| Eviction Signal  |   描述                                                              |
|------------------|---------------------------------------------------------------------------------|
| memory.available | memory.available := node.status.capacity[memory] - node.stats.memory.workingSet |
| nodefs.available   | nodefs.available := node.stats.fs.available |
| nodefs.inodesFree | nodefs.inodesFree := node.stats.fs.inodesFree |
| imagefs.available | imagefs.available := node.stats.runtime.imagefs.available |
| imagefs.inodesFree | imagefs.inodesFree := node.stats.runtime.imagefs.inodesFree |  

上述每个Signal支持一个基于数字或百分比的值。基于百分比的值是相对于总容量计算得到的。    
  

Kubelet 仅支持两种文件系统分区：  
(1) nodefs 文件系统：kubelet用于volumes、守护进程日志，等等；  
(2) imagefs 文件系统：容器运行时用于存储images和容器的可写层；    
  

imagefs是可选的。 kubelet使用cAdvisor自动发现这些文件系统。 kubelet不关心任何其他文件系统，kubelet当前不支持任何其他类型的配置。 例如，不可以将卷和日志存储在专用的imagefs中。    

## Eviction Thresholds （逐出阈值）
Kubelet支持指定eviction thresholds。eviction threshold 是如下的格式：  

  `<eviction-signal><operator><quantity | int%>`
  
* `eviction-signal`上述表中定义的一种.
* `operator`即`<`
* `quantity` 必须匹配Kubernetes使用的数量表示
* 如果以`%`结尾，eviction threshold可以以百分比值表示.

如果达到阈值标准，kubelet将主动尝试回收与eviction signal相关联的计算资源。  
  
  
kubelet支持软、硬eviction thresholds。例如，如果一个节点有 10Gi 内存，期望在内存低于 1Gi 的时候触发eviction，则eviction signal可以以如下两种方式之一来指定（不能同时使用）：

* `memory.available<10%`
* `memory.available<1Gi`

### Soft Eviction Thresholds （软逐出阈值）
软eviction threshold将逐出阈值与所需的管理员指定的宽限期配对。 kubelet不采取任何措施来回收与eviction signal相关的资源，直到超过宽限期。 如果没有提供宽限期，启动时kubelet会出错。  
  
  
另外，如果已经满足软Eviction Threshold，则操作者可以指定从节点驱逐pod时使用的最大允许的pod终止宽限期。 如果指定，则kubelet将使用pod.Spec.TerminationGracePeriodSeconds和允许的最大宽限期中的较小值作为pod终止宽限期。 如果没有指定，kubelet会立即杀死pod而无宽限期。  
  
 
### Hard Eviction Thresholds（硬逐出阈值）
硬Eviction Threshold没有宽限期，如果满足阈值，Kubelet立即回收相关的资源，立即杀掉相应的Pod。    
  

## Eviction Monitoring Interval (逐出监控间隔)
kubelet评估Eviction Thresholds的时间间隔最初与cAdvisor的内部管理间隔相同。在kubernets 1.2中，默认为10s。  
缩短监控间隔是kubernetes的目标，需要修改cAdvisor支持可更改监控时间间隔。 
  
  
## Node conditions
kubelet支持每个Eviction Signal对应一个node condition。  
  
  
如果满足硬Eviction Thresholds，或者满足不依赖于其相关宽限期的软Eviction Thresholds，则kubelet将报告一个Condition反映节点处于压力状态。    
  
  
 当前（1.5.3版本）有效的node conditions如下：  
 (1) NodeReady (即 Ready)，表示 kubelet 是健康的并且可以接收处理Pods;  
 (2) NodeOutOfDisk(即OutOfDisk)，表示kubelet因为节点上空闲磁盘空间不足而不再接收新的Pods;  
 (3) NodeMemoryPressure(即MemoryPressure)，表示kubelet因为可用内存不足而处于压力下；  
 (4) NodeDiskPressure(即DiskPressure)，表示kubelet因为可用磁盘不足而处于压力下；  
 (5) NodeNetworkUnavailable(即NetworkUnavailable)，表示节点的网络没有正确配置。  
 将来将增加更多的conditions  
   
  
有三种有效的condition status：  
(1) ConditionTrue(即 True)，表示资源(resource)在条件(condition)中；  
(2) ConditionFalse(即false)，表示资源(resource)不在条件(condition)中；  
(3) ConditionUnknown(即Unknown)，表示不能确定资源(resource)是否在条件(condition)中；  
将来可能加入其他的中间条件，如ConditionDegraded。  
  
  
对应于指定的 Eviction Signal，定义了如下 node conditions：  

| Node Condition | Eviction Signal  | 描述                                                     |
|----------------|------------------|------------------------------------------------------------------|
| MemoryPressure | memory.available | 节点上的可用内存满足Eviction Threshold |
| DiskPressure | nodefs.available, nodefs.inodesFree, imagefs.available,  imagefs.inodesFree | 节点的root文件系统或image文件系统的可用磁盘空间和inodes满足Eviction Threshold |

kubelet 以 --node-status-update-frequency 指定的频率报告节点状态，默认是10s。  
  
  
### Oscillation of node conditions (节点条件震荡)
如果一个节点在软Eviction Threshold上下振荡，但不超过其关联的宽限期，则会导致相应的node condition在真假之间持续振荡，从而导致调度决策不佳。  
  
  
为了防止这种振荡，定义了 --eviction-pressure-transition-period 标志来控制在过渡到压力条件之前kubelet必须等待多长时间。  
  
  
对于指定的压力condition，kubelet确保在将node condition切换回为false之前指定的期间内没有观察到针对指定压力条件的Eviction Threshold。  
  
  
## Eviction scenarios (逐出场景)  
### Memory
假设 kubelet 启动参数带如下flag：  

```
--eviction-hard="memory.available<100Mi"
--eviction-soft="memory.available<300Mi"
--eviction-soft-grace-period="memory.available=30s"
```

Kubelet 运行 sync 循环查看节点上cAdvisor 通过计算(capacity-workingSet)上报的可用内存。 如果观察到可用内存降至100Mi以下，那么kubelet将立即启动Eviction。 如果观察到可用内存低于300Mi，则会在cache中记录观察到该信号的时间。 如果在下一次sync时，该条件不再满足，则从cache中清除该signal。 如果观察到该信号满足的状态长于指定时间段，则kubelet启动Eviction以尝试回收已满足Eviction Threshold的资源。

### Disk
假设 kubelet 启动参数带如下flag：  

```
--eviction-hard="nodefs.available<1Gi,nodefs.inodesFree<1,imagefs.available<10Gi,imagefs.inodesFree<10"
--eviction-soft="nodefs.available<1.5Gi,nodefs.inodesFree<10,imagefs.available<20Gi,imagefs.inodesFree<100"
--eviction-soft-grace-period="nodefs.available=1m,imagefs.available=2m"
```

Kubelet 运行 sync 循环查看节点上通过cAdvisor 上报的node支持的分区上的可用磁盘。如果节点的主文件系统上的可用磁盘空间被观察到低于1Gi或节点的主文件系统上的可用的inode小于1，那么kubelet将立即启动Eviction。如果观察到节点的image文件系统上的可用磁盘空间降低到10Gi以下，或者节点的主image文件系统上的可用的inode小于10，则kubelet将立即启动Eviction。  
  
  
如果节点的主文件系统上的可用磁盘空间被观察到低于1.5Gi，或者节点的主文件系统上的可用的inode小于10，或者节点的image文件系统上的可用磁盘空间被观察到低于20Gi，或者如果节点的image文件系统上的可用inode小于100，则会在cache中记录观察到该信号的时间。如果在下一次同步时，该标准不再满足，则该信号将从cache中清除。如果该信号满足条件的时间长于指定时间段，则kubelet将启动Eviction以尝试回收已满足Eviction Threshold的资源。  

## Eviction of Pods (逐出 Pods)  
如果已经满足了Eviction Threshold，则kubelet将启动Eviction pod的过程，直到观察到信号已经低于其定义的阈值。  
Eviction顺序如下：  

 * 对于每个监控间隔，如果达到Eviction Threshold  
 * 找出候选 pod
 * 使该 pod fail
 * 阻塞直到pod在节点上终止
 
如果有一个容器没有die（如进程卡在磁盘I/O上）导致pod没有成功终止，kubelet可以选择一个另外的pod来代替。 kubelet调用在运行时界面上开放的KillPod操作。 如果返回错误，kubelet将选择下一个备选的pod。  
  
  
## Eviction Strategy （逐出策略）
kubelet围绕pod QoS 类实现默认逐出策略。  
Kubelet将相对于其调度请求的计算资源最大消耗者的pod作为目标pod，按照以下顺序对QoS等级进行排序：  

 * `BestEffort` 消耗短缺资源最多的pod首先failed；
 * `Burstable` 相对于pod对短缺资源的请求，消耗最大数量的短缺资源的pod首先被杀死。 如果没有pod超出其请求的资源，该策略将针对资源的最大消耗者；
 * `Guaranteed` 相对于pod对资源的请求，消耗最大数量的短缺资源的pod首先被杀掉。如果没有pod超出其请求的资源，该策略将针对资源的最大消耗者；
 
  Guaranteed pod 保证永远不会因为另一个pod的资源消耗被逐出。  
  
如果一个系统守护进程（即kubelet，docker，journald等）消耗的资源比通过 system-reserved 或kube-reserved 分配保留的资源多，而节点只有guaranteed pod保留，那么该节点必须选择驱逐 guaranteed pod，以保持节点的稳定性，并限制其他guaranteed pods 不可预期的资源消耗的影响。

## Disk based evictions (基于磁盘的逐出)
### With Imagefs （有 imagefs）
如果nodefs 文件系统达到Eviction Thresholds，Kubelet将按照如下顺序释放磁盘空间：  

 1.  删除logs
 2.  必要的话逐出Pods
 
 如果 imagefs 文件系统达到Eviction Thresholds，Kubelet将按照如下顺序释放磁盘空间：  
 
  1. 删除不使用的 images
  2. 必要的话逐出Pods

### Without Imagefs （无 imagefs）
如果nodefs 文件系统达到Eviction Thresholds，Kubelet将按照如下顺序释放磁盘空间：  

 1.  删除logs
 2.  删除不使用的 images
 3.  必要的话逐出Pods

### Delete logs of dead pods/containers （删除死亡的pods/containers 的logs）
日志与容器的寿命相关。kubelet保持死亡的容器，以提供访问日志。如果在容器之外存储死亡容器的日志，那么kubelet可以删除这些日志以释放磁盘空间。 一旦容器和日志的生命周期分离，kubelet可以支持更多用户友好的日志逐出策略。 kubelet可以先删除最旧容器的日志。 由于来自容器的第一个和最后一个容器incarnation对于大多数应用程序来说是最重要的，所以kubelet可以尝试保留这些日志，并积极地从其他容器incarnations中删除日志。    
  

一旦logs 与容器的生命周期分离，kubelet就可以删除死亡的容器以释放磁盘空间。  

###  Delete unused images（删除不使用的images）
kubelet基于阈值执行image 垃圾回收。kubelet使用高、低水印（high/low watermark）。 当磁盘使用量超过高水印时，kubelet会删除image，直到达到低水印。 当删除image时，kubelet采用LRU策略。  
  

当前的策略将会被更简单的策略代替。images将基于Eviction Threshold。如果kubelet可以删除logs并保持磁盘可用空间在eviction threshold 之上，kubelet就不会删除任何images。如果Kubelet决定删除不使用的images，则删除所有不使用的images。  

### Evict pods (逐出pods)
当前不能为pods/containers 指定磁盘限制。 必要时，kubelet可以一次逐出一个pod。 kubelet将遵循上述逐出策略作出逐出决定。 kubelet将逐出达到Eviction Threshold且释放最大磁盘空间的pod。 在每个QoS bucket中，kubelet将根据其磁盘使用情况对pod进行排序。 kubelet在每个bucket中按如下步骤对pod进行排序：  
#### Without Imagefs (无 Imagefs)  
如果 nodefs 触发Eviction，kubelet则基于pod的总的磁盘使用量排序 pods  

 * 本地卷+pod的所有容器的可写层&logs
 
#### With Imagefs (有 Imagefs)  
如果 nodefs 触发Eviction，kubelet则基于nodefs的磁盘使用量排序 pods  

 * 本地卷+pod的所有容器的logs
 
如果 imagefs 触发Eviction，kubelet则基于pod的所有容器的可写层的磁盘使用量排序 pods  

## MInimum eviction reclaim （最小逐出回收）
在特定的场景，逐出pods可能导致回收少量的资源。 这可能导致kubelet重复演替达到Eviction Thresholds的情况。 除此之外，逐出资源（如磁盘）也很耗时的。  
  

为了缓解这些问题，kubelet有每个资源的最小回收（minimum-reclaim）量。 每当kubelet观察到资源压力时，kubelet将尝试至少回收资源要达到该资源的最小回收量。  
  
  
以下是可以为每个可驱逐资源配置最小回收的标志：  

   ` --eviction-minimum-reclaim="memory.available=0Mi,nodefs.available=500Mi,imagefs.available=2Gi"`

对于所有资源，默认的 eviction-minimum-reclaim 是0.  

## Deprecation of existing features （弃用现有特性）
kubelet已经支持按需释放磁盘空间，以保持节点的稳定。 作为提案的一部分，磁盘空间回收相关的一些现有功能/标志在未来可能丢弃。  

| 现有 Flag | 新 Flag | 理由 |
| ------------- | -------- | --------- |
| `--image-gc-high-threshold` | `--eviction-hard` or `eviction-soft` | 现有eviction signals 可以捕捉  image garbage collection |
| `--image-gc-low-threshold` | `--eviction-minimum-reclaim` | 逐出回收达到相同的行为 |
| `--maximum-dead-containers` | | 一旦旧logs存储在容器的上下文之外则丢弃 |
| `--maximum-dead-containers-per-container` | | 一旦旧logs存储在容器的上下文之外则丢弃 |
| `--minimum-container-ttl-duration` | | 一旦旧logs存储在容器的上下文之外则丢弃 |
| `--low-diskspace-threshold-mb` | `--eviction-hard` or `eviction-soft` | 提案中处理这种情况的效果更好 |
| `--outofdisk-transition-frequency` | `--eviction-pressure-transition-period` | 使flag通用以适合所有计算资源 |

## Kubelet  Admission Control （Kubelet准入控制）
### Feasibility checks during kubelet admission （kubelet准入的可行性检查）
#### Memory
如果已经超过了所配置的宽限期内的任何内存逐出阈值，kubelet将拒绝BestEffort pod。  
假设kubelet启动参数中带如下参数：  

    --eviction-soft="memory.available<256Mi"
    --eviction-soft-grace-period="memory.available=30s"

如果kubelet发现节点上可用内存小于 256Mi，但由于宽限期标准尚未得到满足，kubelet尚未启动eviction，因此kubelet将立即fail任何进入的best effort pods。  
  

这个决定的原因是进入的pod可能进一步使特定的计算资源更为短缺，并且kubelet在接受新工作负载之前应该恢复到稳定状态。

#### Disk
如果满足任意磁盘逐出阈值，kubelet将拒绝所有pods。  
假设使用以下方法启动kubelet：  

  --eviction-soft="nodefs.available<1500Mi"
  --eviction-soft-grace-period="nodefs.available=30s"
  
如果kubelet发现节点上可用磁盘小于 1500Mi，但由于宽限期标准尚未得到满足，kubelet尚未启动eviction，kubelet将立即fail任何进入的pods。  
  

fail 掉所有进入的 pods而不是尽力尝试的理由是因为磁盘目前是所有QoS类中的一种best effort 资源。  
  
  
即使有专用的 image 文件系统，Kubelet也将应用相同的策略。

## Scheduler （调度）
当计算资源处于压力下时，节点将报告一个条件（confdition）。 调度程序应当将该条件视为信号，以阻止在节点上放置额外的best effort pods。  
  

在这种情况下，如果MemoryPressure条件为true，则应阻止调度程序在节点上放置新的best effort pods，因为它们在准入的时候将被kubelet拒绝。    
  

另一方面，如果DiskPressure条件为true，则阻止调度程序在节点上放置任何新的pod，因为它们在准入的时候将被kubelet拒绝。  

## Enforcing Node Allocatable 
为了执行Node 可分配，Kubelet主要使用cgroups。 但是，storage 不能强制使用cgroup。  
  

一旦Kubelet支持storage成为一个可分配的资源，只要pods的总存储使用量超过节点可分配量，Kubelet将执行逐出。  
如果pod不能容忍逐出，则确保请求已设置，并且不会超出请求。

## 最佳实践
### DaemonSet
kubelet不希望逐出从DaemonSet导出的pod，因为这样的pod将立即重新创建并重新调度到同一个节点。  
  

当前，kubelet无法区分从DaemonSet创建的pod和任何从其他对象创建的pod。 如果/当kubelet可以识别 pod 来源时，kubelet可以主动地从提供给逐出策略的候选pods集合中过滤这些来自 DaemonSet 的 pods  
  

一般来说，强烈建议DaemonSet不要创建BestEffort pod，以避免被识别为候选pod而被逐出。 相反，理想情况下DaemonSet应该仅包括 guaranteed pods。  

## Known issues （已知的问题）
### kubelet 可能逐出超出需要的pods
由于统计收集时间差距，pod 逐出可能会逐出比所需的更多的pods。这可以通过增加按需提供获取root 容器的统计信息的功能（https://github.com/google/cadvisor/issues/1247）来缓解。  

### 在inode耗尽的情况下kubelet如何排序pods
当前，不可能知道特定容器消耗了多少个inodes。 如果kubelet观察到inode耗尽，它将通过按照OoS对pods排序逐出。cadvisor中已开放一个issue （https://github.com/google/cadvisor/issues/1422）来跟踪每个容器inode消耗，允许通过inode消耗对pod进行排名。 例如，可以让用户识别一个创建大量0字节文件的容器，并将该pod的逐出放在其他pods之前。
