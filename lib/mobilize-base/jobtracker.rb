class Jobtracker
  #modify this to increase the frequency of request cycles
  def Jobtracker.cycle_freq
    10
  end

  #frequency of notifications
  def Jobtracker.notification_freq
    3600
  end

  #long running tolerance
  def Jobtracker.longrun_tolerance
    21600
  end

  def Jobtracker.admins
    YAML.load_file('config/mobilize/jobtracker.yml')['admins']
  end

  def Jobtracker.resqueued_job_ids
    return (Resque.queues.map{|q| Resque.peek(q,0,0).to_a}.compact + Resque.workers.map{|w| w.job['payload']}.compact).flatten.map{|j| j['args'].first}
  end

  def Jobtracker.working_jobs
    return Job.where(:status=>'working',:id=>{:$nin=>Jobtracker.resqueued_job_ids},:stages=>{:$ne=>[]}).to_a.select{|j| j.spec if j.spec_id}.compact
  end

  def Jobtracker.longrun_jobs
    return Jobtracker.working_jobs.select{|j| j.updated_at < Time.now.utc - Jobtracker.longrun_tolerance}
  end

  def Jobtracker.worker
    Jobtracker.worker_by_job_id("jobtracker")
  end

  #Resque workers and methods to find 
  def Jobtracker.worker_by_job_id(job_id)
    resque_job = Jobtracker.active_jobs.select{|job| job['payload']['args'][0] == job_id}.first
    if resque_job
      rhash = Resque.redis.get("worker:#{resque_job['worker']}").json_to_hash
      rhash['key'] = resque_job['worker']
      return rhash
    end
  end

  def Jobtracker.worker_args
    Resque.workers.map{|w| Resque.redis.get("worker:#{w.to_s}")}.compact.map{|s| s.json_to_hash['payload']['args']}
  end

  def Jobtracker.get_worker_args(worker)
    key = "worker:#{worker}"
    json = Resque.redis.get(key)
    if json
      hash = JSON.parse(json)
      payload_args = hash['payload']['args'].last
    end
  end
  
  #takes a worker and invokes redis to set the last value in its second arg array element
  #by our convention this is a Hash
  def Jobtracker.set_worker_args(worker,args)
    key = "worker:#{worker}"
    json = Resque.redis.get(key)
    if json
      hash = JSON.parse(json)
      payload_args = hash['payload']['args']
      #jobmaster only gets one arg
      if payload_args[1].nil?
        payload_args[1] = args
      else
        payload_args[1] = {} unless payload_args[1].class==Hash
        args.keys.each{|k,v| payload_args[1][k] = args[k]}
      end
      Resque.redis.set(key,hash.to_json)
      return true
    else
      return false
    end
  end


  def Jobtracker.status
    if Jobtracker.worker_by_job_id("jobtracker")
      return 'working'
    elsif Resque.peek("jobtracker",0,0).length>0
      return 'queued'
    else
      return 'stopped'
    end
  end

  def Jobtracker.restart
    Jobtracker.stop!
    Jobtracker.kill_idle_workers
    Jobtracker.start
  end

  def Jobtracker.send_message(message)
    Resque.redis.set(%{jobtracker_message},message)
    return true
  end

  def Jobtracker.check_message
    return Resque.redis.get(%{jobtracker_message})
  end

  def Jobtracker.start
    if Jobtracker.status!='stopped'
      raise "#{Jobtracker.to_s} still #{Jobtracker.status}"
    else
      Jobtracker.send_message('work')
      Jobtracker.queue
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
    Jobtracker.send_message('stop')
    sleep 5
    i=0
    while Jobtracker.status=='working'
      "#{Jobtracker.to_s} still on queue, waiting".opp
      sleep 5
      i+=1
    end
    return true
  end

  def Jobtracker.queue(queue_name="mobilize_jobtracker",model=Jobtracker,model_unique_id=queue_name, *args)
    Resque::Job.create(queue_name, model, model_unique_id,*args)
    return true
  end

  def Jobtracker.working_queues
    return Resque.workers.map{|w| w.job['queue']}.compact
  end

  def Jobtracker.last_notification
    return Resque.redis.get("last_notification")
  end

  def Jobtracker.last_notification=(time)
    Resque.redis.set("last_notification",time)
    return true
  end

  def Jobtracker.clear_all_queues
    Resque.queues.each{|q| Resque.remove_queue(q)}
    return true
  end

  def Jobtracker.notif_due?
    return (Jobtracker.last_notification.to_s.length==0 || Jobtracker.last_notification.to_datetime < (Time.now.utc - Jobtracker.notification_freq))
  end

  def Jobtracker.failures
    if Resque::Failure.all(0,-1).length>0
      Resque::Failure.all(0,-1)
    else
      Resque::Failure.all(0,0)
    end
  end

  def Jobtracker.job_fail_counts
    fjobs = {}
    excs = Hash.new(0)
    Jobtracker.failures.each do |f|
      sname = if f['payload']['args'].second
                f['payload']['args'].second['name']
              else
                f['payload']['args'].first
              end
      excs = f['error']
      if fjobs[sname].nil?
        fjobs[sname] = {excs => 1} 
      elsif fjobs[sname][excs].nil?
        fjobs[sname][excs] = 1
      else
        fjobs[sname][excs] += 1
      end
    end
    return fjobs
  end

  def Jobtracker.active_jobs
    Resque.workers.map{|w| w.job.merge('worker'=>w.to_s)}.reject{|j| j.keys.length==1 or j['payload']['class'].downcase=='jobtracker'}
  end

  def Jobtracker.worker_runtimes
    Jobtracker.active_jobs.map do |j|
      spec = j['payload']['args'].second['name']
      stg = j['queue']
      runat = j['run_at']
      {'spec'=>spec,'stg'=>stg,'runat'=>runat.gsub("/","-")}
    end
  end

  def Jobtracker.longrun_workers
    #return workers who have been cranking away for 6+ hours
    return Jobtracker.worker_runtimes.select{|wr| (Time.now.utc - Time.parse(wr['runat']))>Jobtracker.longrun_tolerance}
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
      lws = Jobtracker.longrun_workers
      if lws.length>0
        n = {}
        n['subj'] = "#{lws.length.to_s} longrun jobs"
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

  def Jobtracker.kill_idle_workers
    idle_pids = Resque.workers.select{|w| w.job=={}}.map{|w| w.to_s.split(":").second}.join(" ")
    begin
      "kill #{idle_pids}".bash
    rescue
    end
    "Killed idle workers".oputs
  end

  def Jobtracker.kill_workers(delay=0.minute)
    starttime=Time.now.utc
    while Resque.workers.select{|w| w.job['payload']}.length>0 and Time.now.utc<starttime+delay
      sleep 10.second
      "waited #{Time.now.utc-starttime} for workers to finish before kill".oputs
    end
    pids = Resque.workers.map{|w| w.worker_pids}.flatten.uniq.join(" ")
    begin
      "kill #{pids}".bash
    rescue
    end
    "Killed workers after #{Time.now.utc-starttime} seconds".oputs
  end

  def Jobtracker.perform(id,*args)
    #from resque
    while Jobtracker.check_message == 'work'
      Jobtracker.run_jobs
      pp "#{Jobtracker.to_s} status: #{Jobtracker.status} #{Time.now.utc.to_s}"
    end
    pp "Finished #{Jobtracker.to_s} #{Time.now.utc.to_s}"
    return true
  end

  def Jobtracker.get_requestors
    jobspecs = Gdriver.books.select{|b| b.title.starts_with?("Jobspec")}
    requestors = if Mobilize::Base.env == 'staging'
                    jobspecs.select{|s| s.title.ends_with?("_stg")}
                  elsif Mobilize::Base.env == 'development' or Mobilize::Base.env == 'pry_dev'
                    jobspecs.select{|s| s.title.ends_with?("_dev")}
                  elsif Mobilize::Base.env == 'production' or Mobilize::Base.env == 'integration'
                    jobspecs.reject{|s| s.title.split("_").length>2 and s.title[-4..-1] and s.title[-4..-1].starts_with?("_")}
                  else
                    raise "Invalid environment"
                  end.map{|s| s.title.split("_").second}
    return requestors.uniq.sort
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

  def Jobtracker.run_jobs
    #only happens once per deploy
    if 'mobilize'.rname.nil?
      r = Requestor.find_or_create_by_name('mobilize')
      r.run_jobs
    end
    rlastrun={}
    while Jobtracker.check_message != 'stop'
      #go to Googledrive and pull requestors from their jobspecs
      requestors = Jobtracker.get_requestors
      ["Processing requestors ",requestors.join(", ")].join.oputs
      requestors.each do |rname|
        if Jobtracker.check_message != 'stop'
          #maintenance operations take place between requestor polls
          Jobtracker.update_worker_status
          Jobtracker.run_notifications
          #run requestor jobs
          r = Requestor.find_or_create_by_name(rname)
          status_msg = %{Running #{rname}} + if rlastrun[rname]
                                               minago = ((Time.now.utc - rlastrun[rname])/60).to_i
                                               %{, last run #{minago.to_s} min ago}
                                             else
                                               %{, first run}
                                             end
          rlastrun[rname] = Time.now.utc
          #set status
          Jobtracker.set_worker_args(Jobtracker.worker.to_s,{"status"=>status_msg})
          r.run_jobs
          sleep Jobtracker.cycle_freq
        end
      end
    end
    "#{Jobtracker.to_s} told to stop".oputs
    return true
  end
end
