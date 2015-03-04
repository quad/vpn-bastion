dep 'provision' do
  requires 'local apt sources'.with('cn'),
           'upgraded packages',
           'vpn',
           'vnc',
           'bastion'
end

dep 'local apt sources', :country do
  target = '/etc/apt/sources.list'
  template = dependency.load_path.parent / 'sources.list.erb'

  met? { Babushka::Renderable.new(target).from?(template) }
  meet {
    render_erb template, :to => target, :sudo => true
    Babushka::AptHelper.update_pkg_lists "Updating apt with #{country} mirrors"
  }
end

dep 'upgraded packages' do
  met? {
    upgrade_check = `#{Babushka::AptHelper.pkg_cmd} -s upgrade`
    upgrade_check.include?("0 packages upgraded") || upgrade_check.include?("0 upgraded")
  }
  meet { log_shell 'Upgrading distribution',
                   "#{Babushka::AptHelper.pkg_cmd} -y upgrade",
                   :sudo => Babushka::AptHelper.should_sudo? }
end

dep 'bastion' do
  requires dep('pptpd.managed'),
           'pptp.conf',
           'pptpd-options',
           'chap-secrets'

  requires 'sysctl.conf',
           'rc.local'
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

  met? { Babushka::Renderable.new(target).from?(template) }
  meet {
    render_erb template, :to => target, :sudo => true
    sudo '/etc/rc.local'
  }
end

dep 'pptp.conf' do
  target = '/etc/pptp.conf'
  template = dependency.load_path.parent / 'pptp.conf.erb'

  met? { Babushka::Renderable.new(target).from?(template) }
  meet { render_erb template, :to => target, :sudo => true }
end

dep 'pptpd-options' do
  target = '/etc/ppp/pptpd-options'
  template = dependency.load_path.parent / 'pptp-options.erb'

  met? { Babushka::Renderable.new(target).from?(template) }
  meet {
    render_erb template, :to => target, :sudo => true
    sudo 'service pptpd restart'
  }
end

dep 'chap-secrets' do
  target = '/etc/ppp/chap-secrets'
  template = dependency.load_path.parent / 'chap-secrets.erb'

  before { sudo "chmod 644 '#{target}'" }
  met? { Babushka::Renderable.new(target) }
  meet { render_erb template, :to => target, :sudo => true }
  after { sudo "chmod 600 '#{target}'" }
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
    yield
    sudo "chmod 700 '#{target.dirname}'"
  end

  met? {
    look {
      Babushka::Renderable.new(target).from?(template) &&
      File.stat(target).mode == 0010755
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
