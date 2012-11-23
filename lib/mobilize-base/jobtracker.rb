module Mobilize
  module Jobtracker
    def Jobtracker.config
      Base.config('jobtracker')[Base.env]
    end

    #modify this to increase the frequency of request cycles
    def Jobtracker.cycle_freq
      Jobtracker.config['cycle_freq']
    end

    #frequency of notifications
    def Jobtracker.notification_freq
      Jobtracker.config['notification_freq']
    end

    def Jobtracker.requestor_refresh_freq
      Jobtracker.config['requestor_refresh_freq']
    end

    #long running tolerance
    def Jobtracker.max_run_time
      Jobtracker.config['max_run_time']
    end

    def Jobtracker.admins
      Jobtracker.config['admins']
    end

    def Jobtracker.admin_emails
      Jobtracker.admins.map{|a| a['email']}
    end

    def Jobtracker.worker
      Resque.find_worker_by_mongo_id("jobtracker")
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
      Resque.update_job_status("jobtracker",msg)
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

    def Jobtracker.prep_workers
      Resque.prep_workers
    end

    def Jobtracker.failures
      Resque.failures
    end

    def Jobtracker.start
      if Jobtracker.status!='stopped'
        raise "Jobtracker still #{Jobtracker.status}"
      else
        #make sure that workers are running and at the right number
        #Resque.prep_workers
        #queue up the jobtracker (starts the perform method)
        Jobtracker.enqueue!
      end
      return true
    end

    def Jobtracker.enqueue!
      ::Resque::Job.create(Resque.queue_name, Jobtracker, 'jobtracker',{'status'=>'working'})
    end

    def Jobtracker.restart!
      Jobtracker.stop!
      Jobtracker.start
      return true
    end

    def Jobtracker.restart_workers!
      Jobtracker.kill_workers
      sleep 5
      Jobtracker.prep_workers
    end

    def Jobtracker.stop!
      #send signal for Jobtracker to check for
      Jobtracker.update_status('stopping')
      sleep 5
      i=0
      while Jobtracker.status=='stopping'
        puts "#{Jobtracker.to_s} still on queue, waiting"
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

    def Jobtracker.set_test_env
      ENV['MOBILIZE_ENV']='test'
      ::Resque.redis="localhost:9736"
      mongoid_config_path = "#{Mobilize::Base.root}/config/mongoid.yml"
      Mongoid.load!(mongoid_config_path, Mobilize::Base.env)
    end

    def Jobtracker.run_notifications
      if Jobtracker.notif_due?
        notifs = []
        if Jobtracker.failures.length>0
          n = {}
          jfcs = Resque.failure_report
          n['subj'] = "#{jfcs.keys.length.to_s} failed jobs, #{jfcs.values.map{|v| v.values}.flatten.sum.to_s} failures"
          #one row per exception type, with the job name
          n['body'] = jfcs.map{|key,val| val.map{|b,name| [key," : ",b,", ",name," times"].join}}.flatten.join("\n\n")
          notifs << n
        end
        lws = Jobtracker.max_run_time_workers
        if lws.length>0
          n = {}
          n['subj'] = "#{lws.length.to_s} max run time jobs"
          n['body'] = lws.map{|w| %{spec:#{w['spec']} stg:#{w['stg']} runat:#{w['runat'].to_s}}}.join("\n\n")
          notifs << n
        end
        notifs.each do |notif|
          Emailer.write(n['subj'],notif['body']).deliver
          Jobtracker.last_notification=Time.now.utc.to_s
          "Sent notification at #{Jobtracker.last_notification}".oputs
        end
      end
      return true
    end

    def Jobtracker.perform(id,*args)
      while Jobtracker.status != 'stopping'
        requestors = Requestor.all
        Jobtracker.run_notifications
        requestors.each do |r|
          Jobtracker.update_status("Running requestor #{r.name}")
          if r.is_due?
            r.enqueue!
            Jobtracker.update_status("Enqueued requestor #{r.name}")
          end
        end
        sleep 5
      end
      Jobtracker.update_status("told to stop")
      return true
    end

    def Jobtracker.create_test_job
      #set test environment
      Jobtracker.set_test_env

      email = Mobilize::Gdriver.owner_email

      #kill all workers
      Mobilize::Jobtracker.kill_workers

      puts 'enqueue 4 workers on Resque, wait 20s'
      Mobilize::Jobtracker.prep_workers
      sleep 20
      raise "workers not queued" unless Mobilize::Jobtracker.workers.length == Mobilize::Resque.config['max_workers'].to_i

      #make sure old one is deleted
      Mobilize::Requestor.find_or_create_by_email(email).delete

      puts "create requestor from owner"
      requestor = Mobilize::Requestor.find_or_create_by_email(email)
      raise "requestor not created" unless requestor.email == email

      puts "delete old test books and datasets"
      # delete any old specbooks from previous test runs
      jobspec_title = requestor.jobspec_title
      books = Mobilize::Gbooker.find_all_by_title(jobspec_title)
      books.each{|book| book.delete}
      #delete old datasets for this specbook
      Mobilize::Dataset.all.select{|d| d.name.starts_with?(jobspec_title)}.each{|d| d.delete}

      puts "enqueue jobtracker, wait 60s for it to create Jobspec with Jobs sheet"
      Mobilize::Jobtracker.start
      sleep 60
      puts "jobtracker status: #{Mobilize::Jobtracker.status}" 
      puts "status:#{Mobilize::Jobtracker.status}" #!= 'stopped'

      books = Mobilize::Gbooker.find_all_by_title(jobspec_title)
      raise "book not created" unless books.length == 1

      jobs_sheets = Mobilize::Gsheeter.find_all_by_name("#{jobspec_title}/Jobs",email)
      raise "Jobs sheet not created" unless jobs_sheets.length == 1

      puts "add test_source data"

      test_source_rows = [
        ["test_header","test_header2","test_header3"],
        ["t1"]*3,
        ["t2"]*3
      ]

      test_source_sheet = Mobilize::Gsheeter.find_or_create_by_name("#{jobspec_title}/test_source",email)

      test_source_tsv = test_source_rows.map{|r| r.join("\t")}.join("\n")
      test_source_sheet.write(test_source_tsv)

      #delete existing Jobs from the db
      Mobilize::Job.each{|j| j.delete}

      jobs_sheet = jobs_sheets.first

      test_job_row =    {"name" => "test",
                       "active" => "true",
                     "schedule" => "every 0.hour",
                       "status" => "",
                   "last_error" => "",
              "destination_url" => "",
                 "read_handler" => "gsheeter",
                "write_handler" => "gsheeter",
                 "param_source" => "test_source",
                       "params" => "",
                  "destination" => "test_destination"}

      #update second row w details
      test_job_row.values.each_with_index do |v,v_i|
        jobs_sheet[2,v_i+1] = v
      end

      jobs_sheet.save

      puts "job row added to Jobs sheet, enqueueing requestor to process job on resque."
      requestor.enqueue!
      puts "check progress on Resque UI or log file"
      return true
    end
  end
end
