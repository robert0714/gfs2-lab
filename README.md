# Configure the Cluster Software
##  Allow cluster services through firewall

On each node, allow cluster-related services through the local firewall:

```bash
# firewall-cmd --permanent --add-service=high-availability
success
# firewall-cmd --reload
success
```
If you are using iptables directly, or some other firewall solution besides firewalld, simply open the following ports, which can be used by various clustering components: TCP ports 2224, 3121, and 21064, and UDP port 5405.
If you run into any problems during testing, you might want to disable the firewall and SELinux entirely until you have everything working. This may create significant security issues and should not be performed on machines that will be exposed to the outside world, but may be appropriate during development and testing on a protected host.
To disable security measures:

```bash
[root@pcmk-1 ~]# setenforce 0
[root@pcmk-1 ~]# sed -i.bak "s/SELINUX=enforcing/SELINUX=permissive/g" /etc/selinux/config
[root@pcmk-1 ~]# systemctl mask firewalld.service
[root@pcmk-1 ~]# systemctl stop firewalld.service
[root@pcmk-1 ~]# iptables --flush

```
## Enable pcs Daemon

Before the cluster can be configured, the pcs daemon must be started and enabled to start at boot time on each node. This daemon works with the pcs command-line interface to manage synchronizing the corosync configuration across all nodes in the cluster.
Start and enable the daemon by issuing the following commands on each node:

```bash
# systemctl start pcsd.service
# systemctl enable pcsd.service
Created symlink from /etc/systemd/system/multi-user.target.wants/pcsd.service to /usr/lib/systemd/system/pcsd.service.
```
The installed packages will create a hacluster user with a disabled password. While this is fine for running pcs commands locally, the account needs a login password in order to perform such tasks as syncing the corosync configuration, or starting and stopping the cluster on other nodes.
This tutorial will make use of such commands, so now we will set a password for the hacluster user, using the same password on both nodes:

```bash
# passwd hacluster
Changing password for user hacluster.
New password:
Retype new password:
passwd: all authentication tokens updated successfully.

```
Alternatively, to script this process or set the password on a different machine from the one you’re logged into, you can use the --stdin option for passwd:
```bash
[root@pcmk-1 ~]# ssh pcmk-2 -- 'echo mysupersecretpassword | passwd --stdin hacluster'
```

## Configure Corosync
On either node, use pcs cluster auth to authenticate as the hacluster user:
```bash
[root@pcmk-1 ~]# pcs cluster auth pcmk-1 pcmk-2
Username: hacluster
Password:
pcmk-2: Authorized
pcmk-1: Authorized
```
Next, use pcs cluster setup on the same node to generate and synchronize the corosync configuration:

```bash
[root@pcmk-1 ~]# pcs cluster setup --name mycluster pcmk-1 pcmk-2
Destroying cluster on nodes: pcmk-1, pcmk-2...
pcmk-2: Stopping Cluster (pacemaker)...
pcmk-1: Stopping Cluster (pacemaker)...
pcmk-1: Successfully destroyed cluster
pcmk-2: Successfully destroyed cluster

Sending 'pacemaker_remote authkey' to 'pcmk-1', 'pcmk-2'
pcmk-2: successful distribution of the file 'pacemaker_remote authkey'
pcmk-1: successful distribution of the file 'pacemaker_remote authkey'
Sending cluster config files to the nodes...
pcmk-1: Succeeded
pcmk-2: Succeeded

Synchronizing pcsd certificates on nodes pcmk-1, pcmk-2...
pcmk-2: Success
pcmk-1: Success
Restarting pcsd on the nodes in order to reload the certificates...
pcmk-2: Success
pcmk-1: Success
```
If you received an authorization error for either of those commands, make sure you configured the hacluster user account on each node with the same password.

If you are not using pcs for cluster administration, follow whatever procedures are appropriate for your tools to create a corosync.conf and copy it to all nodes.
The pcs command will configure corosync to use UDP unicast transport; if you choose to use multicast instead, choose a multicast address carefully. [5](http://web.archive.org/web/20101211210536/http://29west.com/docs/THPM/multicast-address-assignment.html)

The final corosync.conf configuration on each node should look something like the sample in [Appendix B, Sample Corosync Configuration](https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Clusters_from_Scratch/ap-corosync-conf.html).

# Start and Verify Cluster
## Start the Cluster
Now that corosync is configured, it is time to start the cluster. The command below will start corosync and pacemaker on both nodes in the cluster. If you are issuing the start command from a different node than the one you ran the pcs cluster auth command on earlier, you must authenticate on the current node you are logged into before you will be allowed to start the cluster.
```bash
[root@pcmk-1 ~]# pcs cluster start --all
pcmk-1: Starting Cluster...
pcmk-2: Starting Cluster...
```
### Note
An alternative to using the pcs cluster start --all command is to issue either of the below command sequences on each node in the cluster separately:
```bash
# pcs cluster start
Starting Cluster...
```
or
```bash
# systemctl start corosync.service
# systemctl start pacemaker.service
```
### Important
In this example, we are not enabling the corosync and pacemaker services to start at boot. If a cluster node fails or is rebooted, you will need to run pcs cluster start nodename (or --all) to start the cluster on it. While you could enable the services to start at boot, requiring a manual start of cluster services gives you the opportunity to do a post-mortem investigation of a node failure before returning it to the cluster.

## Verify Corosync Installation
First, use corosync-cfgtool to check whether cluster communication is happy:
```bash
[root@pcmk-1 ~]# corosync-cfgtool -s
Printing ring status.
Local node ID 1
RING ID 0
        id      = 19.168.122.101
        status  = ring 0 active with no faults
```
We can see here that everything appears normal with our fixed IP address (not a 127.0.0.x loopback address) listed as the id, and no faults for the status.
If you see something different, you might want to start by checking the node’s network, firewall and SELinux configurations.
Next, check the membership and quorum APIs:
```bash
[root@pcmk-1 ~]# corosync-cmapctl | grep members
runtime.totem.pg.mrp.srp.members.1.config_version (u64) = 0
runtime.totem.pg.mrp.srp.members.1.ip (str) = r(0) ip(19.168.122.101)
runtime.totem.pg.mrp.srp.members.1.join_count (u32) = 1
runtime.totem.pg.mrp.srp.members.1.status (str) = joined
runtime.totem.pg.mrp.srp.members.2.config_version (u64) = 0
runtime.totem.pg.mrp.srp.members.2.ip (str) = r(0) ip(19.168.122.102)
runtime.totem.pg.mrp.srp.members.2.join_count (u32) = 1
runtime.totem.pg.mrp.srp.members.2.status (str) = joined

[root@pcmk-1 ~]# pcs status corosync

Membership information
\----------------------
    Nodeid      Votes Name
         1          1 pcmk-1 (local)
         2          1 pcmk-2
```
You should see both nodes have joined the cluster.

## Verify Pacemaker Installation
Now that we have confirmed that Corosync is functional, we can check the rest of the stack. Pacemaker has already been started, so verify the necessary processes are running:
```bash
[root@pcmk-1 ~]# ps axf
  PID TTY      STAT   TIME COMMAND
    2 ?        S      0:00 [kthreadd]
...lots of processes...
11635 ?        SLsl   0:03 corosync
11642 ?        Ss     0:00 /usr/sbin/pacemakerd -f
11643 ?        Ss     0:00  \_ /usr/libexec/pacemaker/cib
11644 ?        Ss     0:00  \_ /usr/libexec/pacemaker/stonithd
11645 ?        Ss     0:00  \_ /usr/libexec/pacemaker/lrmd
11646 ?        Ss     0:00  \_ /usr/libexec/pacemaker/attrd
11647 ?        Ss     0:00  \_ /usr/libexec/pacemaker/pengine
11648 ?        Ss     0:00  \_ /usr/libexec/pacemaker/crmd
```
If that looks OK, check the pcs status output:
```bash
[root@pcmk-1 ~]# pcs status
Cluster name: mycluster
WARNING: no stonith devices and stonith-enabled is not false
Stack: corosync
Current DC: pcmk-2 (version 1.1.18-11.el7_5.3-2b07d5c5a9) - partition with quorum
Last updated: Mon Sep 10 16:37:34 2018
Last change: Mon Sep 10 16:30:53 2018 by hacluster via crmd on pcmk-2

2 nodes configured
0 resources configured

Online: [ pcmk-1 pcmk-2 ]

No resources


Daemon Status:
  corosync: active/disabled
  pacemaker: active/disabled
  pcsd: active/enabled
```
Finally, ensure there are no start-up errors from corosync or pacemaker (aside from messages relating to not having STONITH configured, which are OK at this point):
```bash
[root@pcmk-1 ~]# journalctl -b | grep -i error
```
### Note
Other operating systems may report startup errors in other locations, for example /var/log/messages.

Repeat these checks on the other node. The results should be the same.
# Create an Active/Passive Cluster
## Explore the Existing Configuration
When Pacemaker starts up, it automatically records the number and details of the nodes in the cluster, as well as which stack is being used and the version of Pacemaker being used.
The first few lines of output should look like this:
```bash
[root@pcmk-1 ~]# pcs status
Cluster name: mycluster
WARNING: no stonith devices and stonith-enabled is not false
Stack: corosync
Current DC: pcmk-2 (version 1.1.18-11.el7_5.3-2b07d5c5a9) - partition with quorum
Last updated: Mon Sep 10 16:41:46 2018
Last change: Mon Sep 10 16:30:53 2018 by hacluster via crmd on pcmk-2

2 nodes configured
0 resources configured

Online: [ pcmk-1 pcmk-2 ]
```
For those who are not of afraid of XML, you can see the raw cluster configuration and status by using the pcs cluster cib command.

Example 5.1. The last XML you’ll see in this document

```bash
[root@pcmk-1 ~]# pcs cluster cib

```

```xml
<cib crm_feature_set="3.0.14" validate-with="pacemaker-2.10" epoch="5" num_updates="4" admin_epoch="0" cib-last-written="Mon Sep 10 16:30:53 2018" update-origin="pcmk-2" update-client="crmd" update-user="hacluster" have-quorum="1" dc-uuid="2">
  <configuration>
    <crm_config>
      <cluster_property_set id="cib-bootstrap-options">
        <nvpair id="cib-bootstrap-options-have-watchdog" name="have-watchdog" value="false"/>
        <nvpair id="cib-bootstrap-options-dc-version" name="dc-version" value="1.1.18-11.el7_5.3-2b07d5c5a9"/>
        <nvpair id="cib-bootstrap-options-cluster-infrastructure" name="cluster-infrastructure" value="corosync"/>
        <nvpair id="cib-bootstrap-options-cluster-name" name="cluster-name" value="mycluster"/>
      </cluster_property_set>
    </crm_config>
    <nodes>
      <node id="1" uname="pcmk-1"/>
      <node id="2" uname="pcmk-2"/>
    </nodes>
    <resources/>
    <constraints/>
  </configuration>
  <status>
    <node_state id="1" uname="pcmk-1" in_ccm="true" crmd="online" crm-debug-origin="do_state_transition" join="member" expected="member">
      <lrm id="1">
        <lrm_resources/>
      </lrm>
    </node_state>
    <node_state id="2" uname="pcmk-2" in_ccm="true" crmd="online" crm-debug-origin="do_state_transition" join="member" expected="member">
      <lrm id="2">
        <lrm_resources/>
      </lrm>
    </node_state>
  </status>
</cib>

```

Before we make any changes, it’s a good idea to check the validity of the configuration.

```bash
[root@pcmk-1 ~]# crm_verify -L -V
   error: unpack_resources: Resource start-up disabled since no STONITH resources have been defined
   error: unpack_resources: Either configure some or disable STONITH with the stonith-enabled option
   error: unpack_resources: NOTE: Clusters with shared data need STONITH to ensure data integrity
Errors found during check: config not valid
```

As you can see, the tool has found some errors.
In order to guarantee the safety of your data, [6](https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Clusters_from_Scratch/ch05.html#ftn.idm140003574989168) fencing (also called STONITH) is enabled by default. However, it also knows when no STONITH configuration has been supplied and reports this as a problem (since the cluster will not be able to make progress if a situation requiring node fencing arises).
We will disable this feature for now and configure it later.
To disable STONITH, set the stonith-enabled cluster option to false:

```bash
[root@pcmk-1 ~]# pcs property set stonith-enabled=false
[root@pcmk-1 ~]# crm_verify -L

```
With the new cluster option set, the configuration is now valid.

### Warning
The use of stonith-enabled=false is completely inappropriate for a production cluster. It tells the cluster to simply pretend that failed nodes are safely powered off. Some vendors will refuse to support clusters that have STONITH disabled. We disable STONITH here only to defer the discussion of its configuration, which can differ widely from one installation to the next. See [Section 8.1, “What is STONITH?”](https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Clusters_from_Scratch/ch08.html#_what_is_stonith) for information on why STONITH is important and details on how to configure it.

## Add a Resource
Our first resource will be a unique IP address that the cluster can bring up on either node. Regardless of where any cluster service(s) are running, end users need a consistent address to contact them on. Here, I will choose 19.168.122.120 as the floating address, give it the imaginative name ClusterIP and tell the cluster to check whether it is running every 30 seconds.

### Warning
The chosen address must not already be in use on the network. Do not reuse an IP address one of the nodes already has configured.
```bash
[root@pcmk-1 ~]# pcs resource create ClusterIP ocf:heartbeat:IPaddr2 \
    ip=19.168.122.120 cidr_netmask=24 op monitor interval=30s
```

Another important piece of information here is ocf:heartbeat:IPaddr2. This tells Pacemaker three things about the resource you want to add:
*  The first field (ocf in this case) is the standard to which the resource script conforms and where to find it.
*  The second field (heartbeat in this case) is standard-specific; for OCF resources, it tells the cluster which OCF namespace the resource script is in.
*  The third field (IPaddr2 in this case) is the name of the resource script.

To obtain a list of the available resource standards (the ocf part of ocf:heartbeat:IPaddr2), run:

```bash
[root@pcmk-1 ~]# pcs resource standards
lsb
ocf
service
systemd
```

To obtain a list of the available OCF resource providers (the heartbeat part of ocf:heartbeat:IPaddr2), run:

```bash
[root@pcmk-1 ~]# pcs resource providers
heartbeat
openstack
pacemaker
```

Finally, if you want to see all the resource agents available for a specific OCF provider (the IPaddr2 part of ocf:heartbeat:IPaddr2), run:

```bash
[root@pcmk-1 ~]# pcs resource agents ocf:heartbeat
apache
aws-vpc-move-ip
awseip
awsvip
azure-lb
clvm
.
. (skipping lots of resources to save space)
.
symlink
tomcat
VirtualDomain
Xinetd
```

Now, verify that the IP resource has been added, and display the cluster’s status to see that it is now active:

```bash
[root@pcmk-1 ~]# pcs status
Cluster name: mycluster
Stack: corosync
Current DC: pcmk-2 (version 1.1.18-11.el7_5.3-2b07d5c5a9) - partition with quorum
Last updated: Mon Sep 10 16:55:26 2018
Last change: Mon Sep 10 16:53:42 2018 by root via cibadmin on pcmk-1

2 nodes configured
1 resource configured

Online: [ pcmk-1 pcmk-2 ]

Full list of resources:

 ClusterIP      (ocf::heartbeat:IPaddr2):       Started pcmk-1

Daemon Status:
  corosync: active/disabled
  pacemaker: active/disabled
  pcsd: active/enabled
```

## Perform a Failover

Since our ultimate goal is high availability, we should test failover of our new resource before moving on.
First, find the node on which the IP address is running.

```bash
[root@pcmk-1 ~]# pcs status
Cluster name: mycluster
Stack: corosync
Current DC: pcmk-2 (version 1.1.18-11.el7_5.3-2b07d5c5a9) - partition with quorum
Last updated: Mon Sep 10 16:55:26 2018
Last change: Mon Sep 10 16:53:42 2018 by root via cibadmin on pcmk-1

2 nodes configured
1 resource configured

Online: [ pcmk-1 pcmk-2 ]

Full list of resources:

 ClusterIP      (ocf::heartbeat:IPaddr2):       Started pcmk-2

Daemon Status:
  corosync: active/disabled
  pacemaker: active/disabled
  pcsd: active/enabled
```
Notice that pcmk-1 is OFFLINE for cluster purposes (its pcsd is still active, allowing it to receive pcs commands, but it is not participating in the cluster).
Also notice that ClusterIP is now running on pcmk-2 — failover happened automatically, and no errors are reported.

### Quorum
If a cluster splits into two (or more) groups of nodes that can no longer communicate with each other (aka. partitions), quorum is used to prevent resources from starting on more nodes than desired, which would risk data corruption.
A cluster has quorum when more than half of all known nodes are online in the same partition, or for the mathematically inclined, whenever the following equation is true:

```bash
total_nodes < 2 * active_nodes
```

For example, if a 5-node cluster split into 3- and 2-node paritions, the 3-node partition would have quorum and could continue serving resources. If a 6-node cluster split into two 3-node partitions, neither partition would have quorum; pacemaker’s default behavior in such cases is to stop all resources, in order to prevent data corruption.
Two-node clusters are a special case. By the above definition, a two-node cluster would only have quorum when both nodes are running. This would make the creation of a two-node cluster pointless, but corosync has the ability to treat two-node clusters as if only one node is required for quorum.
The pcs cluster setup command will automatically configure two_node: 1 in corosync.conf, so a two-node cluster will "just work".
If you are using a different cluster shell, you will have to configure corosync.conf appropriately yourself.


Now, simulate node recovery by restarting the cluster stack on pcmk-1, and check the cluster’s status. (It may take a little while before the cluster gets going on the node, but it eventually will look like the below.)

```bash

[root@pcmk-1 ~]# pcs cluster start pcmk-1
pcmk-1: Starting Cluster...
[root@pcmk-1 ~]# pcs status
Cluster name: mycluster
Stack: corosync
Current DC: pcmk-2 (version 1.1.18-11.el7_5.3-2b07d5c5a9) - partition with quorum
Last updated: Mon Sep 10 17:00:04 2018
Last change: Mon Sep 10 16:53:42 2018 by root via cibadmin on pcmk-1

2 nodes configured
1 resource configured

Online: [ pcmk-1 pcmk-2 ]

Full list of resources:

 ClusterIP      (ocf::heartbeat:IPaddr2):       Started pcmk-2

Daemon Status:
  corosync: active/disabled
  pacemaker: active/disabled
  pcsd: active/enabled

```

## Prevent Resources from Moving after Recovery

In most circumstances, it is highly desirable to prevent healthy resources from being moved around the cluster. Moving resources almost always requires a period of downtime. For complex services such as databases, this period can be quite long.
To address this, Pacemaker has the concept of resource stickiness, which controls how strongly a service prefers to stay running where it is. You may like to think of it as the "cost" of any downtime. By default, Pacemaker assumes there is zero cost associated with moving resources and will do so to achieve "optimal" [7](https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Clusters_from_Scratch/_prevent_resources_from_moving_after_recovery.html#ftn.idm140003650713760) resource placement. We can specify a different stickiness for every resource, but it is often sufficient to change the default.

```bash
[root@pcmk-1 ~]# pcs resource defaults resource-stickiness=100
Warning: Defaults do not apply to resources which override them with their own defined values
[root@pcmk-1 ~]# pcs resource defaults
resource-stickiness: 100
```

[7] Pacemaker’s definition of optimal may not always agree with that of a human’s. The order in which Pacemaker processes lists of resources and nodes creates implicit preferences in situations where the administrator has not explicitly specified them.


# Add Apache HTTP Server as a Cluster Service

Now that we have a basic but functional active/passive two-node cluster, we’re ready to add some real services. We’re going to start with Apache HTTP Server because it is a feature of many clusters and relatively simple to configure.

## Install Apache

Before continuing, we need to make sure Apache is installed on both hosts. We also need the wget tool in order for the cluster to be able to check the status of the Apache server.

```bash
# yum install -y httpd wget
# firewall-cmd --permanent --add-service=http
# firewall-cmd --reload
```

### Important
Do not enable the httpd service. Services that are intended to be managed via the cluster software should never be managed by the OS. It is often useful, however, to manually start the service, verify that it works, then stop it again, before adding it to the cluster. This allows you to resolve any non-cluster-related problems before continuing. Since this is a simple example, we’ll skip that step here.

## Create Website Documents
We need to create a page for Apache to serve. On CentOS 7.5, the default Apache document root is /var/www/html, so we’ll create an index file there. For the moment, we will simplify things by serving a static site and manually synchronizing the data between the two nodes, so run this command on both nodes:

```bash
# cat <<-END >/var/www/html/index.html
 <html>
 <body>My Test Site - $(hostname)</body>
 </html>
END
```

## Enable the Apache status URL
n order to monitor the health of your Apache instance, and recover it if it fails, the resource agent used by Pacemaker assumes the server-status URL is available. On both nodes, enable the URL with:

```bash
# cat <<-END >/etc/httpd/conf.d/status.conf
 <Location /server-status>
    SetHandler server-status
    Require local
 </Location>
END
```

### Note
If you are using a different operating system, server-status may already be enabled or may be configurable in a different location. If you are using a version of Apache HTTP Server less than 2.4, the syntax will be different.


## Configure the Cluster

At this point, Apache is ready to go, and all that needs to be done is to add it to the cluster. Let’s call the resource WebSite. We need to use an OCF resource script called apache in the heartbeat namespace. [8](https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Clusters_from_Scratch/_configure_the_cluster.html#ftn.idm140003639327568) The script’s only required parameter is the path to the main Apache configuration file, and we’ll tell the cluster to check once a minute that Apache is still running.

```bash
[root@pcmk-1 ~]# pcs resource create WebSite ocf:heartbeat:apache  \
      configfile=/etc/httpd/conf/httpd.conf \
      statusurl="http://localhost/server-status" \
      op monitor interval=1min
```

By default, the operation timeout for all resources' start, stop, and monitor operations is 20 seconds. In many cases, this timeout period is less than a particular resource’s advised timeout period. For the purposes of this tutorial, we will adjust the global operation timeout default to 240 seconds.

```bash
[root@pcmk-1 ~]# pcs resource op defaults timeout=240s
Warning: Defaults do not apply to resources which override them with their own defined values
[root@pcmk-1 ~]# pcs resource op defaults
timeout: 240s
```

### Note
In a production cluster, it is usually better to adjust each resource’s start, stop, and monitor timeouts to values that are appropriate to the behavior observed in your environment, rather than adjust the global default.
After a short delay, we should see the cluster start Apache.

```bash

[root@pcmk-1 ~]# pcs status
Cluster name: mycluster
Stack: corosync
Current DC: pcmk-2 (version 1.1.18-11.el7_5.3-2b07d5c5a9) - partition with quorum
Last updated: Mon Sep 10 17:06:22 2018
Last change: Mon Sep 10 17:05:41 2018 by root via cibadmin on pcmk-1

2 nodes configured
2 resources configured

Online: [ pcmk-1 pcmk-2 ]

Full list of resources:

 ClusterIP      (ocf::heartbeat:IPaddr2):       Started pcmk-2
 WebSite        (ocf::heartbeat:apache):        Started pcmk-1

Daemon Status:
  corosync: active/disabled
  pacemaker: active/disabled
  pcsd: active/enabled
```

Wait a moment, the WebSite resource isn’t running on the same host as our IP address!

### Note
 
If, in the pcs status output, you see the WebSite resource has failed to start, then you’ve likely not enabled the status URL correctly. You can check whether this is the problem by running:

```bash
wget -O - http://localhost/server-status
```

If you see Not Found or Forbidden in the output, then this is likely the problem. Ensure that the <Location /server-status> block is correct.

[8](https://clusterlabs.org/pacemaker/doc/en-US/Pacemaker/2.0/html/Clusters_from_Scratch/_configure_the_cluster.html#idm140003639327568) Compare the key used here, ocf:heartbeat:apache, with the one we used earlier for the IP address, ocf:heartbeat:IPaddr2


## Ensure Resources Run on the Same Host

To reduce the load on any one machine, Pacemaker will generally try to spread the configured resources across the cluster nodes. However, we can tell the cluster that two resources are related and need to run on the same host (or not at all). Here, we instruct the cluster that WebSite can only run on the host that ClusterIP is active on.
To achieve this, we use a colocation constraint that indicates it is mandatory for WebSite to run on the same node as ClusterIP. The "mandatory" part of the colocation constraint is indicated by using a score of INFINITY. The INFINITY score also means that if ClusterIP is not active anywhere, WebSite will not be permitted to run.

### Note

If ClusterIP is not active anywhere, WebSite will not be permitted to run anywhere.

### Important

Colocation constraints are "directional", in that they imply certain things about the order in which the two resources will have a location chosen. In this case, we’re saying that WebSite needs to be placed on the same machine as ClusterIP, which implies that the cluster must know the location of ClusterIP before choosing a location for WebSite.

```bash
[root@pcmk-1 ~]# pcs constraint colocation add WebSite with ClusterIP INFINITY
[root@pcmk-1 ~]# pcs constraint
Location Constraints:
Ordering Constraints:
Colocation Constraints:
  WebSite with ClusterIP (score:INFINITY)
Ticket Constraints:
[root@pcmk-1 ~]# pcs status
Cluster name: mycluster
Stack: corosync
Current DC: pcmk-2 (version 1.1.18-11.el7_5.3-2b07d5c5a9) - partition with quorum
Last updated: Mon Sep 10 17:08:54 2018
Last change: Mon Sep 10 17:08:27 2018 by root via cibadmin on pcmk-1

2 nodes configured
2 resources configured

Online: [ pcmk-1 pcmk-2 ]

Full list of resources:

 ClusterIP      (ocf::heartbeat:IPaddr2):       Started pcmk-2
 WebSite        (ocf::heartbeat:apache):        Started pcmk-2

Daemon Status:
  corosync: active/disabled
  pacemaker: active/disabled
  pcsd: active/enabled
```

## Ensure Resources Start and Stop in Order
Like many services, Apache can be configured to bind to specific IP addresses on a host or to the wildcard IP address. If Apache binds to the wildcard, it doesn’t matter whether an IP address is added before or after Apache starts; Apache will respond on that IP just the same. However, if Apache binds only to certain IP address(es), the order matters: If the address is added after Apache starts, Apache won’t respond on that address.
To be sure our WebSite responds regardless of Apache’s address configuration, we need to make sure ClusterIP not only runs on the same node, but starts before WebSite. A colocation constraint only ensures the resources run together, not the order in which they are started and stopped.
We do this by adding an ordering constraint. By default, all order constraints are mandatory, which means that the recovery of ClusterIP will also trigger the recovery of WebSite.

```bash
[root@pcmk-1 ~]# pcs constraint order ClusterIP then WebSite
Adding ClusterIP WebSite (kind: Mandatory) (Options: first-action=start then-action=start)
[root@pcmk-1 ~]# pcs constraint
Location Constraints:
Ordering Constraints:
  start ClusterIP then start WebSite (kind:Mandatory)
Colocation Constraints:
  WebSite with ClusterIP (score:INFINITY)
Ticket Constraints:
```

## Prefer One Node Over Another
Pacemaker does not rely on any sort of hardware symmetry between nodes, so it may well be that one machine is more powerful than the other.
In such cases, you may want to host the resources on the more powerful node when it is available, to have the best performance — or you may want to host the resources on the less powerful node when it’s available, so you don’t have to worry about whether you can handle the load after a failover.
To do this, we create a location constraint.
In the location constraint below, we are saying the WebSite resource prefers the node pcmk-1 with a score of 50. Here, the score indicates how strongly we’d like the resource to run at this location.

```bash
[root@pcmk-1 ~]# pcs constraint location WebSite prefers pcmk-1=50
[root@pcmk-1 ~]# pcs constraint
Location Constraints:
  Resource: WebSite
    Enabled on: pcmk-1 (score:50)
Ordering Constraints:
  start ClusterIP then start WebSite (kind:Mandatory)
Colocation Constraints:
  WebSite with ClusterIP (score:INFINITY)
Ticket Constraints:
[root@pcmk-1 ~]# pcs status
Cluster name: mycluster
Stack: corosync
Current DC: pcmk-2 (version 1.1.18-11.el7_5.3-2b07d5c5a9) - partition with quorum
Last updated: Mon Sep 10 17:21:41 2018
Last change: Mon Sep 10 17:21:14 2018 by root via cibadmin on pcmk-1

2 nodes configured
2 resources configured

Online: [ pcmk-1 pcmk-2 ]

Full list of resources:

 ClusterIP      (ocf::heartbeat:IPaddr2):       Started pcmk-2
 WebSite        (ocf::heartbeat:apache):        Started pcmk-2

Daemon Status:
  corosync: active/disabled
  pacemaker: active/disabled
  pcsd: active/enabled
```

Wait a minute, the resources are still on pcmk-2!
Even though WebSite now prefers to run on pcmk-1, that preference is (intentionally) less than the resource stickiness (how much we preferred not to have unnecessary downtime).
To see the current placement scores, you can use a tool called crm_simulate.


```bash
[root@pcmk-1 ~]# crm_simulate -sL

Current cluster status:
Online: [ pcmk-1 pcmk-2 ]

 ClusterIP      (ocf::heartbeat:IPaddr2):       Started pcmk-2
 WebSite        (ocf::heartbeat:apache):        Started pcmk-2

Allocation scores:
native_color: ClusterIP allocation score on pcmk-1: 50
native_color: ClusterIP allocation score on pcmk-2: 200
native_color: WebSite allocation score on pcmk-1: -INFINITY
native_color: WebSite allocation score on pcmk-2: 100

Transition Summary:
```

## Move Resources Manually

There are always times when an administrator needs to override the cluster and force resources to move to a specific location. In this example, we will force the WebSite to move to pcmk-1.
We will use the pcs resource move command to create a temporary constraint with a score of INFINITY. While we could update our existing constraint, using move allows to easily get rid of the temporary constraint later. If desired, we could even give a lifetime for the constraint, so it would expire automatically — but we don’t that in this example.

```bash
[root@pcmk-1 ~]# pcs resource move WebSite pcmk-1
[root@pcmk-1 ~]# pcs constraint
Location Constraints:
  Resource: WebSite
    Enabled on: pcmk-1 (score:50)
    Enabled on: pcmk-1 (score:INFINITY) (role: Started)
Ordering Constraints:
  start ClusterIP then start WebSite (kind:Mandatory)
Colocation Constraints:
  WebSite with ClusterIP (score:INFINITY)
Ticket Constraints:
[root@pcmk-1 ~]# pcs status
Cluster name: mycluster
Stack: corosync
Current DC: pcmk-2 (version 1.1.18-11.el7_5.3-2b07d5c5a9) - partition with quorum
Last updated: Mon Sep 10 17:28:55 2018
Last change: Mon Sep 10 17:28:27 2018 by root via crm_resource on pcmk-1

2 nodes configured
2 resources configured

Online: [ pcmk-1 pcmk-2 ]

Full list of resources:

 ClusterIP      (ocf::heartbeat:IPaddr2):       Started pcmk-1
 WebSite        (ocf::heartbeat:apache):        Started pcmk-1

Daemon Status:
  corosync: active/disabled
  pacemaker: active/disabled
  pcsd: active/enabled
```

Once we’ve finished whatever activity required us to move the resources to pcmk-1 (in our case nothing), we can then allow the cluster to resume normal operation by removing the new constraint. Due to our first location constraint and our default stickiness, the resources will remain on pcmk-1.
We will use the pcs resource clear command, which removes all temporary constraints previously created by pcs resource move or pcs resource ban.

```bash
[root@pcmk-1 ~]# pcs resource clear WebSite
[root@pcmk-1 ~]# pcs constraint
Location Constraints:
  Resource: WebSite
    Enabled on: pcmk-1 (score:50)
Ordering Constraints:
  start ClusterIP then start WebSite (kind:Mandatory)
Colocation Constraints:
  WebSite with ClusterIP (score:INFINITY)
Ticket Constraints:
```

Note that the INFINITY location constraint is now gone. If we check the cluster status, we can also see that (as expected) the resources are still active on pcmk-1.

```bash
[root@pcmk-1 ~]# pcs status
Cluster name: mycluster
Stack: corosync
Current DC: pcmk-2 (version 1.1.18-11.el7_5.3-2b07d5c5a9) - partition with quorum
Last updated: Mon Sep 10 17:31:47 2018
Last change: Mon Sep 10 17:31:04 2018 by root via crm_resource on pcmk-1

2 nodes configured
2 resources configured

Online: [ pcmk-1 pcmk-2 ]

Full list of resources:

 ClusterIP      (ocf::heartbeat:IPaddr2):       Started pcmk-1
 WebSite        (ocf::heartbeat:apache):        Started pcmk-1

Daemon Status:
  corosync: active/disabled
  pacemaker: active/disabled
  pcsd: active/enabled
```

To remove the constraint with the score of 50, we would first get the constraint’s ID using pcs constraint --full, then remove it with pcs constraint remove and the ID. We won’t show those steps here, but feel free to try it on your own, with the help of the pcs man page if necessary.


# Creating DRDB



```bash 
# semanage permissive -a drbd_t
```

We will configure DRBD to use port 7789, so allow that port from each host to the other:

```bash
[root@pcmk-1 ~]# firewall-cmd --permanent --add-rich-rule='rule family="ipv4" \
    source address="19.168.122.102" port port="7789" protocol="tcp" accept'
success
[root@pcmk-1 ~]# firewall-cmd --reload
success
```

```bash
[root@pcmk-2 ~]# firewall-cmd --permanent --add-rich-rule='rule family="ipv4" \
    source address="19.168.122.101" port port="7789" protocol="tcp" accept'
success
[root@pcmk-2 ~]# firewall-cmd --reload
success
```

### Note
In this example, we have only two nodes, and all network traffic is on the same LAN. In production, it is recommended to use a dedicated, isolated network for cluster-related traffic, so the firewall configuration would likely be different; one approach would be to add the dedicated network interfaces to the trusted zone.




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
```

## Allocate a Disk Volume for DRBD

DRBD will need its own block device on each node. This can be a physical disk partition or logical volume, of whatever size you need for your data. For this document, we will use a 512MiB logical volume, which is more than sufficient for a single HTML file and (later) GFS2 metadata.


```bash
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

Or  ( Actually Repeat for the second node, making sure to use the same size: )

```bash
[root@pcmk-1 ~]# ssh pcmk-2 -- lvcreate --name drbd-demo --size 512M centos_pcmk-2
 Logical volume "drbd-demo" created.
```
## Configure DRBD

DRBD will not be able to run under the default SELinux security policies. If you are familiar with SELinux, you can modify the policies in a more fine-grained manner, but here we will simply exempt DRBD processes from SELinux control:


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

### Note
In this example, we create an xfs filesystem with no special options. In a production environment, you should choose a filesystem type and options that are suitable for your application.

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
[root@pcmk-1 ~]# chcon -R --reference=/var/www/html /mnt
[root@pcmk-1 ~]# umount /dev/drbd1
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

We can see that WebDataClone (our DRBD device) is running as master (DRBD’s primary role) on pcmk-1 and slave (DRBD’s secondary role) on pcmk-2.

### Important
The resource agent should load the DRBD module when needed if it’s not already loaded. If that does not happen, configure your operating system to load the module at boot time. For CentOS 7.5, you would run this on both nodes:

```bash
# echo drbd >/etc/modules-load.d/drbd.conf
```

## Configure the Cluster for the Filesystem

Now that we have a working DRBD device, we need to mount its filesystem.
In addition to defining the filesystem, we also need to tell the cluster where it can be located (only on the DRBD Primary) and when it is allowed to start (after the Primary was promoted).
We are going to take a shortcut when creating the resource this time. Instead of explicitly saying we want the ocf:heartbeat:Filesystem script, we are only going to ask for Filesystem. We can do this because we know there is only one resource script named Filesystem available to pacemaker, and that pcs is smart enough to fill in the ocf:heartbeat: portion for us correctly in the configuration. If there were multiple Filesystem scripts from different OCF providers, we would need to specify the exact one we wanted.
Once again, we will queue our changes to a file and then push the new configuration to the cluster as the final step.

```bash
[root@pcmk-1 ~]# pcs cluster cib fs_cfg
[root@pcmk-1 ~]# pcs -f fs_cfg resource create WebFS Filesystem \
        device="/dev/drbd1" directory="/var/www/html" fstype="xfs"
Assumed agent name 'ocf:heartbeat:Filesystem' (deduced from 'Filesystem')
[root@pcmk-1 ~]# pcs -f fs_cfg constraint colocation add \
        WebFS with WebDataClone INFINITY with-rsc-role=Master
[root@pcmk-1 ~]# pcs -f fs_cfg constraint order \
        promote WebDataClone then start WebFS
Adding WebDataClone WebFS (kind: Mandatory) (Options: first-action=promote then-action=start)
```

We also need to tell the cluster that Apache needs to run on the same machine as the filesystem and that it must be active before Apache can start.

```bash
[root@pcmk-1 ~]# pcs -f fs_cfg constraint colocation add WebSite with WebFS INFINITY
[root@pcmk-1 ~]# pcs -f fs_cfg constraint order WebFS then WebSite
Adding WebFS WebSite (kind: Mandatory) (Options: first-action=start then-action=start)
```


Review the updated configuration.

```bash
[root@pcmk-1 ~]# pcs -f fs_cfg constraint
Location Constraints:
  Resource: WebSite
    Enabled on: pcmk-1 (score:50)
Ordering Constraints:
  start ClusterIP then start WebSite (kind:Mandatory)
  promote WebDataClone then start WebFS (kind:Mandatory)
  start WebFS then start WebSite (kind:Mandatory)
Colocation Constraints:
  WebSite with ClusterIP (score:INFINITY)
  WebFS with WebDataClone (score:INFINITY) (with-rsc-role:Master)
  WebSite with WebFS (score:INFINITY)
Ticket Constraints:
[root@pcmk-1 ~]# pcs -f fs_cfg resource show
 ClusterIP      (ocf::heartbeat:IPaddr2):       Started pcmk-1
 WebSite        (ocf::heartbeat:apache):        Started pcmk-1
 Master/Slave Set: WebDataClone [WebData]
     Masters: [ pcmk-1 ]
     Slaves: [ pcmk-2 ]
 WebFS  (ocf::heartbeat:Filesystem):    Stopped
```

After reviewing the new configuration, upload it and watch the cluster put it into effect.

```bash
[root@pcmk-1 ~]# pcs cluster cib-push fs_cfg --config
CIB updated
[root@pcmk-1 ~]# pcs status
Cluster name: mycluster
Stack: corosync
Current DC: pcmk-2 (version 1.1.18-11.el7_5.3-2b07d5c5a9) - partition with quorum
Last updated: Mon Sep 10 18:02:24 2018
Last change: Mon Sep 10 18:02:14 2018 by root via cibadmin on pcmk-1

2 nodes configured
5 resources configured

Online: [ pcmk-1 pcmk-2 ]

Full list of resources:

 ClusterIP      (ocf::heartbeat:IPaddr2):       Started pcmk-1
 WebSite        (ocf::heartbeat:apache):        Started pcmk-1
 Master/Slave Set: WebDataClone [WebData]
     Masters: [ pcmk-1 ]
     Slaves: [ pcmk-2 ]
 WebFS  (ocf::heartbeat:Filesystem):    Started pcmk-1

Daemon Status:
  corosync: active/disabled
  pacemaker: active/disabled
  pcsd: active/enabled
```

##  Test Cluster Failover

Previously, we used pcs cluster stop pcmk-1 to stop all cluster services on pcmk-1, failing over the cluster resources, but there is another way to safely simulate node failure.
We can put the node into standby mode. Nodes in this state continue to run corosync and pacemaker but are not allowed to run resources. Any resources found active there will be moved elsewhere. This feature can be particularly useful when performing system administration tasks such as updating packages used by cluster resources.
Put the active node into standby mode, and observe the cluster move all the resources to the other node. The node’s status will change to indicate that it can no longer host resources, and eventually all the resources will move.



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


# Configure STONITH

## What is STONITH?

STONITH (Shoot The Other Node In The Head aka. fencing) protects your data from being corrupted by rogue nodes or unintended concurrent access.

Just because a node is unresponsive doesn’t mean it has stopped accessing your data. The only way to be 100% sure that your data is safe, is to use STONITH to ensure that the node is truly offline before allowing the data to be accessed from another node.

STONITH also has a role to play in the event that a clustered service cannot be stopped. In this case, the cluster uses STONITH to force the whole node offline, thereby making it safe to start the service elsewhere.

##  Choose a STONITH Device

It is crucial that your STONITH device can allow the cluster to differentiate between a node failure and a network failure.

A common mistake people make when choosing a STONITH device is to use a remote power switch (such as many on-board IPMI controllers) that shares power with the node it controls. If the power fails in such a case, the cluster cannot be sure whether the node is really offline, or active and suffering from a network fault, so the cluster will stop all resources to avoid a possible split-brain situation.

Likewise, any device that relies on the machine being active (such as SSH-based "devices" sometimes used during testing) is inappropriate.

## Configure the Cluster for STONITH
1.  Install the STONITH agent(s). To see what packages are available, run yum search fence-. Be sure to install the package(s) on all cluster nodes.
1.  Configure the STONITH device itself to be able to fence your nodes and accept fencing requests. This includes any necessary configuration on the device and on the nodes, and any firewall or SELinux changes needed. Test the communication between the device and your nodes.
1.  Find the correct STONITH agent script: pcs stonith list
1.  Find the parameters associated with the device: pcs stonith describe agent_name
1.  Create a local copy of the CIB: pcs cluster cib stonith_cfg
1.  Create the fencing resource: pcs -f stonith_cfg stonith create stonith_id stonith_device_type [stonith_device_options]Any flags that do not take arguments, such as --ssl, should be passed as ssl=1.
1.  Enable STONITH in the cluster: pcs -f stonith_cfg property set stonith-enabled=true
1.  If the device does not know how to fence nodes based on their uname, you may also need to set the special pcmk_host_map 1.  parameter. See man pacemaker-fenced for details.
1.  If the device does not support the list command, you may also need to set the special pcmk_host_list and/or pcmk_host_check parameters. See man pacemaker-fenced for details.
1.  If the device does not expect the victim to be specified with the port parameter, you may also need to set the special pcmk_host_argument parameter. See man pacemaker-fenced for details.
1.  Commit the new configuration: pcs cluster cib-push stonith_cfg
1.  Once the STONITH resource is running, test it (you might want to stop the cluster on that machine first): stonith_admin --reboot nodename


## Example

For this example, assume we have a chassis containing four nodes and an IPMI device active on 10.0.0.1. Following the steps above would go something like this:

Step 1: Install the fence-agents-ipmilan package on both nodes.

Step 2: Configure the IP address, authentication credentials, etc. in the IPMI device itself.

Step 3: Choose the fence_ipmilan STONITH agent.

Step 4: Obtain the agent’s possible parameters:

```bash
[root@pcmk-1 ~]# pcs stonith describe fence_ipmilan
fence_ipmilan - Fence agent for IPMI

fence_ipmilan is an I/O Fencing agentwhich can be used with machines controlled by IPMI.This agent calls support software ipmitool (http://ipmitool.sf.net/). WARNING! This fence agent might report success before the node is powered off. You should use -m/method onoff if your fence device works correctly with that option.

Stonith options:
  ipport: TCP/UDP port to use for connection with device
  hexadecimal_kg: Hexadecimal-encoded Kg key for IPMIv2 authentication
  port: IP address or hostname of fencing device (together with --port-as-ip)
  inet6_only: Forces agent to use IPv6 addresses only
  ipaddr: IP Address or Hostname
  passwd_script: Script to retrieve password
  method: Method to fence (onoff|cycle)
  inet4_only: Forces agent to use IPv4 addresses only
  passwd: Login password or passphrase
  lanplus: Use Lanplus to improve security of connection
  auth: IPMI Lan Auth type.
  cipher: Ciphersuite to use (same as ipmitool -C parameter)
  target: Bridge IPMI requests to the remote target address
  privlvl: Privilege level on IPMI device
  timeout: Timeout (sec) for IPMI operation
  login: Login Name
  verbose: Verbose mode
  debug: Write debug information to given file
  power_wait: Wait X seconds after issuing ON/OFF
  login_timeout: Wait X seconds for cmd prompt after login
  delay: Wait X seconds before fencing is started
  power_timeout: Test X seconds for status change after ON/OFF
  ipmitool_path: Path to ipmitool binary
  shell_timeout: Wait X seconds for cmd prompt after issuing command
  port_as_ip: Make "port/plug" to be an alias to IP address
  retry_on: Count of attempts to retry power on
  sudo: Use sudo (without password) when calling 3rd party sotfware.
  priority: The priority of the stonith resource. Devices are tried in order of highest priority to lowest.
  pcmk_host_map: A mapping of host names to ports numbers for devices that do not support host names. Eg. node1:1;node2:2,3 would tell the cluster to use port 1 for node1 and ports 2 and
                 3 for node2
  pcmk_host_list: A list of machines controlled by this device (Optional unless pcmk_host_check=static-list).
  pcmk_host_check: How to determine which machines are controlled by the device. Allowed values: dynamic-list (query the device), static-list (check the pcmk_host_list attribute), none
                   (assume every device can fence every machine)
  pcmk_delay_max: Enable a random delay for stonith actions and specify the maximum of random delay. This prevents double fencing when using slow devices such as sbd. Use this to enable a
                  random delay for stonith actions. The overall delay is derived from this random delay value adding a static delay so that the sum is kept below the maximum delay.
  pcmk_delay_base: Enable a base delay for stonith actions and specify base delay value. This prevents double fencing when different delays are configured on the nodes. Use this to enable
                   a static delay for stonith actions. The overall delay is derived from a random delay value adding this static delay so that the sum is kept below the maximum delay.
  pcmk_action_limit: The maximum number of actions can be performed in parallel on this device Pengine property concurrent-fencing=true needs to be configured first. Then use this to
                     specify the maximum number of actions can be performed in parallel on this device. -1 is unlimited.

Default operations:
  monitor: interval=60s
```

Step 5: pcs cluster cib stonith_cfg

Step 6: Here are example parameters for creating our STONITH resource:

```bash
[root@pcmk-1 ~]# pcs -f stonith_cfg stonith create ipmi-fencing fence_ipmilan \
      pcmk_host_list="pcmk-1 pcmk-2" ipaddr=10.0.0.1 login=testuser \
      passwd=acd123 op monitor interval=60s
[root@pcmk-1 ~]# pcs -f stonith_cfg stonith
 ipmi-fencing   (stonith:fence_ipmilan):        Stopped
```

Steps 7-10: Enable STONITH in the cluster:

```bash
[root@pcmk-1 ~]# pcs -f stonith_cfg property set stonith-enabled=true
[root@pcmk-1 ~]# pcs -f stonith_cfg property
Cluster Properties:
 cluster-infrastructure: corosync
 cluster-name: mycluster
 dc-version: 1.1.18-11.el7_5.3-2b07d5c5a9
 have-watchdog: false
 stonith-enabled: true
```

Step 11: pcs cluster cib-push stonith_cfg --config
Step 12: Test:

```bash
[root@pcmk-1 ~]# pcs cluster stop pcmk-2
[root@pcmk-1 ~]# stonith_admin --reboot pcmk-2
```

After a successful test, login to any rebooted nodes, and start the cluster (with pcs cluster start).



# Convert Cluster to Active/Active

The primary requirement for an Active/Active cluster is that the data required for your services is available, simultaneously, on both machines. Pacemaker makes no requirement on how this is achieved; you could use a SAN if you had one available, but since DRBD supports multiple Primaries, we can continue to use it here.

## Install Cluster Filesystem Software

The only hitch is that we need to use a cluster-aware filesystem. The one we used earlier with DRBD, xfs, is not one of those. Both OCFS2 and GFS2 are supported; here, we will use GFS2.

On both nodes, install the GFS2 command-line utilities and the Distributed Lock Manager (DLM) required by cluster filesystems:

```bash
# yum install -y gfs2-utils dlm
```

## Configure the Cluster for the DLM

The DLM needs to run on both nodes, so we’ll start by creating a resource for it (using the ocf:pacemaker:controld resource script), and clone it:

```bash
[root@pcmk-1 ~]# pcs cluster cib dlm_cfg
[root@pcmk-1 ~]# pcs -f dlm_cfg resource create dlm \
        ocf:pacemaker:controld op monitor interval=60s
[root@pcmk-1 ~]# pcs -f dlm_cfg resource clone dlm clone-max=2 clone-node-max=1
[root@pcmk-1 ~]# pcs -f dlm_cfg resource show
 ClusterIP      (ocf::heartbeat:IPaddr2):       Started pcmk-1
 WebSite        (ocf::heartbeat:apache):        Started pcmk-1
 Master/Slave Set: WebDataClone [WebData]
     Masters: [ pcmk-1 ]
     Slaves: [ pcmk-2 ]
 WebFS  (ocf::heartbeat:Filesystem):    Started pcmk-1
 Clone Set: dlm-clone [dlm]
     Stopped: [ pcmk-1 pcmk-2 ]
```

Activate our new configuration, and see how the cluster responds:

```bash
[root@pcmk-1 ~]# pcs cluster cib-push dlm_cfg --config
CIB updated
[root@pcmk-1 ~]# pcs status
Cluster name: mycluster
Stack: corosync
Current DC: pcmk-1 (version 1.1.18-11.el7_5.3-2b07d5c5a9) - partition with quorum
Last updated: Tue Sep 11 10:18:30 2018
Last change: Tue Sep 11 10:16:49 2018 by hacluster via crmd on pcmk-2

2 nodes configured
8 resources configured

Online: [ pcmk-1 pcmk-2 ]

Full list of resources:

 ipmi-fencing   (stonith:fence_ipmilan):        Started pcmk-1
 ClusterIP      (ocf::heartbeat:IPaddr2):       Started pcmk-1
 WebSite        (ocf::heartbeat:apache):        Started pcmk-1
 Master/Slave Set: WebDataClone [WebData]
     Masters: [ pcmk-1 ]
     Slaves: [ pcmk-2 ]
 WebFS  (ocf::heartbeat:Filesystem):    Started pcmk-1
 Clone Set: dlm-clone [dlm]
     Started: [ pcmk-1 pcmk-2 ]

Daemon Status:
  corosync: active/disabled
  pacemaker: active/disabled
  pcsd: active/enabled
```

## Create and Populate GFS2 Filesystem

Before we do anything to the existing partition, we need to make sure it is unmounted. We do this by telling the cluster to stop the WebFS resource. This will ensure that other resources (in our case, Apache) using WebFS are not only stopped, but stopped in the correct order.

```bash
[root@pcmk-1 ~]# pcs resource disable WebFS
[root@pcmk-1 ~]# pcs resource
 ClusterIP      (ocf::heartbeat:IPaddr2):       Started pcmk-1
 WebSite        (ocf::heartbeat:apache):        Stopped
 Master/Slave Set: WebDataClone [WebData]
     Masters: [ pcmk-1 ]
     Slaves: [ pcmk-2 ]
 WebFS  (ocf::heartbeat:Filesystem):    Stopped (disabled)
 Clone Set: dlm-clone [dlm]
     Started: [ pcmk-1 pcmk-2 ]
```

You can see that both Apache and WebFS have been stopped, and that pcmk-1 is the current master for the DRBD device.

Now we can create a new GFS2 filesystem on the DRBD device.

### Warning
This will erase all previous content stored on the DRBD device. Ensure you have a copy of any important data.

### Important
Run the next command on whichever node has the DRBD Primary role. Otherwise, you will receive the message:

```bash
/dev/drbd1: Read-only file system
```

```bash
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
Filesystem size:           0.50 GB (131056 blocks)
Journals:                  2
Resource groups:           3
Locking protocol:          "lock_dlm"
Lock table:                "mycluster:web"
UUID:                      0bcbffab-cada-4105-94d1-be8a26669ee0
```

The mkfs.gfs2 command required a number of additional parameters:
*  -p lock_dlm specifies that we want to use the kernel’s DLM.
*  -j 2 indicates that the filesystem should reserve enough space for two journals (one for each node that will access the filesystem).
*  -t mycluster:web specifies the lock table name. The format for this field is clustername:fsname. For clustername, we need to use the same value we specified originally with pcs cluster setup --name (which is also the value of cluster_name in /etc/corosync/corosync.conf). If you are unsure what your cluster name is, you can look in /etc/corosync/corosync.conf or execute the command pcs cluster corosync pcmk-1 | grep cluster_name.

Now we can (re-)populate the new filesystem with data (web pages). We’ll create yet another variation on our home page.

```bash
[root@pcmk-1 ~]# mount /dev/drbd1 /mnt
[root@pcmk-1 ~]# cat <<-END >/mnt/index.html
<html>
<body>My Test Site - GFS2</body>
</html>
END
[root@pcmk-1 ~]# chcon -R --reference=/var/www/html /mnt
[root@pcmk-1 ~]# umount /dev/drbd1
[root@pcmk-1 ~]# drbdadm verify wwwdata
```
## Reconfigure the Cluster for GFS2

With the WebFS resource stopped, let’s update the configuration.

```bash
[root@pcmk-1 ~]# pcs resource show WebFS
 Resource: WebFS (class=ocf provider=heartbeat type=Filesystem)
  Attributes: device=/dev/drbd1 directory=/var/www/html fstype=xfs
  Meta Attrs: target-role=Stopped
  Operations: monitor interval=20 timeout=40 (WebFS-monitor-interval-20)
              notify interval=0s timeout=60 (WebFS-notify-interval-0s)
              start interval=0s timeout=60 (WebFS-start-interval-0s)
              stop interval=0s timeout=60 (WebFS-stop-interval-0s)
```

The fstype option needs to be updated to gfs2 instead of xfs.

```bash
[root@pcmk-1 ~]# pcs resource update WebFS fstype=gfs2
[root@pcmk-1 ~]# pcs resource show WebFS
 Resource: WebFS (class=ocf provider=heartbeat type=Filesystem)
  Attributes: device=/dev/drbd1 directory=/var/www/html fstype=gfs2
  Meta Attrs: target-role=Stopped
  Operations: monitor interval=20 timeout=40 (WebFS-monitor-interval-20)
              notify interval=0s timeout=60 (WebFS-notify-interval-0s)
              start interval=0s timeout=60 (WebFS-start-interval-0s)
              stop interval=0s timeout=60 (WebFS-stop-interval-0s)
```

GFS2 requires that DLM be running, so we also need to set up new colocation and ordering constraints for it:

```bash
[root@pcmk-1 ~]# pcs constraint colocation add WebFS with dlm-clone INFINITY
[root@pcmk-1 ~]# pcs constraint order dlm-clone then WebFS
Adding dlm-clone WebFS (kind: Mandatory) (Options: first-action=start then-action=start)
```

## Clone the IP address

There’s no point making the services active on both locations if we can’t reach them both, so let’s clone the IP address.

The IPaddr2 resource agent has built-in intelligence for when it is configured as a clone. It will utilize a multicast MAC address to have the local switch send the relevant packets to all nodes in the cluster, together with iptables clusterip rules on the nodes so that any given packet will be grabbed by exactly one node. This will give us a simple but effective form of load-balancing requests between our two nodes.

Let’s start a new config, and clone our IP:

```bash
[root@pcmk-1 ~]# pcs cluster cib loadbalance_cfg
[root@pcmk-1 ~]# pcs -f loadbalance_cfg resource clone ClusterIP \
     clone-max=2 clone-node-max=2 globally-unique=true
```

* clone-max=2 tells the resource agent to split packets this many ways. This should equal the number of nodes that can host the IP.
* clone-node-max=2 says that one node can run up to 2 instances of the clone. This should also equal the number of nodes that can host the IP, so that if any node goes down, another node can take over the failed node’s "request bucket". Otherwise, requests intended for the failed node would be discarded.
* globally-unique=true tells the cluster that one clone isn’t identical to another (each handles a different "bucket"). This also tells the resource agent to insert iptables rules so each host only processes packets in its bucket(s).