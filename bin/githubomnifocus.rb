#!/usr/bin/env ruby

require 'bundler/setup'
Bundler.require(:default)

require 'rb-scpt'
require 'yaml'
require 'net/http'
require 'pathname'
require 'octokit'
require "awesome_print"

Octokit.auto_paginate = true

def get_opts
	if  File.file?(ENV['HOME']+'/.ghofsync.yaml')
		config = YAML.load_file(ENV['HOME']+'/.ghofsync.yaml')
	else config = YAML.load <<-EOS
	#YAML CONFIG EXAMPLE
---
github:
  username: ''
  oauth: ''
EOS
	end

	return Trollop::options do
		banner ""
		banner <<-EOS
GitHub OmniFocus Sync Tool

Usage:
	Create a file $HOME/.ghofsync.yaml, with the content:
github:
  username: ''
  oauth: ''

	Run: $ ghofsync --omnifocus_project --github_orga Github organization --github_repo Github repository
---
EOS
  		version 'ghofsync 1.1.0'
		opt :username, 'Github Username', :type => :string, :required => false, :default => config["github"]["username"]
		opt :oauth, 'Github oauth token', :type => :string, :required => false, :default => config["github"]["oauth"]

		opt :omnifocus_project, 'OmniFocus Project', :type => :string, :short => 'p', :required => true
		opt :github_orga, 'Github organization', :type => :string, :short => 'o', :required => true
		opt :github_repo, 'Github repository', :type => :string, :short => 'r', :required => true
	end
end

def get_issues(ghclient, ghproject, ghrepo)
	github_issues = Hash.new
	issues = ghclient.issues "#{ghproject}/#{ghrepo}"
	issues.each do |issue|
		github_issues["#{ghrepo}-##{issue.number}"] = issue
	end
	return github_issues
end

# Task properties
# id (text) : The identifier of the task.
# name (text) : The name of the task.
# note (rich text) : The note of the task.
# container (document, quick entry tree, project, or task, r/o) : The containing task, project or document.
# containing project (project or missing value, r/o) : The task's project, up however many levels of parent tasks. Inbox tasks aren't considered contained by their provisionalliy assigned container, so if the task is actually an inbox task, this will be missing value.
# parent task (task or missing value, r/o) : The task holding this task. If this is missing value, then this is a top level task -- either the root of a project or an inbox item.
# containing document (document or quick entry tree, r/o) : The containing document or quick entry tree of the object.
# in inbox (boolean, r/o) : Returns true if the task itself is an inbox task or if the task is contained by an inbox task.
# primary tag (tag or missing value) : The task's first tag. Setting this will remove the current first tag on the task, if any and move or add the new tag as the first tag on the task. Setting this to missing value will remove the current first tag and leave any other remaining tags.
# completed by children (boolean) : If true, complete when children are completed.
# sequential (boolean) : If true, any children are sequentially dependent.
# flagged (boolean) : True if flagged
# next (boolean, r/o) : If the task is the next task of its containing project, next is true.
# blocked (boolean, r/o) : True if the task has a task that must be completed prior to it being actionable.
# creation date (date) : When the task was created. This can only be set when the object is still in the inserted state. For objects created in the document, it can be passed with the creation properties. For objects in a quick entry tree, it can be set until the quick entry panel is saved.
# modification date (date, r/o) : When the task was last modified.
# defer date (date or missing value) : When the task should become available for action.  syn start date
# due date (date or missing value) : When the task must be finished.
# completion date (date or missing value) : The task's date of completion. This can only be modified on a completed task to backdate the completion date.
# completed (boolean, r/o) : True if the task is completed. Use the "mark complete" and "mark incomplete" commands to change a tasks's status.
# estimated minutes (integer or missing value) : The estimated time, in whole minutes, that this task will take to finish.
# repetition rule (repetition rule or missing value) : The repetition rule for this task, or missing value if it does not repeat.
# next defer date (date or missing value, r/o) : The next defer date if this task repeats and it has a defer date.
# next due date (date or missing value, r/o) : The next due date if this task repeats and it has a due date.
# number of tasks (integer, r/o) : The number of direct children of this task.
# number of available tasks (integer, r/o) : The number of available direct children of this task.
# number of completed tasks (integer, r/o) : The number of completed direct children of this task.

# add_issues_to_of add github issue to omnifocus
def add_issues_to_of (ghclient, omnifocus, ofproject, ghproject, ghrepo)
	proj = omnifocus.flattened_tasks[ofproject]

	results = get_issues ghclient, ghproject, ghrepo
	if results.nil?
		puts "No results from GitHub"
		exit
	end

	results.each do |issue_id, issue|
		# do not record pull request
		next if issue["pull_request"] && !issue["pull_request"]["diff_url"].nil?
		url = "https://github.com/#{ghproject}/#{ghrepo}/issues/#{issue.number}"
		exists = proj.tasks.get.find { |t| t.note.get.force_encoding("UTF-8").include? url }
		next if exists

		# add task to omnifocus project
		proj.make(:new => :task, :with_properties => { 
			:name => "#{issue.number}: #{issue.title}", 
			:note => "#{url}\n\n#{issue["body"]}",
			:primary_tag => omnifocus.flattened_tags['ghissue']
		})

		puts "Created task #{issue.number}: #{issue.title}"
	end
end

def sync_issue_in_of (ghclient, omnifocus)
	create_tag_if_not_exists(omnifocus, "ghissue")
	tag = omnifocus.flattened_tags['ghissue']
	tag.tasks.get.find.each do |task|
		next if !task.note.get.match('github')
		
		repoFullname, number = task.note.get.match(/https:\/\/github.com\/(.*)?\/issues\/(.*)/i).captures
		issue = ghclient.issue(repoFullname, number)
		next if issue == nil

		task.name.set "#{issue.number}: #{issue["title"]}"
		if issue.state == 'closed' && task.completed.get != true
			task.mark_complete()
			puts "Marked task completed #{issue.number}"
		elsif issue.state != 'closed' && task.completed.get
			task.mark_incomplete()
			puts "Marked task incompleted #{issue.number}"
		end

		issue.labels.each do |label|
			if !task.tags.get.find { |t| t.name.get == label.name }
				puts "add tag " + label.name + " on omnifocus task #{issue.number}"
				create_tag_if_not_exists(omnifocus, label.name)
				tag = omnifocus.flattened_tags[label.name]
				omnifocus.add(tag, :to => task.tags)
			end
		end

		if task.flagged.get && issue.assignee.login.downcase != $opts[:username].downcase
			puts "task flagged unassigned me #{issue.number}"
			task.flagged.set false
		elsif !task.flagged.get && issue.assignee && issue.assignee.login.downcase == $opts[:username].downcase
			puts "task flagged to me #{issue.number}"
			task.flagged.set true
		end
	end
end

def create_tag_if_not_exists(omnifocus, tagname)
	tag = omnifocus.flattened_tags[tagname]
	if !omnifocus.exists(tag)
		puts "tag #{tagname} does not exist"
		omnifocus.make(:new => :tag, :with_properties => { :name => tagname })
		puts "tag #{tagname} created"
	end
end

def main ()
	if !`ps aux` =~ /OmniFocus/
		puts "OmniFocus is not running"
		exit
	end

	$opts = get_opts
	if $opts[:username] && $opts[:oauth]
		ghclient = Octokit::Client.new :access_token => $opts[:oauth]
		ghclient.user.login
	else
		puts "No username and oauth token combo found! Try --help for help."
		exit
	end

	omnifocus = Appscript.app.by_name("OmniFocus").default_document
	add_issues_to_of(ghclient, omnifocus, $opts[:omnifocus_project], $opts[:github_orga], $opts[:github_repo])
	sync_issue_in_of(ghclient, omnifocus)
end

main
