require 'socket'

dep 'provision' do
  requires 'hostname'.with('vpn-bastion'),
           'upgraded packages',
           'vpn',
           'vnc',
           'bastion'
end

dep 'upgraded packages' do
  met? {
    Babushka::AptHelper.update_pkg_lists "Updating apt package lists"
    upgrade_check = `#{Babushka::AptHelper.pkg_cmd} -s -y upgrade`
    upgrade_check =~ /\b0 packages upgraded/ || upgrade_check =~ /\b0 upgraded/
  }
  meet { log_shell 'Upgrading distribution',
                   "#{Babushka::AptHelper.pkg_cmd} -y upgrade",
                   :sudo => Babushka::AptHelper.should_sudo? }
end

dep 'bastion' do
  requires 'sysctl.conf',
           'rc.local',
	   dep('tinyproxy.managed')
end

dep 'sysctl.conf' do
  target = '/etc/sysctl.conf'
  template = dependency.load_path.parent / 'sysctl.conf.erb'

  met? { Babushka::Renderable.new(target).from?(template) }
  meet {
    render_erb template, :to => target, :sudo => true
    sudo 'sysctl -p'
  }
end

dep 'rc.local' do
  target = '/etc/rc.local'
  template = dependency.load_path.parent / 'rc.local.erb'

  def our_ip
    Socket.ip_address_list.find { |a| a.ipv4? && !a.ipv4_loopback? }.ip_address
  end

  def jira
    {ip: '172.18.94.227', port: 8080}
  end

  def stash
    {ip: '10.1.7.231', port: 443}
  end

  def chendu_network
    '125.69.76.0/24'
  end

  def gateway
    `ip -o route list scope global`.
      split.
      find { |i| i =~ /\d+\.\d+\.\d+\.\d+/ }
  end

  met? { Babushka::Renderable.new(target).from?(template) }
  meet {
    render_erb template, :to => target, :sudo => true
    sudo '/etc/rc.local'
  }
end

dep 'vpn' do
  requires 'openjdk.managed',
           'openjdk i386.managed',
           dep('firefox.managed'),
           dep('xterm.managed'),
           'update-alternatives fix'
end

dep 'update-alternatives fix' do
  name = 'update-alternatives'
  bin = '/usr/bin' / name
  sbin = '/usr/sbin' / name

  met? { sbin.readlink == bin }
  meet { sudo "ln -s '#{bin}' '#{sbin}'" }
end

dep 'openjdk.managed' do
  installs { via :apt, 'openjdk-7-jre', 'icedtea-plugin' }
  provides 'java'
end

dep 'openjdk i386.managed' do
  requires 'dpkg architecture'.with('i386')
  installs { via :apt, 'openjdk-7-jre:i386' }
  provides 'java'
end

dep 'dpkg architecture', :arch do
  met? { `dpkg --print-foreign-architectures`.include? arch }
  meet {
    sudo "dpkg --add-architecture #{arch}"
    Babushka::AptHelper.update_pkg_lists "Updating apt with #{arch} architecture"
  }
end

dep 'vnc' do
  requires 'xstartup',
           dep('tightvncserver.managed'),
           dep('matchbox-window-manager.managed')
end

dep 'xstartup' do
  requires 'vnc directory'

  def target
    '~/.vnc/xstartup'.p
  end

  def template
    dependency.load_path.parent / 'xstartup.erb'
  end

  def look
    sudo "chmod 755 '#{target.dirname}'"
    retval = yield
    sudo "chmod 700 '#{target.dirname}'"
    retval
  end

  met? {
    look {
      Babushka::Renderable.new(target).from?(template) && File.stat(target).mode == 0100755
    }
  }
  meet {
    look {
      render_erb template, :to => target, :sudo => true
      sudo "chmod 755 '#{target}'"
    }
  }
end

dep 'vnc directory' do
  target = '~/.vnc'.p

  met? {
    target.dir? &&
         File.stat(target).mode == 040700 &&
         File.stat(target).uid == 0
  }
  meet {
    target.mkdir
    sudo "chmod 700 '#{target}'"
    sudo "chown root.root '#{target}'"
  }
end

dep 'hostname', :host_name do
  met? { shell('hostname') == host_name }
  meet {
    sudo "hostnamectl set-hostname #{host_name}"
    sudo "sed -ri 's/^127.0.0.1.*$/127.0.0.1 #{host_name} localhost/' /etc/hosts"
  }
end
