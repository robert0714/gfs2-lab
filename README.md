# Creating DRDB
The first step in setting up DRBD is to prepare the partitions to be used as DRBD devices. We are assuming
that we have an additional disk (sdb) on both the nodes (pcmk-1 and nodpcmk-2) that are of same sizes. We will create two partition tables (sdb1 and sdb2) of 20 GB each for the DRBD devices (drbd1 and drbd2).
```bash
$ vagrant ssh pcmk-1
[vagrant@pcmk-1 ~]$ ls /dev/sdb*
/dev/sdb
[vagrant@pcmk-1 ~]$ ls /dev/sd*
/dev/sda  /dev/sda1  /dev/sda2  /dev/sdb
[vagrant@pcmk-1 ~]$ sudo lsblk
NAME            MAJ:MIN RM SIZE RO TYPE MOUNTPOINT
sda               8:0    0  64G  0 disk 
├─sda1            8:1    0   1G  0 part /boot
└─sda2            8:2    0  63G  0 part 
  ├─centos-root 253:0    0  41G  0 lvm  /
  ├─centos-swap 253:1    0   2G  0 lvm  [SWAP]
  └─centos-home 253:2    0  20G  0 lvm  /home
sdb               8:16   0  20G  0 disk 
[vagrant@pcmk-1 ~]$ sudo fdisk /dev/sdb
Welcome to fdisk (util-linux 2.23.2).

Changes will remain in memory only, until you decide to write them.
Be careful before using the write command.

Device does not contain a recognized partition table
Building a new DOS disklabel with disk identifier 0xb33e345b.

Command (m for help): n
Partition type:
   p   primary (0 primary, 0 extended, 4 free)
   e   extended
Select (default p): p
Partition number (1-4, default 1): 
First sector (63-41943039, default 63): 
Using default value 63
Last sector, +sectors or +size{K,M,G} (63-41943039, default 41943039): 
Using default value 41943039
Partition 1 of type Linux and of size 20 GiB is set

Command (m for help): w
The partition table has been altered!

Calling ioctl() to re-read partition table.
Syncing disks.
[vagrant@pcmk-1 ~]$ ls /dev/sd*
/dev/sda  /dev/sda1  /dev/sda2  /dev/sdb  /dev/sdb1
[vagrant@pcmk-1 ~]$ sudo lsblk
NAME            MAJ:MIN RM SIZE RO TYPE MOUNTPOINT
sda               8:0    0  64G  0 disk 
├─sda1            8:1    0   1G  0 part /boot
└─sda2            8:2    0  63G  0 part 
  ├─centos-root 253:0    0  41G  0 lvm  /
  ├─centos-swap 253:1    0   2G  0 lvm  [SWAP]
  └─centos-home 253:2    0  20G  0 lvm  /home
sdb               8:16   0  20G  0 disk 
└─sdb1            8:17   0  20G  0 part 
[vagrant@pcmk-1 ~]$ 

```

執行pvcreate/vgcreate

```bash
[root@pcmk-1 drbd.d]# pvcreate /dev/sdb1
[root@pcmk-1 drbd.d]# vgcreate centos_pcmk-1 /dev/sdb1
  Volume group "centos_pcmk-1" successfully created
[root@pcmk-1 drbd.d]# vgdisplay | grep -e Name -e Free
  VG Name               centos_pcmk-1
  Free  PE / Size       5119 / <20.00 GiB
  VG Name               centos
  Free  PE / Size       1 / 4.00 MiB
[root@pcmk-1 drbd.d]# lvcreate --name drbd-demo --size 512M centos_pcmk-1
  Logical volume "drbd-demo" created.
[root@pcmk-1 drbd.d]# lvs
  LV        VG            Attr       LSize   Pool Origin Data%  Meta%  Move Log Cpy%Sync Convert
  home      centos        -wi-ao---- <20.01g                                                    
  root      centos        -wi-ao----  40.98g                                                    
  swap      centos        -wi-ao----   2.00g                                                    
  drbd-demo centos-pcmk-1 -wi-a----- 512.00m                                                    
[root@pcmk-1 drbd.d]# ssh pcmk-2
Last login: Wed Jul 24 07:15:44 2019 from 19.168.122.101
[root@pcmk-2 ~]# lsblk
NAME            MAJ:MIN RM SIZE RO TYPE MOUNTPOINT
sda               8:0    0  64G  0 disk 
├─sda1            8:1    0   1G  0 part /boot
└─sda2            8:2    0  63G  0 part 
  ├─centos-root 253:0    0  41G  0 lvm  /
  ├─centos-swap 253:1    0   2G  0 lvm  [SWAP]
  └─centos-home 253:2    0  20G  0 lvm  /home
sdb               8:16   0  20G  0 disk 
└─sdb1            8:17   0  20G  0 part 
[root@pcmk-2 ~]# vgdisplay | grep -e Name -e Free
  VG Name               centos
  Free  PE / Size       1 / 4.00 MiB
[root@pcmk-2 ~]# pvcreate /dev/sdb1
  Physical volume "/dev/sdb1" successfully created.
[root@pcmk-2 ~]# vgcreate centos_pcmk-2 /dev/sdb1
  Volume group "centos_pcmk-2" successfully created
[root@pcmk-2 ~]# vgdisplay | grep -e Name -e Free
  VG Name               centos_pcmk-2
  Free  PE / Size       5119 / <20.00 GiB
  VG Name               centos
  Free  PE / Size       1 / 4.00 MiB
[root@pcmk-2 ~]# lvcreate --name drbd-demo --size 512M centos_pcmk-2
```
## Configure DRBD
There is no series of commands for building a DRBD configuration, so simply run this on both nodes to use this sample configuration:

```bash 
[root@pcmk-1 drbd.d]# cat <<END >/etc/drbd.d/wwwdata.res
resource wwwdata {
 protocol C;
 meta-disk internal;
 device /dev/drbd1;
 syncer {
  verify-alg sha1;
 }
 net {
  allow-two-primaries;
 }
 on pcmk-1 {
  disk   /dev/centos_pcmk-1/drbd-demo;
  address  19.168.122.101:7789;
 }
 on pcmk-2 {
  disk   /dev/centos_pcmk-2/drbd-demo;
  address  19.168.122.102:7789;
 }
}
END
```

##  Initialize DRBD
With the configuration in place, we can now get DRBD running.
These commands create the local metadata for the DRBD resource, ensure the DRBD kernel module is loaded, and bring up the DRBD resource. Run them on one node:

```bash
[root@pcmk-1 drbd.d]# drbdadm create-md wwwdata
initializing activity log
initializing bitmap (16 KB) to all zero
Writing meta data...
New drbd meta data block successfully created.
[root@pcmk-1 drbd.d]# modprobe drbd
[root@pcmk-1 drbd.d]# drbdadm up wwwdata

  --==  Thank you for participating in the global usage survey  ==--
The server's response is:
you are the 17550th user to install this version
[root@pcmk-1 drbd.d]# 
```

We can confirm DRBD’s status on this node:

```bash
[root@pcmk-1 drbd.d]#  cat /proc/drbd
version: 8.4.11-1 (api:1/proto:86-101)
GIT-hash: 66145a308421e9c124ec391a7848ac20203bb03c build by mockbuild@, 2018-11-03 01:26:55

 1: cs:WFConnection ro:Secondary/Unknown ds:Inconsistent/DUnknown C r----s
    ns:0 nr:0 dw:0 dr:0 al:8 bm:0 lo:0 pe:0 ua:0 ap:0 ep:1 wo:f oos:524236

```
Because we have not yet initialized the data, this node’s data is marked as Inconsistent. Because we have not yet initialized the second node, the local state is WFConnection (waiting for connection), and the partner node’s status is marked as Unknown.
Now, repeat the above commands on the second node, starting with creating wwwdata.res. After giving it time to connect, when we check the status, it shows:

```bash
[root@pcmk-2 ~]# cat /proc/drbd
version: 8.4.11-1 (api:1/proto:86-101)
GIT-hash: 66145a308421e9c124ec391a7848ac20203bb03c build by mockbuild@, 2018-11-03 01:26:55

 1: cs:Connected ro:Secondary/Secondary ds:Inconsistent/Inconsistent C r-----
    ns:0 nr:0 dw:0 dr:0 al:8 bm:0 lo:0 pe:0 ua:0 ap:0 ep:1 wo:f oos:524236
[root@pcmk-2 ~]# 
```

You can see the state has changed to Connected, meaning the two DRBD nodes are communicating properly, and both nodes are in Secondary role with Inconsistent data.
To make the data consistent, we need to tell DRBD which node should be considered to have the correct data. In this case, since we are creating a new resource, both have garbage, so we’ll just pick pcmk-1 and run this command on it:

```bash

[root@pcmk-1 drbd.d]# drbdadm primary --force wwwdata
```

If we check the status immediately, we’ll see something like this:

```bash
[root@pcmk-1 drbd.d]#  cat /proc/drbd
version: 8.4.11-1 (api:1/proto:86-101)
GIT-hash: 66145a308421e9c124ec391a7848ac20203bb03c build by mockbuild@, 2018-11-03 01:26:55

 1: cs:Connected ro:Secondary/Secondary ds:Inconsistent/Inconsistent C r-----
    ns:0 nr:0 dw:0 dr:0 al:8 bm:0 lo:0 pe:0 ua:0 ap:0 ep:1 wo:f oos:524236
[root@pcmk-1 drbd.d]# drbdadm primary --force wwwdata
[root@pcmk-1 drbd.d]#  cat /proc/drbd
version: 8.4.11-1 (api:1/proto:86-101)
GIT-hash: 66145a308421e9c124ec391a7848ac20203bb03c build by mockbuild@, 2018-11-03 01:26:55

 1: cs:SyncSource ro:Primary/Secondary ds:UpToDate/Inconsistent C r-----
    ns:434616 nr:0 dw:0 dr:436744 al:8 bm:0 lo:0 pe:0 ua:0 ap:0 ep:1 wo:f oos:89620
        [===============>....] sync'ed: 83.6% (89620/524236)K
        finish: 0:00:04 speed: 18,712 (13,580) K/sec
[root@pcmk-1 drbd.d]# 

```
We can see that this node has the Primary role, the partner node has the Secondary role, this node’s data is now considered UpToDate, the partner node’s data is still Inconsistent, and a progress bar shows how far along the partner node is in synchronizing the data.
After a while, the sync should finish, and you’ll see something like:
```bash
[root@pcmk-1 drbd.d]#  cat /proc/drbd
version: 8.4.11-1 (api:1/proto:86-101)
GIT-hash: 66145a308421e9c124ec391a7848ac20203bb03c build by mockbuild@, 2018-11-03 01:26:55

 1: cs:Connected ro:Primary/Secondary ds:UpToDate/UpToDate C r-----
    ns:524236 nr:0 dw:0 dr:526364 al:8 bm:0 lo:0 pe:0 ua:0 ap:0 ep:1 wo:f oos:0
[root@pcmk-1 drbd.d]#
```
Both sets of data are now UpToDate, and we can proceed to creating and populating a filesystem for our WebSite resource’s documents.

## Populate the DRBD Disk
On the node with the primary role (pcmk-1 in this example), create a filesystem on the DRBD device:

```bash
[root@pcmk-1 drbd.d]# lsblk
NAME                           MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
sda                              8:0    0   64G  0 disk 
├─sda1                           8:1    0    1G  0 part /boot
└─sda2                           8:2    0   63G  0 part 
  ├─centos-root                253:0    0   41G  0 lvm  /
  ├─centos-swap                253:1    0    2G  0 lvm  [SWAP]
  └─centos-home                253:2    0   20G  0 lvm  /home
sdb                              8:16   0   20G  0 disk 
└─sdb1                           8:17   0   20G  0 part 
  └─centos--pcmk--1-drbd--demo 253:3    0  512M  0 lvm  
    └─drbd1                    147:1    0  512M  0 disk 
[root@pcmk-1 drbd.d]# mkfs.xfs /dev/drbd1
meta-data=/dev/drbd1             isize=512    agcount=4, agsize=32765 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=0, sparse=0
data     =                       bsize=4096   blocks=131059, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0 ftype=1
log      =internal log           bsize=4096   blocks=855, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
[root@pcmk-1 drbd.d]# 
```
Mount the newly created filesystem, populate it with our web document, give it the same SELinux policy as the web document root, then unmount it (the cluster will handle mounting and unmounting it later):

```bash
[root@pcmk-1 drbd.d]# cd ~
[root@pcmk-1 ~]#  mount /dev/drbd1 /mnt
[root@pcmk-1 ~]# cat <<-END >/mnt/index.html
>  <html>
>   <body>My Test Site - DRBD</body>
>  </html>
> END
[root@pcmk-1 ~]#

```
### Configure the Cluster for the DRBD device
One handy feature pcs has is the ability to queue up several changes into a file and commit those changes all at once. To do this, start by populating the file with the current raw XML config from the CIB.

```bash
[root@pcmk-1 ~]# pcs cluster cib drbd_cfg
[root@pcmk-1 ~]# 
```
Using pcs’s -f option, make changes to the configuration saved in the drbd_cfg file. These changes will not be seen by the cluster until the drbd_cfg file is pushed into the live cluster’s CIB later.
Here, we create a cluster resource for the DRBD device, and an additional clone resource to allow the resource to run on both nodes at the same time.

```bash
[root@pcmk-1 ~]# pcs cluster cib drbd_cfg
[root@pcmk-1 ~]# pcs -f drbd_cfg resource create WebData ocf:linbit:drbd \
>          drbd_resource=wwwdata op monitor interval=60s
[root@pcmk-1 ~]# pcs -f drbd_cfg resource master WebDataClone WebData \
>          master-max=1 master-node-max=1 clone-max=2 clone-node-max=1 \
>          notify=true
[root@pcmk-1 ~]# pcs -f drbd_cfg resource show
 Master/Slave Set: WebDataClone [WebData]
     Stopped: [ pcmk-1 pcmk-2 ]
[root@pcmk-1 ~]# 

```
After you are satisfied with all the changes, you can commit them all at once by pushing the drbd_cfg file into the live CIB.

```bash
[root@pcmk-1 ~]# pcs cluster cib-push drbd_cfg --config
CIB updated
[root@pcmk-1 ~]# 
```
Let’s see what the cluster did with the new configuration:

```bash
[root@pcmk-1 ~]# pcs status
Cluster name: mycluster

WARNINGS:
No stonith devices and stonith-enabled is not false

Stack: corosync
Current DC: pcmk-1 (version 1.1.19-8.el7_6.4-c3c624ea3d) - partition with quorum
Last updated: Wed Jul 24 08:41:08 2019
Last change: Wed Jul 24 08:40:27 2019 by root via cibadmin on pcmk-1

2 nodes configured
2 resources configured

Online: [ pcmk-1 pcmk-2 ]

Full list of resources:

 Master/Slave Set: WebDataClone [WebData]
     Masters: [ pcmk-1 ]
     Slaves: [ pcmk-2 ]

Daemon Status:
  corosync: active/disabled
  pacemaker: active/disabled
  pcsd: active/enabled
[root@pcmk-1 ~]# 
```
You can see that both Apache and WebFS have been stopped, and that pcmk-1 is the current master for the DRBD device.
Now we can create a new GFS2 filesystem on the DRBD device.

Run the next command on whichever node has the DRBD Primary role. Otherwise, you will receive the message:

```bash
/dev/drbd1: Read-only file system
```

```bash
[root@pcmk-1 ~]# umount /dev/drbd1
[root@pcmk-1 ~]# mkfs.gfs2 -p lock_dlm -j 2 -t mycluster:web /dev/drbd1
It appears to contain an existing filesystem (xfs)
This will destroy any data on /dev/drbd1
Are you sure you want to proceed? [y/n] y
Discarding device contents (may take a while on large devices): Done
Adding journals: Done 
Building resource groups: Done 
Creating quota file: Done
Writing superblock and syncing: Done
Device:                    /dev/drbd1
Block size:                4096
Device size:               0.50 GB (131059 blocks)
Filesystem size:           0.50 GB (131055 blocks)
Journals:                  2
Journal size:              8MB
Resource groups:           4
Locking protocol:          "lock_dlm"
Lock table:                "mycluster:web"
UUID:                      590e1ae3-448e-40e5-afea-168c655ea6cf
[root@pcmk-1 ~]# 
```

The mkfs.gfs2 command required a number of additional parameters:
*  -p lock_dlm specifies that we want to use the kernel’s DLM.
*  -j 2 indicates that the filesystem should reserve enough space for two journals (one for each node that will access the filesystem).
*  -t mycluster:web specifies the lock table name. The format for this field is clustername:fsname. For clustername, we need to use the same value we specified originally with pcs cluster setup --name (which is also the value of cluster_name in /etc/corosync/corosync.conf). If you are unsure what your cluster name is, you can look in /etc/corosync/corosync.conf or execute the command pcs cluster corosync pcmk-1 | grep cluster_name.

Now we can (re-)populate the new filesystem with data (web pages). We’ll create yet another variation on our home page.

```bash


```