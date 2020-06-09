# NAME

debclean - revert system to know set of packages

# SYNOPSYS

`debclean [OPTION]`

# DESCRIPTION

The script will try and remove any package that are not on a predetermined list.
This allows for a quick revert to a known state of the system, making reproducible
builds easier.

The following arguments can be used:

`-u`

Create a new base list. All packages on the base list are required. This determines
the basic state of the system.

`-c`

Checks the system for any packages installed that are not on the base list and
removes them. It also installs any missing packages that are on the base list.
These actions requires the user running the script to have sudo permissions
for the `apt-get` command.

`-l`

Outputs a list of packages that have been extra installed compared to the base list
and those who have been removed.

# CONFIGURATION FILE

A configuration file is not required, but it allows to overwrite the location where
administrative files are being stored. If no configuration file is specified,
the location where the script is run will also be used the store the administration
files.

The following variable can be used:

`LOCATION`

The value of this variable needs to refer to a directory where the administrative
files can be stored

# FILES

`~/.debclean`

Configuration file

`$LOCATION/debclean.baselist-$HOSTNAME`

Baselist for a specific system

# EXAMPLES

Initialise a new base list for the system.

`debclean -u`

# AUTHOR

Written by Mark Verboom

# REPORTING BUGS

Preferably by opening an issue on the github page.

# COPYRIGHT

Copyright  ©  2014  Free Software Foundation, Inc.  License GPLv3+: GNU
GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
This is free software: you are free  to  change  and  redistribute  it.
There is NO WARRANTY, to the extent permitted by law.

