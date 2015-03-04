#!/bin/sh

set -e

sudo sh -c "`curl https://babushka.me/up`"
babushka sources -a vpn-bastion https://github.com/quad/vpn-bastion.git
babushka vpn-bastion:provision
