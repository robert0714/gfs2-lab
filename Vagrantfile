# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|
  if (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM) != nil
    config.vm.synced_folder ".", "/vagrant", mount_options: ["dmode=700,fmode=600"]
  else
    config.vm.synced_folder ".", "/vagrant"
  end
  (1..2).each do |i|
    config.vm.define "pcmk-#{i}" do |d|
      d.vm.box = "bento/centos-7.6"
      d.vm.hostname = "pcmk-#{i}"
      d.vm.network "private_network", ip: "19.168.122.10#{i}"
      d.vm.provision :shell, path: "post-deploy.sh",run: "always"
      fileName2 =  "pcmk-#{i}/pcmk-#{i}_disk2.vdi"      
      d.vm.provider "virtualbox" do |v|
        v.memory = 1536
        v.cpus = 1
        unless File.exist?(fileName2)
          v.customize ['createhd', '--filename', fileName2,'--size', 1 * 20480]
          v.customize ['storageattach', :id,  '--storagectl', 'SATA Controller', '--port', 1, '--device', 0, '--type', 'hdd', '--medium', fileName2]
        end
      end
    end
  end
  if Vagrant.has_plugin?("vagrant-vbguest")
    config.vbguest.auto_update = false
    config.vbguest.no_install = true
    config.vbguest.no_remote = true
  end
end