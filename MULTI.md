# Multi

Initially build has been made to easily create debian packages. However,
it would be very handy to also make other types of packages. The most important
being rpm packages.

Some infrastructure is in place to build packages for different platforms, but
this is not complete.

This file documents the issue's that need to be fixed.

## Build environment requirements

The script needs to check for required software based on the type of os it
is running on.

### Progress

* (v) Add OS detection
* (v) Create OS dependant required software function
* Push changes upstream

## Debclean script

The debclean script was named debclean and specifically for debian. However,
the configuration file only has support for 1 post processing command. The
best solution seems to be to change the debclean script to a generic clean
script, that runs the appropriate action depending on the type of packaging
the system uses.

### Progress

* [ ] Initial changeover to clean script
* [ ] Push changes upstream
* [ ] Implement rpm solution
* [ ] Push changes upstream
