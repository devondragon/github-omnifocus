# github-omnifocus



Ruby script to create and manage OmniFocus tasks based on your GitHub issues

What it does:

It pulls back all unresolved GitHub issues that are assigned to you and if it hasn't already created a OmniFocus task for that issue, it creates a new one.  The title of the task is the GitHub issue number followed by the summary from the issue.  The note part of the OmniFocus task will contain the URL to the GitHub issue so you can easily go right to it, and the body of the issue

It also checks all the OmniFocus tasks that look like they are related to GitHub issues, and checks to see if the matching issue has been resolved.  If so, it marks the task as complete. If a task has been re-assigned to someone else or unassigned it will remove it from Omnifocus.

Very simple.  The Ruby code is straight forward and it should be easy to modify to do other things to meet your specific needs.

This uses [Bundler](http://bundler.io/), so you will need to run the following to set everything up.

```
gem install bundler
bundle install
```

This also supports [rbenv](http://rbenv.org/), if you happen to be using it.

You'll need to copy ghofsync.yaml.sample from the git checkout to ~/.ghofsync.yaml, and then edit is as appropriate.

Make sure that you have a project in context in Omnifocus that matches what you used in the configuration file.

You can run the script manually or you can add a cron entry to run it periodically (it will take a minute or so to run so don't run it too often), or you can use the OS X launchd to schedule it (this is preferred).  If you are using the keychain option, you MUST use the launchd scheduler isntead of cron.

You can use crontab -e to edit your user crontab and create an entry like this:

```
*/10 * * * * cd ~/dev/git/github-omnifocus/bin && ./githubomnifocus.rb
```


To install it in launchd, edit ghofsync.plist to meet your needs and copy it to ~/Library/LaunchAgents/ghofsync.plist and run

```
launchctl load ~/Library/LaunchAgents/ghofsync.plist
```

That should be it!  If it doesn't work, try adding some puts debug statements and running it manually.  
	
