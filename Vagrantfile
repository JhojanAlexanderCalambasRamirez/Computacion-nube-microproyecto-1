# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|

  if Vagrant.has_plugin?("vagrant-vbguest")
    config.vbguest.no_install  = true
    config.vbguest.auto_update = false
    config.vbguest.no_remote   = true
  end

  # =========================
  # WEB1 - NodeJS - Consul Server
  # IP: 192.168.100.11
  # =========================
  config.vm.define "web1" do |web1|
    web1.vm.box      = "bento/ubuntu-22.04"
    web1.vm.hostname = "web1"
    web1.vm.network "private_network", ip: "192.168.100.11"

    web1.vm.provision "shell", path: "scripts/provision_web.sh"

    web1.vm.provider "virtualbox" do |vb|
      vb.name   = "web1"
      vb.memory = 1024
      vb.cpus   = 1
    end
  end

  # =========================
  # WEB2 - NodeJS - Consul Agent
  # IP: 192.168.100.12
  # =========================
  config.vm.define "web2" do |web2|
    web2.vm.box      = "bento/ubuntu-22.04"
    web2.vm.hostname = "web2"
    web2.vm.network "private_network", ip: "192.168.100.12"

    web2.vm.provision "shell", path: "scripts/provision_web.sh"

    web2.vm.provider "virtualbox" do |vb|
      vb.name   = "web2"
      vb.memory = 1024
      vb.cpus   = 1
    end
  end

  # =========================
  # HAPROXY - Balanceador de Carga
  # IP: 192.168.100.10
  # Puertos redirigidos al Mac anfitrion:
  #   localhost:8080 - trafico web (HAProxy puerto 80)
  #   localhost:8404 - GUI estadisticas HAProxy
  # =========================
  config.vm.define "haproxy" do |haproxy|
    haproxy.vm.box      = "bento/ubuntu-22.04"
    haproxy.vm.hostname = "haproxy"
    haproxy.vm.network "private_network", ip: "192.168.100.10"
    haproxy.vm.network "forwarded_port", guest: 80,   host: 8080 
    haproxy.vm.network "forwarded_port", guest: 8404, host: 8404   

    haproxy.vm.provision "shell", path: "scripts/provision_haproxy.sh"

    haproxy.vm.provider "virtualbox" do |vb|
      vb.name   = "haproxy"
      vb.memory = 1024
      vb.cpus   = 1
    end
  end

end
