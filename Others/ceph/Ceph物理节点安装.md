# Ceph集群安装
## 1. 安装要求
对于多节点的情况，Ceph有如下要求：  
(1) 修改各自的hostname，并能够通过hostname来互相无密码访问（通过ssh-keygen命令）；  
(2) 各节点间需要时钟同步，Ceph 默认时间偏差为0.05s  
(3) 每个 OSD 节点上至少有一个磁盘或者分区存储数据，分区建议格式化成 XFS


## 2. 节点规划
安装Ceph集群，至少需要2个节点（OSD至少需要两个才能做数据备份，Monitor可以与OSD共节点），本次安装环境如下：  

    (1) 10.35.48.172  ceph01    角色：OSD/Monitor/admin  
    (2) 10.35.48.177  ceph02    角色：OSD

## 2. 安装步骤
### 2.1 设置时钟同步
(1) 在节点安装 ntp  （apt-get install ntp）  
(2) 在作为时间服务器的节点配置，修改 /etc/ntp.conf，用如下内容替换：  

    driftfile /var/lib/ntp/ntp.drift

    statistics loopstats peerstats clockstats
    filegen loopstats file loopstats type day enable
    filegen peerstats file peerstats type day enable
    filegen clockstats file clockstats type day enable

    `#`如下设置 10.35.48.x 网段的服务器可以与本机进行时钟同步
    restrict default kod nomodify notrap nopeer noquery
    restrict 10.35.48.0 mask 255.255.255.0 nomodify notrap

    restrict 127.0.0.1
    restrict ::1

    `#`如下设置时钟同步选择的上游时间服务器为本机
    server 127.127.1.0
    fudge 127.127.1.0 stratum 8

## 2.2 设置主机名以及主机之间无密码通信
(1) 修主机名  
	修改各个节点的 /etc/hostname, 如在 ceph01上，修改 /etc/hostname 内容为：  

    ceph01

(2) 设置主机名和 IP 映射  
	修改各个节点的 /etc/hosts，加入所有主机名和IP的映射，如：  

    10.35.48.172  ceph01  
    10.35.48.177  ceph02

(3) 在主节点生成秘钥并分发到其他节点  
    
    A. 主节点执行： ssh-keygen -t rsa # 一直按确定键即可  
    B. 主节点执行： cat /root/.ssh/id_rsa.pub>> /root/.ssh/authorized_keys  
    C. scp 发送整个 /root/.ssh 文件夹到其他节点的 /root 目录下

## 2.3 ceph-deploy 安装 Ceph
(1) 设置镜像源，方便安装ceph部署及ceph相关组件  

    export CEPH_DEPLOY_REPO_URL=http://mirrors.163.com/ceph/debian-jewel/db  
    export CEPH_DEPLOY_GPG_URL=http://mirrors.163.com/ceph/keys/release.asc 

将上面两句写入各个节点的 /etc/profile 和 /etc/environment  中，并使用  

    source /etc/profile  

使设置生效

(2) 在ceph01上安装ceph-deploy  
    
    apt-get install ceph-deploy

(3) 在ceph01上创建集群目录  
    
    mkdir /home/cephcluster  
    cd /home/cephcluster

(4) 创建集群，会在当前目录下看到ceph.conf ceph.log ceph.mon.keyring三个文件  
在ceph01上执行：  
  
      ceph-deploy new ceph01  

执行以上命令后，ceph01相当于监控节点。如果要把两台都作为监控节点则(实际 ceph 的monitor 数量需要为基数)：  

		ceph-deploy new ceph01 ceph02 ceph03

(5) vim ceph.conf并将以下配置追加到后面(后面的数值根据 OSD 节点数量确定)  
    
    osd pool default size = 2

(6) 分别在ceph01和ceph02上安装ceph  
在ceph01上执行以下命令:  

    ceph-deploy install ceph01 ceph02  

执行以上命令，相当于在两个节点上都运行了：apt-get install -y ceph ceph-common ceph-mds ，如果上面的命令失败，也可以用apt-get去每台主机上安装ceph

(7) 初始化集群监控  
在ceph01上执行：  

    ceph-deploy mon create-initial

(8) 收集秘钥，目录下会多出ceph.bootstrap-mds.keyring  ceph.client.admin.keyring  ceph.client.admin.keyring这几个文件  

    ceph-deploy gatherkeys ceph01

(9) 准备硬盘并准备OSD  
假设磁盘为 /dev/sdb 分别在 ceph01 和 ceph02 上执行：  

    mkfs.xfs /dev/sdb

准备 OSD：在ceph01上执行  

    ceph-deploy osd prepare  ceph01:/dev/sdb ceph02:/dev/sdb  

上述命令执行成功后，实际在 /dev/sdb 上创建了一个XFS格式的分区 /dev/sdb1  

激活 OSD：在ceph01上执行：  

    ceph-deploy osd activate  ceph01:/dev/sdb1 ceph02:/dev/sdb1  

上面两条命令执行后:  

    ceph01 的 /dev/sdb1 会 mount 到 ceph01 节点的 /var/lib/ceph/osd/ceph-0  
    ceph02 的 /dev/sdb1 会 mount 到 ceph02 节点的 /var/lib/ceph/osd/ceph-1  

保持系统启动启动就会挂载上述两个磁盘，/etc/rc.local 里加入挂载磁盘命令:  
ceph01 节点：  

    mount /dev/sdb1 /var/lib/ceph/osd/ceph-0  

ceph02 节点：  

    mount /dev/sdb1 /var/lib/ceph/osd/ceph-1

(10) 将配置文件和管理密钥复制到管理节点和Ceph节点，下次再使用ceph 命令行就无需指定集群监视器地址，执行命令时也无需每次都指定ceph.client.admin.keyring  
在ceph01节点上执行：  

    ceph-deploy --overwrite-conf admin ceph01 ceph02  

执行以上命令之后,ceph02这台机器的/etc/ceph目录下也会多出ceph.client.admin.keyring这个文件。

(11) ceph -s  或者 ceph -v 验证 Ceph 集群安装情况正常  

(12) 重启集群  

    service ceph restart -a  

如果上面的命令不起作用则对各个节点服务进行重启  
  
    A. 重启mon节点，mon节点在ceph01上  
      /etc/init.d/ceph restart mon.ceph01  
      或    
      systemctl start ceph-mon@ceph01  

    B、重启osd0节点，osd0在ceph01上  
      /etc/init.d/ceph start osd.0  
      或  
      systemctl start ceph-osd@0  

    C、重启osd1节点，osd1在ceph02上  
      ssh ceph02  
      /etc/init.d/ceph start osd.1  
      或  
      systemctl start ceph-osd@1

## 2.4 CephFS 创建及挂载
(1) 添加 MDS: 在ceph01上建一个元数据服务器MDS  
大多数情况下都是使用ceph的块设备，一般不用建立mds，只有用到ceph的文件存储 CephFS的时候才用到 MDS  
首先执行：  

    mkdir -p /var/lib/ceph/mds/ceph-ceph01  
    ceph-deploy mds create ceph01  

检查创建的 mds 正常运行：  

     netstat -tnlp | grep mds  

或者用   

     ceph -s  

查看确定有 mdsmap 相关的信息  

(2) 创建两个存储池，分别存储数据和元数据  

    ceph osd pool create fs_data 32  
    ceph osd pool create fs_metadata 32  

查看创建的存储池：  

    rados lspools

(3) 创建CephFS  

    ceph fs new cephfs fs_metadata fs_data  

查看创建的CephFS  

    ceph fs ls

(4) 查看MDS状态  

    ceph mds stat  

正常状态类似如下：  

    e5: 1/1/1 up {0=ceph01=up:active}

(5) 挂载 CephFS  

    A. 加载rbd、ceph 内核模块  
      modprobe rbd ceph

    B. 获取admin key
      cat ceph.client.admin.keyring  
      
      输出类似如下：
      
      [client.admin]  
      key = AQCY+0BZcoJwFRAA405ddOWiaqz2dWNVrviqOg==  

    C. 创建挂载点，尝试本地挂载（每个节点上都可以创建，可以同时挂载到每个节点上，实现各节点并行访问 CephFS）  
      mkdir /home/wong/cephs  
      mount -t ceph 10.35.48.172:6789:/ /home/wong/cephfs -o name=admin,secret=AQCY+0BZcoJwFRAA405ddOWiaqz2dWNVrviqOg==  

      查看挂载情况：  
      #df -hT  
      10.35.48.172:6789:/ ceph      950G   72M  949G    1% /home/wong/cephfs  

    D. 如果有多个mon节点，可以挂载多个节点，保证了CephFS的高可用，当有一个节点down的时候不影响数据读写  
      mount -t ceph 10.35.48.172,10.35.48.177:6789:/ /home/wong/cephfs -o name=admin,secret=AQCY+0BZcoJwFRAA405ddOWiaqz2dWNVrviqOg==

      查看挂载情况：  
      #df -hT  
      10.35.48.172,10.35.48.177:6789:/ ceph      884G   68M  884G    1% /home/wong/cephfs


# 3. Ceph 卸载
## 3.1 卸载相关数据
        ceph-deploy purgedata ceph01 ceph02

## 3.2 卸载ceph相关软件包（如果需要重装ceph所有组件，才需要执行此步骤）
        ceph-deploy purge ceph01 ceph02

## 3.3 删除本地认证信息 (重建 Ceph 集群需要执行)
        ceph-deploy forgetkeys

## 3.4  清理相关文件脚本(一键清除 Ceph)
    service ceph -a stop
      dirs=(/var/lib/ceph/bootstrap-mds/*  /var/lib/ceph/bootstrap-osd/* /var/lib/ceph/mds/* \
      /var/lib/ceph/mon/* /var/lib/ceph/tmp/* /var/lib/ceph/osd/* /var/run/ceph/*   /var/log/ceph/*  /etc/ceph/*)

      for d in ${dirs[@]};
      do
          rm -rf $d
          echo $d  done
      done
      umount /var/lib/ceph/osd/*

      for disk in b1
      do
        # 重新格式化 /dev/sdb1
        /root/mkfs.xfs -d agcount=1 -f -i size=2048 /dev/sd$disk
      done

## 3.5  安装 Ceph 脚本(一键安装 Ceph)
          cd  /home/cephcluster
          ceph-deploy new `hostname`
          ceph-deploy --overwrite-conf  mon create-initial
          ceph-deploy disk zap `hostname`:/dev/sdb
          ceph-deploy osd  prepare  `hostname`:/dev/sdb
          ceph-deploy osd activate  `hostname`:/dev/sdb1

# 4. Ceph 块设备使用方法
(1) 作为ceph client 的 节点（如节点名为 cephclient）需要与 ceph 集群节点能够 ssh 无密码访问（方便部署 ceph）  

(2) 在 ceph 集群的 admin 节点上执行如下命令在 ceph 的 client 节点安装 ceph  

        ceph-deploy install cephclient  

(3) 在admin节点上，用ceph-deploy复制Ceph配置文件和ceph.client.admin.keyring到 ceph client 节点  

        ceph-deploy admin cephclient  

(4) 在 ceph client 节点上，创建一个 100GB 的块设备镜像，镜像名称为 foo   

        rbd create foo --size 102400  

 查看镜像  

        rbd ls -l  

注意：默认是在 rbd 这个 pool 下面创建foo镜像 rbd/foo，也可以自己先创建一个 pool：  

        ceph osd pool create <creating_pool_name> <pg_num>  

参数：  

        creating_pool_name ： 要创建的pool的名字  
        pg_num : Placement Group的个数  
        # ceph osd pool create testpool 512  

(5) 在 ceph client 节点上，要映射块设备镜像到内核模块，首先要加载Ceph的RBD模块,让内核从新识别设备  

        modprobe rbd  
        partprobe  

(6) 在 ceph client 节点上，映射之前创建的镜像 foo 到一个块设备  

        rbd map foo --pool rbd --name client.admin  

(7) 显示映射块设备  

        rbd showmapped  

显示如下:  

        id pool image snap device  
        0  rbd  foo   -    /dev/rbd0  

(8) 用这个块设备在一个ceph client节点上创建一个文件系统  

        mkfs.ext4 -m0 /dev/rbd0  

(9) 在这个 ceph client 节点挂载这个文件系统到ceph-client节点上  

        mount /dev/rbd0 /rbdfs0  

(10) 取消映射块设备  

        umount /dev/rbd0  
        rbd unmap /dev/rbd0  

(11) 删除镜像文件  

        rbd rm foo  

