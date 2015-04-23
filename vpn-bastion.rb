require 'securerandom'
require 'socket'
require 'tempfile'

dep 'provision' do
  requires 'hostname'.with('vpn-bastion'),
           'upgraded packages',
           'unattended upgrades',
           'vpn',
           'vnc',
           'bastion',
           'ipsec'
end

dep 'ipsec' do
  requires 'eth0.cfg.file',
           dep('openswan.managed') { provides 'ipsec' },
           dep('xl2tpd.managed'),
           'ipsec.conf.file',
           'ipsec.secrets.file',
           'xl2tpd.conf',
           'options.xl2tpd.file',
           'chap-secrets.file'
end

dep 'eth0.cfg.file' do
  target '/etc/network/interfaces.d/eth0.cfg'
  source 'eth0.cfg.erb'
end

dep 'ipsec.conf.file' do
  target '/etc/ipsec.conf'
  source 'ipsec.conf.erb'

  after { sudo 'service ipsec reload' }
end

dep 'ipsec.secrets.file' do
  target '/etc/ipsec.secrets'
  source 'ipsec.secrets.erb'
  perms 600

  def secrets_file
    dependency.load_path.parent / 'secrets'
  end

  def secret
    if secrets_file.p.exists? 
      secrets_file.read
    else
      SecureRandom.random_number(36**12).to_s(36).rjust(12, "0").tap do |s|
        secrets_file.write s
      end
    end
  end
end

dep 'xl2tpd.conf' do
  def target
    '/etc/xl2tpd/xl2tpd.conf'.p
  end

  def source
    dependency.load_path.parent / 'xl2tpd.conf.erb'
  end

  def source_sha
    Digest::SHA2.digest source.read
  end

  def target_sha
    Digest::SHA2.digest target.read
  end

  met? { source_sha == target_sha  }
  meet { sudo "cp '#{source}' '#{target}'" }
  after { sudo 'service xl2tpd restart' }
end

dep 'options.xl2tpd.file' do
  target '/etc/ppp/options.xl2tpd'
  source 'options.xl2tpd.erb'
end

dep 'chap-secrets.file' do
  target '/etc/ppp/chap-secrets'
  source 'chap-secrets.erb'
  perms 600
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

dep 'unattended upgrades' do
  def conf
    '/etc/apt/apt.conf.d/20auto-upgrades'.p.read || ''
  end

  met? { conf.include? 'Unattended-Upgrade "1"' }
  meet {
    sudo %(echo 'unattended-upgrades unattended-upgrades/enable_auto_updates select true' | debconf-set-selections)
    sudo %(dpkg-reconfigure -f noninteractive unattended-upgrades)
  }
end

dep 'bastion' do
  requires 'sysctl.conf.file',
           'rc.local.file',
	   dep('tinyproxy.managed'),
           'dhclient.conf.file'
end

dep 'sysctl.conf.file' do
  target '/etc/sysctl.conf'
  source 'sysctl.conf.erb'

  after { sudo 'sysctl -p' }
end

dep 'rc.local.file' do
  target '/etc/rc.local'
  source 'rc.local.erb'

  def our_ip
    Socket.ip_address_list.find { |a| a.ipv4? && !a.ipv4_loopback? }.ip_address
  end

  def jenkins
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

  after { sudo '/etc/rc.local' }
end

dep 'vpn' do
  requires 'openjdk.managed',
           'openjdk i386.managed',
           dep('firefox.managed'),
           dep('xterm.managed'),
           'update-alternatives fix'
end

dep 'dhclient.conf.file' do
  target '/etc/dhcp/dhclient.conf'
  source 'dhclient.conf.erb'
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

meta :file do
  accepts_value_for :source
  accepts_value_for :target
  accepts_value_for :perms

  template {
    def template
      dependency.load_path.parent / source
    end

    def peek restricted_filename
      if restricted_filename.p.readable?
        yield restricted_filename
      else
        Tempfile.open(restricted_filename.p.basename.to_s) do |tf|
          tfn = tf.path.p
          tfn.write sudo("cat '#{restricted_filename}'")
          yield tfn
        end
      end
    end

    met? {
      peek(target) { |fn| Babushka::Renderable.new(fn).from?(template) }
    }
    meet {
      render_erb template, :to => target, :sudo => true, :perms => perms || 644
    }
  }
end
