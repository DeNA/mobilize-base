class Jobtracker
  def Jobtracker.config
    Mobilize::Base.config('jobtracker')
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

  def Jobtracker.worker
    Resque::Mobilize.worker_by_model_id("jobtracker")
  end

  def Jobtracker.status
    args = Jobtracker.get_args(Jobtracker.worker)
    return args['status'] if args
    return 'stopped'
  end

  def Jobtracker.restart
    Jobtracker.stop!
    Jobtracker.start
  end

  def Jobtracker.set_args(args)
    Resque::Mobilize.set_args_by_worker(Jobtracker.worker,args)
    return true
  end

  def Jobtracker.get_args(args)
    Resque::Mobilize.get_args_by_worker(Jobtracker.worker)
    return true
  end

  def Jobtracker.start
    if Jobtracker.status!='stopped'
      raise "#{Jobtracker.to_s} still #{Jobtracker.status}"
    else
      #make sure that workers are running
      #make sure user has entered password
      Jobtracker.set_args({'status'=>'working'})
      Resque::Job.create('mobilize_jobtracker', Jobtracker, 'jobtracker',{})
    end
    return true
  end

  def Jobtracker.restart!
    Jobtracker.stop!
    Jobtracker.start
    return true
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
    return Jobtracker.get_args("last_notification")
  end

  def Jobtracker.last_notification=(time)
    Jobtracker.set_args("last_notification",time)
  end

  def Jobtracker.notif_due?
    return (Jobtracker.last_notification.to_s.length==0 || Jobtracker.last_notification.to_datetime < (Time.now.utc - Jobtracker.notification_freq))
  end

  def Jobtracker.max_timeout_workers
    #return workers who have been cranking away for 6+ hours
    return Jobtracker.worker_runtimes.select{|wr| (Time.now.utc - Time.parse(wr['runat']))>Jobtracker.max_run_time}
  end

  def Jobtracker.start_workers
    "/usr/bin/rake mobilize:work &"
  end

  def Jobtracker.run_notifications
    if Jobtracker.notif_due?
      notifs = []
      jfcs = Jobtracker.job_fail_counts
      if jfcs.keys.length>0
        n = {}
        n['subj'] = "#{jfcs.keys.length.to_s} failed jobs, #{jfcs.values.map{|v| v.values}.flatten.sum.to_s} failures"
        #one row per exception type, with the job name
        n['body'] = jfcs.map{|k,v| v.map{|v,n| [k," : ",v,", ",n," times"].join}}.flatten.join("\n\n")
        notifs << n
      end
      lws = Jobtracker.max_timeout_workers
      if lws.length>0
        n = {}
        n['subj'] = "#{lws.length.to_s} max timeout jobs"
        n['body'] = lws.map{|w| %{spec:#{w['spec']} stg:#{w['stg']} runat:#{w['runat'].to_s}}}.join("\n\n")
        notifs << n
      end
      notifs.each do |n|
        Notice.alert(n['subj'],n['body'],Jobtracker.admins.join(",")).deliver
        Jobtracker.last_notification=Time.now.utc.to_s
        "Sent notification at #{Jobtracker.last_notification}".oputs
      end
    end
    return true
  end

  def Jobtracker.get_requestors
  end

  def Jobtracker.update_worker_status
    Jobtracker.active_jobs.each do |aj|
      j = aj['payload']['args'][0].j
      #set status and name
      Jobtracker.set_worker_args(aj['worker'],
                                 {"status"=>j.status,
                                  "task"=>j.active_task,
                                  "name"=>"#{j.requestor.name}/#{j.name}"})
    end
  end

  def Jobtracker.perform(id,*args)
    rlastrun={}
    while Jobtracker.status == 'working'
      requestors = Jobtracker.get_requestors
      ["Processing requestors ",requestors.join(", ")].join.oputs
      Jobtracker.run_notifications
      requestors.each do |rname|
        #run requestor jobs
        r = Requestor.find_or_create_by_name(rname)
        rlastrun[rname] = Time.now.utc
        #set status
        Jobtracker.set_worker_args(Jobtracker.worker.to_s,{"status"=>status_msg})
        r.run_jobs
        sleep Jobtracker.cycle_freq
      end
    end
    "#{Jobtracker.to_s} told to stop".oputs
    return true
  end
end
