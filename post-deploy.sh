#!/bin/bash
value=$( grep -ic "entry" /etc/hosts )
if [ $value -eq 0 ]
then
echo "
################ ceph-cookbook host entry ############
19.168.122.101 pcmk-1.clusterlabs.org pcmk-1
19.168.122.102 pcmk-2.clusterlabs.org pcmk-2
######################################################
" >> /etc/hosts
fi
sudo rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
sudo rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
sudo yum install -y pacemaker pcs psmisc policycoreutils-python gfs2-utils dlm kmod-drbd84 drbd84-utils fence-agents-ipmilan