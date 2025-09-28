# Vagrantfile
Vagrant.configure("2") do |config|
  # Global defaults
  config.vm.box_check_update = true
  config.vm.synced_folder ".", "/vagrant", disabled: true   # avoid shared-folder overhead
  config.ssh.insert_key = false

  BOX_NAME = "ubuntu/focal64"   # Ubuntu 20.04 official image; Vagrant will auto-download on first `up`

  # Common inline provisioner: keep lab networking simple for Phase 1 checks
  COMMON_PROVISION = <<-SHELL
    set -e
    sudo ufw disable || true
    # make sure hostname resolves to its IP (helps some tools)
    if ! grep -q "$(hostname)" /etc/hosts; then
      echo "$(hostname -I | awk '{print $1}')  $(hostname)" | sudo tee -a /etc/hosts
    fi
  SHELL

  # ---- Control plane nodes ----
  (1..3).each do |i|
    config.vm.define "master-#{i}" do |master|
      master.vm.box = BOX_NAME
      master.vm.hostname = "master-#{i}"
      master.vm.network "private_network", ip: "192.168.100.#{10 + i}"
      master.vm.provider "virtualbox" do |vb|
        vb.name   = "homelab-master-#{i}"
        vb.memory = 4096
        vb.cpus   = 2
        vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
        vb.gui = false
      end
      master.vm.provision "shell", inline: COMMON_PROVISION
    end
  end

  # ---- Worker nodes ----
  (1..3).each do |i|
    config.vm.define "worker-#{i}" do |worker|
      worker.vm.box = BOX_NAME
      worker.vm.hostname = "worker-#{i}"
      worker.vm.network "private_network", ip: "192.168.100.#{20 + i}"
      worker.vm.provider "virtualbox" do |vb|
        vb.name   = "homelab-worker-#{i}"
        vb.memory = 6144
        vb.cpus   = 2
        vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
        vb.gui = false
      end
      worker.vm.provision "shell", inline: COMMON_PROVISION
    end
  end

  # ---- Infra services node ----
  config.vm.define "infra" do |infra|
    infra.vm.box = BOX_NAME
    infra.vm.hostname = "infra"
    infra.vm.network "private_network", ip: "192.168.100.50"
    infra.vm.provider "virtualbox" do |vb|
      vb.name   = "homelab-infra"
      vb.memory = 4096
      vb.cpus   = 2
      vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
      vb.gui = false
    end
    infra.vm.provision "shell", inline: COMMON_PROVISION
  end
end

