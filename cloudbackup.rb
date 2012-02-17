#!/usr/bin/env ruby


# To be run on the backup spooler
# 
# 1.  Cull the old snapshots
# 2.  Rotate the current snapshot to a named snapshot
# 3.  Mount the snapshot volume on each server.
# 4.  On the first server, create the gluster snapshot volume
# 5.  Mount the gluster snapshot volume on the backup spooler
# 6.  Rsync from the gluster snapshot to the current snapshot
# 7.  Unmount the gluster snapshot volume from the backup spooler
# 8.  Remove the gluster snapshot volume
# 9.  On each server, remove the lvm2 snapshot volume
# 10.  Report great success!


require "rubygems"
require "net/ssh"
require "pp"
require "highline/import"

cloudservers = ["cloud0.rcg.montana.edu", "cloud1.rcg.montana.edu"]
masterserver = "cloud0.rcg.montana.edu"
backupto = "/mnt/backup"
backupfrom = "/mnt/snapshot"


class RemoteHost
  def initialize(url, user = "matt")
    @host = url
    @user = user
    @shell = Net::SSH.start(url, user)
    @history = String.new
  end
  
  def exec(command)
    realcommand = command + "; echo $?"
    ret = @shell.exec!(realcommand)
    @history += "#{@user}@#{@host} # #{realcommand}\n#{ret}\n"
    (ret =~ /^0$/) != nil
  end
  
  def truetest
    exec("/bin/true")
  end
  
  def falsetest 
    exec("/bin/false")
  end
  
  def history
    @history
  end
end

class Cloud
  def initialize(servers, master)
    @servers = Hash.new()
    servers.each { |server| @servers.[]= server, RemoteHost.new(server) }
    @master = master
  end
  
  def servers
    @servers
  end
  
  def attempt(command, targets = :all)
    sessions = case targets
    when :all		then 	Array.new(@servers.keys)
    when :master	then 	[ @master ]
    end
    success = true
    sessions.each do |session| 
      STDERR.puts "Running #{command} on #{session}"
      retval = @servers[session].exec(command)
#       pp retval
      if !retval
	success = false;
	STDERR.puts "There was a failure on #{session}.  A history dump follows:"
	STDERR.puts @servers[session].history
      end
    end
    success
  end
  
  def debug
    @servers.each { |host,server| STDERR.puts server.history }
  end
end

class BackupManager
  def initialize(cloudservers, masterserver)
    @cloud = Cloud.new(cloudservers, masterserver)
  end
  
  def runbackup
    if @cloud.attempt("sudo lvcreate -l 100%FREE -s -n backup /dev/store/live")
      if @cloud.attempt("sudo mount /dev/store/backup /mnt/snapshot")
	cmd = "sudo gluster volume create backup replica 2"
	@cloud.servers.each { |host, connection| cmd += " #{host}:/mnt/snapshot" }
	if @cloud.attempt(cmd, :master)
	  if @cloud.attempt("sudo gluster volume start backup", :master)
# 	    STDERR.puts <<-EOF
# 	
#     //=================================================================================\\\\
#     ||Great success!  If you're seeing this, we're almost ready to start doing backups!||
#     \\\\=================================================================================//
# 
#     EOF
	yield
	STDERR.puts "Assuming backups are done, cleaning up now."
	  else
	    abort "Something went wrong with starting the gluster volume.  You should probably investigate."
	  end
	  if @cloud.attempt("yes | sudo gluster volume stop backup", :master)
	  else
	    abort "Something went wrong with stopping the gluster volume.  You should probably investigate."
	  end
	else
	end
	if @cloud.attempt("yes | sudo gluster volume delete backup", :master)
	else
	  abort "Was not able to properly undo the gluster stuff.  You should probably investigate."
	end
      else
	#Recovery code would go here, but cleanup code is the same.
      end
	@cloud.attempt("sudo umount -f /dev/store/backup")
    else
      #recovery code would go here, but it turns out that the cleanup code is the same as the recovery code.
    end
    @cloud.attempt("sudo lvremove -f /dev/store/backup",:all);
  end
end

BackupManager.new(cloudservers, masterserver).runbackup do 
#  abort "Test away, sir."
  STDERR.puts "Waiting to make sure the NFS mount is available..."
  sleep 5
  STDERR.puts "Starting the actual backup!" 
  system("mount -t nfs #{masterserver}:/backup #{backupfrom}")
  system("rsync -a --delete --progress #{backupfrom}/* #{backupto}") or abort("Something went wrong with the backup.  Dying immediately so you can test.")
  system("umount #{backupfrom}")
  STDERR.puts "Backup complete!"
end