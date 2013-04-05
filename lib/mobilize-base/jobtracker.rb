module Mobilize
  module Jobtracker
    def Jobtracker.config
      Base.config('jobtracker')
    end

    #modify this to increase the frequency of request cycles
    def Jobtracker.cycle_freq
      Jobtracker.config['cycle_freq']
    end

    #frequency of notifications
    def Jobtracker.notification_freq
      Jobtracker.config['notification_freq']
    end

    def Jobtracker.runner_read_freq
      Jobtracker.config['runner_read_freq']
    end

    #long running tolerance
    def Jobtracker.max_run_time
      Jobtracker.config['max_run_time']
    end

    def Jobtracker.admins
      Jobtracker.config['admins']
    end

    def Jobtracker.admin_emails
      Jobtracker.admins.map{|a| a['email'] }
    end

    def Jobtracker.worker
      Resque.find_worker_by_path("jobtracker")
    end

    def Jobtracker.workers(state="all")
      Resque.workers(state)
    end

    def Jobtracker.status
      args = Jobtracker.get_args
      return args['status'] if args
      job = Resque.jobs.select{|j| j['args'].first=='jobtracker'}.first
      return 'queued' if job
      return 'stopped'
    end

    def Jobtracker.update_status(msg)
      #Jobtracker has no persistent database state
      Resque.set_worker_args_by_path("jobtracker",{'status'=>msg})
      return true
    end

    def Jobtracker.restart
      Jobtracker.stop!
      Jobtracker.start
    end

    def Jobtracker.set_args(args)
      Resque.set_worker_args(Jobtracker.worker,args)
      return true
    end

    def Jobtracker.get_args
      Resque.get_worker_args(Jobtracker.worker)
    end

    def Jobtracker.kill_workers
      Resque.kill_workers
    end

    def Jobtracker.kill_idle_workers
      Resque.kill_idle_workers
    end

    def Jobtracker.kill_idle_and_stale_workers
      Resque.kill_idle_and_stale_workers
    end

    def Jobtracker.prep_workers
      Resque.prep_workers
    end

    def Jobtracker.failures
      Resque.failures
    end

    def Jobtracker.start
      if Jobtracker.status!='stopped'
        Jobtracker.update_status("Jobtracker still #{Jobtracker.status}")
      else
        #make sure that workers are running and at the right number
        #Resque.prep_workers
        #queue up the jobtracker (starts the perform method)
        Jobtracker.enqueue!
      end
      return true
    end

    def Jobtracker.enqueue!
      ::Resque::Job.create(Resque.queue_name, Jobtracker, 'jobtracker',{})
    end

    def Jobtracker.restart!
      Jobtracker.stop!
      Jobtracker.start
      return true
    end

    def Jobtracker.restart_workers!
      Jobtracker.kill_workers
      sleep 10
      Jobtracker.prep_workers
      Jobtracker.update_status("put workers back on the queue")
    end

    def Jobtracker.stop!
      #send signal for Jobtracker to check for
      Jobtracker.update_status('stopping')
      sleep 5
      i=0
      while Jobtracker.status=='stopping'
        Jobtracker.update_status("#{Jobtracker.to_s} still on queue, waiting")
        sleep 5
        i+=1
      end
      return true
    end

    def Jobtracker.last_notification
      return Jobtracker.get_args["last_notification"] if Jobtracker.get_args
    end

    def Jobtracker.last_notification=(time)
      Jobtracker.set_args({"last_notification"=>time})
    end

    def Jobtracker.notif_due?
      last_duetime = Time.now.utc - Jobtracker.notification_freq
      return (Jobtracker.last_notification.to_s.length==0 || Jobtracker.last_notification.to_datetime < last_duetime)
    end

    def Jobtracker.max_run_time_workers
      #return workers who have been cranking away for 6+ hours
        workers = Jobtracker.workers('working').select do |w|
            w.job['runat'].to_s.length>0 and 
              (Time.now.utc - Time.parse(w.job['runat'])) > Jobtracker.max_run_time
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
            runner_dst = Dataset.find_by_url("gsheet://#{u.runner.path}")
            n['body'] += "\n\n#{runner_dst.http_url}" if runner_dst and runner_dst.http_url
            n['to'] = email
            n['bcc'] = Jobtracker.admin_emails.join(",")
            notifs << n
          end
        end
        lws = Jobtracker.max_run_time_workers
        if lws.length>0
          n = {}
          n['subject'] = "#{lws.length.to_s} max run time jobs"
          n['body'] = lws.map{|w| %{spec:#{w['spec']} stg:#{w['stg']} runat:#{w['runat'].to_s}}}.join("\n\n")
          n['to'] = Jobtracker.admin_emails.join(",")
          notifs << n
        end
        #deliver each email generated
        notifs.each do |notif|
          Email.write(notif).deliver
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

    #test methods
    def Jobtracker.restart_test_redis
      Jobtracker.stop_test_redis
      if !system("which redis-server")
        raise "** can't find `redis-server` in your path, you need redis to run Resque and Mobilize"
      end
      "redis-server #{Base.root}/test/redis-test.conf".bash
    end

    def Jobtracker.stop_test_redis
      processes = `ps -A -o pid,command | grep [r]edis-test`.split($/)
      pids = processes.map { |process| process.split(" ")[0] }
      puts "Killing test redis server..."
      pids.each { |pid| Process.kill("TERM", pid.to_i) }
      puts "removing redis db dump file"
      sleep 5
      `rm -f #{Base.root}/test/dump.rdb #{Base.root}/test/dump-cluster.rdb`
    end

    def Jobtracker.set_test_env
      ENV['MOBILIZE_ENV']='test'
      ::Resque.redis="localhost:9736"
      mongoid_config_path = "#{Base.root}/config/mobilize/mongoid.yml"
      Mongoid.load!(mongoid_config_path, Base.env)
    end

    def Jobtracker.drop_test_db
      Jobtracker.set_test_env
      Mongoid.session(:default).collections.each do |collection| 
        unless collection.name =~ /^system\./
          collection.drop
        end
      end
    end

    def Jobtracker.build_test_runner(user_name)
      Jobtracker.set_test_env
      u = User.where(:name=>user_name).first
      Jobtracker.update_status("delete old books and datasets")
      # delete any old runner from previous test runs
      gdrive_slot = Gdrive.owner_email
      u.runner.gsheet(gdrive_slot).spreadsheet.delete
      Dataset.find_by_handler_and_path('gbook',u.runner.title).delete
      Jobtracker.update_status("enqueue jobtracker, wait 45s")
      Mobilize::Jobtracker.start
      sleep 45
    end
  end
end
