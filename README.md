# vpn-bastion

Babushka to setup a Linux box as a VPN bastion.

```shell
$ sh -c "`curl https://raw.githubusercontent.com/quad/vpn-bastion/master/bootstrap.sh`"
```

## How do I log into the VPN?

Where `1.2.3.4` is the IP address for your Ubuntu VM...

```shell
laptop$ ssh ubuntu@1.2.3.4 -L 5901:localhost:5901
ubuntu$ sudo tightvncserver -nolisten tcp -localhost :1
```

Then start a VNC client (*Screen Sharing* on OSX) and connect to `localhost:5901`. The password is `abc123`.

```shell
ubuntu$ firefox
```

Then login to the VPN as normal.

## How do I access Jenkins?

Add the hostname of the Jenkins box to your `/etc/hosts`. Something like:

```
1.2.3.4   taurus.bigcorp.com
```

Then access http://taurus.bigcorp.com:8080/jenkins/ as normal.

## How do I access other things?

Use the SOCKS via SSH proxy.

```shell
laptop$ ssh -ND 8080 ubuntu@1.2.3.4
```

Then change your network SOCKS proxy to `localhost:8080`.
