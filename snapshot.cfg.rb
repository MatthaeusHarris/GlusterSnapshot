#!/usr/bin/env ruby

class Settings
	def initialize
		@cloudservers = ["babycloud-0.rcg.montana.edu", "babycloud-1.rcg.montana.edu", "babycloud-2.rcg.montana.edu", "babycloud-3.rcg.montana.edu"]
		@masterserver = "babycloud-0.rcg.montana.edu"
		@backupto = "/mnt/backup"
		@backupfrom = "/mnt/snapshot"
	end

	attr_reader :cloudservers, :masterserver, :backupto, :backupfrom
end