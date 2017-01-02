#!/bin/bash

PKGS="nginx stunnel firefox firefox-esr firejail thinlinc openvpn mysqltuner mitmproxy"

buildnew() {
   pkg=$1
   BUILD=0
   if $( build -q -c $pkg > /dev/null )
   then
      build -q -b $pkg && BUILD=1
   fi
   test $BUILD -eq 1 && build -p $pkg
}

main() {
   for pkg in $PKGS
   do
      buildnew $pkg
   done
}

main $*
