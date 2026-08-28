# Build

A quick and dirty shellscript to assist in automating building new software
releases and converting them into basic packages.

The script is mainly aimed at Debian systems, but enough infrastructure is in place to
add different packaging options.

## Components

The following components can be found in this repository:

### build

This is the main script to automatically build software. The basic idea is based around
recipes. For a recipe the following steps will be executed:

* Retrieve the latest version of the software available from the source
* Build the software if a newer version is available then last build
* Create a package from the build software
* Ship the package to a repository

Everthing is based around bash shell code.

### torepo

This is a very simple example of how to copy a package to a repository, in this case
freight based.
