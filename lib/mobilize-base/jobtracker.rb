class Jobtracker
  def Jobtracker.config
    Mobilize::Base.config('jobtracker')[Mobilize::Base.env]
  end

  #modify this to increase the frequency of request cycles
  def Jobtracker.cycle_freq
    Jobtracker.config['cycle_freq']
  end

  #frequency of notifications
  def Jobtracker.notification_freq
    Jobtracker.config['notification_freq']
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
    Resque::Mobilize.find_worker_by_mongo_id("jobtracker")
  end

  def Jobtracker.workers(state=nil)
    Resque::Mobilize.workers(state)
  end

  def Jobtracker.status
    args = Jobtracker.get_args
    return args['status'] if args
    return 'stopped'
  end

  def update_status(msg)
    #Jobtracker has no persistent database state
    Resque::Mobilize.update_worker_status(Jobtracker.worker,msg)
    return true
  end

  def Jobtracker.restart
    Jobtracker.stop!
    Jobtracker.start
  end

  def Jobtracker.set_args(args)
    Resque::Mobilize.set_worker_args(Jobtracker.worker,args)
    return true
  end

  def Jobtracker.get_args
    Resque::Mobilize.get_worker_args(Jobtracker.worker)
  end

  def Jobtracker.kill_workers
    Resque::Mobilize.kill_workers
  end

  def Jobtracker.kill_idle_workers
    Resque::Mobilize.kill_idle_workers
  end

  def Jobtracker.prep_workers
    Resque::Mobilize.prep_workers
  end

  def Jobtracker.failures
    Resque::Mobilize.failures
  end

  def Jobtracker.start
    if Jobtracker.status!='stopped'
      raise "Jobtracker still #{Jobtracker.status}"
    else
      #make sure that workers are running and at the right number
      Resque::Mobilize.prep_workers
      #queue up the jobtracker (starts the perform method)
      Jobtracker.enqueue!
    end
    return true
  end

  def Jobtracker.enqueue!
    Resque::Job.create(Resque::Mobilize.queue_name, Jobtracker, 'jobtracker',{'status'=>'working'})
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
      "#{Jobtracker.to_s} still on queue, waiting".opp
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
    return (Jobtracker.last_notification.to_s.length==0 || Jobtracker.last_notification.to_datetime < (Time.now.utc - Jobtracker.notification_freq))
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
    Resque::Mobilize.start_workers(count)
  end

  def Jobtracker.kill_workers(count=nil)
    Resque::Mobilize.kill_workers(count)
  end

  def Jobtracker.run_notifications
    if Jobtracker.notif_due?
      notifs = []
      if Jobtracker.failures.length>0
        n = {}
        jfcs = Resque::Mobilize.failure_report
        n['subj'] = "#{jfcs.keys.length.to_s} failed jobs, #{jfcs.values.map{|v| v.values}.flatten.sum.to_s} failures"
        #one row per exception type, with the job name
        n['body'] = jfcs.map{|k,v| v.map{|v,n| [k," : ",v,", ",n," times"].join}}.flatten.join("\n\n")
        notifs << n
      end
      lws = Jobtracker.max_run_time_workers
      if lws.length>0
        n = {}
        n['subj'] = "#{lws.length.to_s} max run time jobs"
        n['body'] = lws.map{|w| %{spec:#{w['spec']} stg:#{w['stg']} runat:#{w['runat'].to_s}}}.join("\n\n")
        notifs << n
      end
      notifs.each do |n|
        Emailer.write(n['subj'],n['body']).deliver
        Jobtracker.last_notification=Time.now.utc.to_s
        "Sent notification at #{Jobtracker.last_notification}".oputs
      end
    end
    return true
  end

  def Jobtracker.perform(id,*args)
    while Jobtracker.status == 'working'
      requestors = Requestor.all
      ["Processing requestors ",requestors.join(", ")].join.oputs
      Jobtracker.run_notifications
      requestors.each do |rname|
        last_due_time = Time.now.utc - Jobtracker.requestor_refresh_freq
        r.enqueue! if r.last_run < last_due_time
      end
    end
    "#{Jobtracker.to_s} told to stop".oputs
    return true
  end
end
