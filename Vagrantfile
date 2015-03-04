# -*- mode: ruby -*-
# vi: set ft=ruby :

unless Vagrant.has_plugin?('vagrant-babushka')
  raise 'vagrant-babushka plugin is not installed!'
end

Vagrant.configure(2) do |config|
  config.vm.box = 'ubuntu/trusty64'

  config.vm.provision :babushka do |babushka|
    babushka.local_deps_path = '.'
    babushka.meet 'provision'
  end
end
