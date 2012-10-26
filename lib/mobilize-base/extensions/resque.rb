module Resque
  module Mobilize
    def Mobilize.config
      ::Mobilize::Base.config('resque')
    end

    def Mobilize.queues
      ::Mobilize::Base.queues
    end

    def Mobilize.all_model_ids
      return (Mobilize.queues.map{|q| Resque.peek(q,0,0).to_a}.compact + Resque.workers.map{|w| w.job['payload']}.compact).flatten.map{|j| j['args'].first}
    end

    def Mobilize.active_workers
      Resque.workers.map{|w| w.job.merge('worker'=>w.to_s)}.reject{|j| j.keys.length==1 or j['payload']['class'].downcase=='jobtracker'}
    end

    def Mobilize.max_timeout_jobs
      return Mobilize.active_workers.select{|w| w['runat'] < Time.now.utc - Jobtracker.max_run_time}
    end

    #Resque workers and methods to find 
    def Mobilize.worker_by_model_id(id)
      resque_job = Mobilize.active_workers.select{|w| w['payload']['args'][0] == id}.first
      if resque_job
        rhash = Resque.redis.get("worker:#{resque_job['worker']}").json_to_hash
        rhash['key'] = resque_job['worker']
        return rhash
      end
    end

    def Mobilize.log_path
      ::Mobilize::Base.log_path("mobilize-resque-#{::Mobilize::Base.env}")
    end

    def Mobilize.update_worker_status(worker,msg)
      Mobilize.set_worker_args(worker,{"status"=>msg})
      #also fire a log, cap logfiles at 10 MB
      Logger.new(Mobilize.log_path, 10, 1024*1000*10).info("[#{worker} #{Time.now.utc}] #{msg}")
    end

    def Mobilize.get_worker_args(worker)
      key = "worker:#{worker}"
      json = Resque.redis.get(key)
      if json
        hash = JSON.parse(json)
        payload_args = hash['payload']['args'].last
      end
    end

    #takes a worker and invokes redis to set the last value in its second arg array element
    #by our convention this is a Hash
    def Mobilize.set_worker_args(worker,args)
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

    def Mobilize.working_queues
      return Resque.workers.map{|w| w.job['queue']}.compact
    end

    def Mobilize.clear_queues
      Resque.queues.each{|q| Resque.remove_queue(q)}
      return true
    end

    def Mobilize.failures
      if Resque::Failure.all(0,-1).length>0
        Resque::Failure.all(0,-1)
      else
        Resque::Failure.all(0,0)
      end
    end

    def Mobilize.job_fail_counts
      fjobs = {}
      excs = Hash.new(0)
      Mobilize.failures.each do |f|
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

    def Mobilize.worker_runtimes
      Mobilize.active_workers.map do |j|
        spec = j['payload']['args'].second['name']
        stg = j['queue']
        runat = j['run_at']
        {'spec'=>spec,'stg'=>stg,'runat'=>runat.gsub("/","-")}
      end
    end

    def Mobilize.kill_idle_workers
      idle_pids = Resque.workers.select{|w| w.job=={}}.map{|w| w.to_s.split(":").second}.join(" ")
      begin
        "kill #{idle_pids}".bash
      rescue
      end
      "Killed idle workers".oputs
    end

    def Mobilize.kill_workers(delay=0.minute)
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

  end
end
