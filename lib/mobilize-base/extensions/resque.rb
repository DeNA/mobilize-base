module Mobilize
  module Resque
    def Resque.config
      Base.config('resque')[::Mobilize::Base.env]
    end

    def Resque.queue_name
      Resque.config['queue_name']
    end

    def Resque.queues
      Base.queues
    end

    def Resque.log_path
      Base.log_path("mobilize-resque-#{::Mobilize::Base.env}")
    end

    def Resque.workers(state="all")
      raise "invalid state #{state}" unless ['all','idle','working','timeout'].include?(state)
      workers = ::Resque.workers.select{|w| w.queues.first == Resque.queue_name}
      return workers if state == 'all'
      working_workers = workers.select{|w| w.job['queue']== Resque.queue_name}
      return working_workers if state == 'working'
      idle_workers = workers.select{|w| w.job['queue'].nil?}
      return idle_workers if state == 'idle'
      timeout_workers = workers.select{|w| w.job['payload'] and w.job['payload']['class']!='Jobtracker' and w.job['runat'] < (Time.now.utc - Jobtracker.max_run_time)}
      return timeout_workers if state == 'timeout'
    end

    def Resque.failures
      ::Resque::Failure.all(0,0).select{|f| f['queue'] == Resque.queue_name}
    end

    #active state refers to jobs that are either queued or working
    def Resque.jobs(state="active")
      raise "invalid state #{state}" unless ['all','queued','working','active','timeout','failed'].include?(state)
      working_jobs =  Resque.workers('working').map{|w| w.job['payload']}
      return working_jobs if state == 'working'
      queued_jobs = ::Resque.peek(Resque.queue_name,0,0).to_a
      return queued_jobs if state == 'queued'
      return working_jobs + queued_jobs if state == 'active'
      failed_jobs = Resque.failures.map{|f| f['payload']}
      return failed_jobs if state == 'failed'
      timeout_jobs = Resque.workers("timeout").map{|w| w.job['payload']}
      return tiomeout_jobs if state == 'timeout'
      return working_jobs + queued_jobs + failed_jobs if state == 'all'
    end

    def Resque.active_mongo_ids
      #first argument of the payload is the mongo id in Mongo unless the worker is Jobtracker
      Resque.jobs('active').map{|j| j['args'].first unless j['class']=='Jobtracker'}.compact
    end

    #Resque workers and methods to find
    def Resque.find_worker_by_mongo_id(mongo_id)
      Resque.workers('working').select{|w| w.job['payload']['args'][0] == mongo_id}.first
    end

    def Resque.update_job_status(mongo_id,msg)
      #this only works on working workers
      worker = Resque.find_worker_by_mongo_id(mongo_id)
      return false unless worker
      Resque.set_worker_args(worker,{"status"=>msg})
      #also fire a log, cap logfiles at 10 MB
      Logger.new(Resque.log_path, 10, 1024*1000*10).info("[#{worker} #{Time.now.utc}] status: #{msg}")
      return true
    end

    def Resque.update_job_email(mongo_id,email)
      #this only works on working workers
      worker = Resque.find_worker_by_mongo_id(mongo_id)
      return false unless worker
      Resque.set_worker_args(worker,{"email"=>email})
      #also fire a log, cap logfiles at 10 MB
      Logger.new(Resque.log_path, 10, 1024*1000*10).info("[#{worker} #{Time.now.utc}] email: #{email}")
    end

    def Resque.get_worker_args(worker)
      key = "worker:#{worker}"
      json = ::Resque.redis.get(key)
      if json
        hash = JSON.parse(json)
        payload_args = hash['payload']['args'].last
      end
    end

    #takes a worker and invokes redis to set the last value in its second arg array element
    #by our convention this is a Hash
    def Resque.set_worker_args(worker,args)
      key = "worker:#{worker}"
      json = ::Resque.redis.get(key)
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
        ::Resque.redis.set(key,hash.to_json)
        return true
      else
        return false
      end
    end

    def Resque.failure_report
      fjobs = {}
      excs = Hash.new(0)
      Resque.failures.each do |f|
        sname = f['payload']['class'] + ("=>" + f['payload']['args'].second['name'].to_s if f['payload']['args'].second).to_s
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

    def Resque.start_workers(count=1)
      count.times do
        "(cd #{Base.root};rake MOBILIZE_ENV=#{Base.env} mobilize:work) >> #{Resque.log_path} 2>&1 &".bash
      end
    end

    def Resque.kill_idle_workers(count=nil)
      idle_pids = Resque.workers('idle').select{|w| w.job=={}}.map{|w| w.to_s.split(":").second}
      if count>idle_pids.length or count == 0
        return false
      elsif count
        "kill #{idle_pids[0..count-1].join(" ")}".bash
      else
        "kill #{idle_pids.join(" ")}".bash
      end
      return true
    end

    def Resque.kill_workers(count=nil)
      pids = Resque.workers.map{|w| w.to_s.split(":").second}
      if count.to_i > pids.length or count == 0
        return false
      elsif count
        "kill #{pids[0..count-1].join(" ")}".bash(false)
      elsif pids.length>0
        "kill #{pids.join(" ")}".bash(false)
      else
        return false
      end
      return true
    end

    def Resque.prep_workers(max_workers=Resque.config['max_workers'])
      curr_workers = Resque.workers.length
      if curr_workers > max_workers
        #kill as many idlers as necessary
        Resque.kill_idle_workers(curr_workers - max_workers)
        #wait a few secs for these guys to die
        sleep 10
        curr_workers = Resque.workers.length
        if curr_workers > max_workers
          #kill working workers
          Resque.kill_workers(curr_workers - max_workers)
        end
      else
        Resque.start_workers(max_workers-curr_workers)
      end
      return true
    end
  end
end
