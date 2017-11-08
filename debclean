#!/bin/bash
#
# Change system back to state as defined in package list
#
BASE=debclean.baselist-$(hostname)
CUR=/tmp/debclean.curlist

LOC=$( dirname ${BASH_SOURCE[0]})
BASE=$LOC/$BASE

case $1 in
"-u")
   echo "Are you sure you want to overwrite the base list? "
   read answer
   if test "$answer" = "y"
   then
      dpkg -l | grep "^.i" | awk '{print $2}' > $BASE
      echo "Base list updated."
   else
      echo "Base list not updated."
   fi
;;
"-c")
   if test -f $BASE
   then
      dpkg -l | grep "^.i" | awk '{print $2}' > $CUR
      diff $BASE $CUR | grep '<' | cut -d' ' -f2 | xargs sudo apt-get -qq -y install > /dev/null 2>&1
      test ${PIPESTATUS[3]} -ne 0 && echo "Error installing missing packages."
      sudo apt-get -qq -y --purge autoremove > /dev/null 2>&1
      test $? -ne 0 && echo "Error removing no longer required packages."
      diff $BASE $CUR | grep '>' | cut -d' ' -f2 | xargs sudo apt-get -qq --purge -y remove > /dev/null 2>&1
      test ${PIPESTATUS[3]} -ne 0 && echo "Error removing extra packages."
      rm -f $CUR
   else
      echo "No base list is available for this system."
   fi
;;
"-l")
   if test -f $BASE
   then
      dpkg -l | grep "^.i" | awk '{print $2}' > $CUR
      echo "Extra packages installed:"
      diff $BASE $CUR | grep '>' | cut -d' ' -f2
      echo "Packages removed:"
      diff $BASE $CUR | grep '<' | cut -d' ' -f2
      rm -f $CUR
   else
      echo "No base list is available for this system."
   fi
;;
*)
   echo "Usage: debclean.sh"
   echo "  -u  update base list"
   echo "  -l  list difference of current packages with base list"
   echo "  -c  revert packages to configuration in base list"
   exit 1
;;
esac


