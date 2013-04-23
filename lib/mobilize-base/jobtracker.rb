module Mobilize
  module Jobtracker
    #adds convenience methods
    require "#{File.dirname(__FILE__)}/helpers/jobtracker_helper"

    def Jobtracker.max_run_time_workers
      #return workers who have been cranking away for 6+ hours
        workers = Jobtracker.workers('working').select do |w|
            w.job['run_at'].to_s.length>0 and 
              (Time.now.utc - Time.parse(w.job['run_at'])) > Jobtracker.max_run_time
        end
        return workers
    end

    def Jobtracker.start_worker(count=nil)
      Resque.start_workers(count)
    end

    def Jobtracker.kill_workers(count=nil)
      Resque.kill_workers(count)
    end

    def Jobtracker.run_notifications
      if Jobtracker.notif_due?
        notifs = []
        if Jobtracker.failures.length>0
          failure_hash = Resque.new_failures_by_email
          failure_hash.each do |email,stage_paths|
            n = {}
            n['subject'] = "#{stage_paths.keys.length.to_s} new failed jobs, #{stage_paths.values.map{|v| v.values}.flatten.sum.to_s} failures"
            #one row per exception type, with the job name
            n['body'] = stage_paths.map do |path,exceptions| 
                                          exceptions.map do |exc_to_s,times| 
                                            [path," : ",exc_to_s,", ",times," times"].join
                                          end
                                        end.flatten.join("\n\n")
            u = User.where(:name=>email.split("@").first).first
            if u
              runner_dst = Dataset.find_by_url("gsheet://#{u.runner.path}")
              n['body'] += "\n\n#{runner_dst.http_url}" if runner_dst and runner_dst.http_url
            end
            n['to'] = email
            n['bcc'] = [Gdrive.admin_group_name,Gdrive.domain].join("@")
            notifs << n
          end
        end
        lws = Jobtracker.max_run_time_workers
        if lws.length>0
          bod = begin
                  lws.map{|w| w.job['payload']['args']}.first.join("\n")
                rescue
                  "Failed to get job names"
                end
          n = {}
          n['subject'] = "#{lws.length.to_s} max run time jobs"
          n['body'] = bod
          n['to'] = [Gdrive.admin_group_name,Gdrive.domain].join("@")
          notifs << n
        end
        #deliver each email generated
        notifs.each do |notif|
          begin
            Email.write(notif).deliver
          rescue
            #log email on failure
            Jobtracker.update_status("Failed to deliver #{notif.to_s}")
          end
        end
        #update notification time so JT knows to wait a while
        Jobtracker.last_notification = Time.now.utc.to_s
        Jobtracker.update_status("Sent notification at #{Jobtracker.last_notification}")
      end
      return true
    end

    def Jobtracker.perform(id,*args)
      while Jobtracker.status != 'stopping'
        users = User.all
        Jobtracker.run_notifications
        #run throush all users randomly
        #so none are privileged on JT restarts
        users.sort_by{rand}.each do |u|
          r = u.runner
          Jobtracker.update_status("Checking #{r.path}")
          if r.is_due?
            r.enqueue!
            Jobtracker.update_status("Enqueued #{r.path}")
          end
        end
        sleep 5
      end
      Jobtracker.update_status("told to stop")
      return true
    end

    def Jobtracker.deployed_at
      #assumes deploy is as of last commit, or as of last deploy time
      #as given by the REVISION file in the root folder
      deploy_time = begin
                      %{git log -1 --format="%cd"}.bash
                    rescue
                      revision_path = "#{ENV['PWD']}/REVISION"
                      "touch #{revision_path}".bash unless File.exists?(revision_path)
                      revision_string = "ls -l #{revision_path}".bash
                      revision_rows = revision_string.split("\n").map{|lss| lss.strip.split(" ")}
                      mod_time = revision_rows.map do |lsr| 
                        if lsr.length == 8
                          #ubuntu
                          lsr[5..6].join(" ")
                        elsif lsr.length == 9
                          #osx
                          lsr[5..7].join(" ")
                        end
                      end.first
                      mod_time
                    end.to_s.strip
      Time.parse(deploy_time)
    end
  end
end
