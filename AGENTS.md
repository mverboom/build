To be able to test the script, please use the build.lnw.verboom.net container. The ssh config for you has been
setup that you can log in with the unpriviledged user builduser with the command:

ssh build

The git repository you are working in here is available on that system in the directory:

/home/builduser/bin

That directory is the git worktree (branch `docker`); the scripts there are tracked files, not
symlinks. Sync it with `git pull --ff-only origin docker`.
