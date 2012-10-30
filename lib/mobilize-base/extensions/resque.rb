module Resque
  module Mobilize
    def Mobilize.config
      ::Mobilize::Base.config('resque')[::Mobilize::Base.env]
    end

    def Mobilize.queue_name
      Resque::Mobilize.config['queue_name']
    end

    def Mobilize.queues
      ::Mobilize::Base.queues
    end

    def Mobilize.log_path
      ::Mobilize::Base.log_path("mobilize-resque-#{::Mobilize::Base.env}")
    end

    def Mobilize.admins
      Resque::Mobilize.config['admins']
    end

    def Mobilize.workers(state="all")
      raise "invalid state #{state}" unless ['all','idle','working','timeout'].include?(state)
      workers = Resque.workers.select{|w| w.queues.first == Resque::Mobilize.queue_name}
      return workers if state == 'all'
      working_workers = workers.select{|w| w.job['queue']== Resque::Mobilize.queue_name}
      return working_workers if state == 'working'
      idle_workers = workers.select{|w| w.job['queue'].nil?}
      return idle_workers if state == 'idle'
      timeout_workers = workers.select{|w| w.job['payload'] and w.job['payload']['class']!='Jobtracker' and w.job['runat'] < (Time.now.utc - Jobtracker.max_run_time)}
      return timeout_workers if state == 'timeout'
    end

    def Mobilize.failures
      Resque::Failure.all(0,0).select{|f| f['queue'] == Resque::Mobilize.queue_name}
    end

    #active state refers to jobs that are either queued or working
    def Mobilize.jobs(state="active")
      raise "invalid state #{state}" unless ['all','queued','working','active','timeout','failed'].include?(state)
      working_jobs =  Resque::Mobilize.workers('working').map{|w| w.job['payload']}
      return working_jobs if state == 'working'
      queued_jobs = Resque.peek(Resque::Mobilize.queue_name,0,0).to_a
      return queued_jobs if state == 'queued'
      return working_jobs + queued_jobs if state == 'active'
      failed_jobs = Resque::Mobilize.failures.map{|f| f['payload']}
      return failed_jobs if state == 'failed'
      timeout_jobs = Resque::Mobilize.workers("timeout").map{|w| w.job['payload']}
      return tiomeout_jobs if state == 'timeout'
      return working_jobs + queued_jobs + failed_jobs if state == 'all'
    end

    def Mobilize.active_mongo_ids
      #first argument of the payload is the mongo id in Mongo unless the worker is Jobtracker
      Resque::Mobilize.jobs('active').map{|j| j['args'].first unless j['class']=='Jobtracker'}.compact
    end

    #Resque workers and methods to find
    def Mobilize.find_worker_by_mongo_id(mongo_id)
      Resque::Mobilize.workers('working').select{|w| w.job['payload']['args'][0] == mongo_id}.first
    end

    def Mobilize.update_job_status(mongo_id,msg)
      #this only works on working workers
      worker = Resque::Mobilize.find_worker_by_mongo_id(mongo_id)
      return false unless worker
      Resque::Mobilize.set_worker_args(worker,{"status"=>msg})
      #also fire a log, cap logfiles at 10 MB
      Logger.new(Resque::Mobilize.log_path, 10, 1024*1000*10).info("[#{worker} #{Time.now.utc}] status: #{msg}")
      return true
    end

    def Mobilize.update_job_email(mongo_id,email)
      #this only works on working workers
      worker = Resque::Mobilize.find_worker_by_mongo_id(mongo_id)
      return false unless worker
      Resque::Mobilize.set_worker_args(worker,{"email"=>email})
      #also fire a log, cap logfiles at 10 MB
      Logger.new(Resque::Mobilize.log_path, 10, 1024*1000*10).info("[#{worker} #{Time.now.utc}] email: #{email}")
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

    def Mobilize.failure_report
      fjobs = {}
      excs = Hash.new(0)
      Resque::Mobilize.failures.each do |f|
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

    def Mobilize.start_workers(count=1)
      count.times do
        "(cd #{::Mobilize::Base.root};/usr/bin/rake mobilize:work) >> #{Resque::Mobilize.log_path} 2>&1 &".bash
      end
    end

    def Mobilize.kill_idle_workers(count=nil)
      idle_pids = Resque::Mobilize.workers('idle').select{|w| w.job=={}}.map{|w| w.to_s.split(":").second}
      if count>idle_pids.length or count == 0
        return false
      elsif count
        "kill #{idle_pids[0..count-1].join(" ")}".bash
      else
        "kill #{idle_pids.join(" ")}".bash
      end
      return true
    end

    def Mobilize.kill_workers(count=nil)
      pids = Resque::Mobilize.workers.map{|w| w.to_s.split(":").second}
      if count.to_i > pids.length or count == 0
        return false
      elsif count
        "kill #{pids[0..count-1].join(" ")}".bash
      elsif pids.length>0
        "kill #{pids.join(" ")}".bash
      else
        return false
      end
      return true
    end

    def Mobilize.prep_workers(max_workers=Resque::Mobilize.config['max_workers'])
      curr_workers = Resque::Mobilize.workers.length
      if curr_workers > max_workers
        #kill as many idlers as necessary
        Resque::Mobilize.kill_idle_workers(curr_workers - max_workers)
        #wait a few secs for these guys to die
        sleep 10
        curr_workers = Resque::Mobilize.workers.length
        if curr_workers > max_workers
          #kill working workers
          Resque::Mobilize.kill_workers(curr_workers - max_workers)
        end
      else
        Resque::Mobilize.start_workers(max_workers-curr_workers)
      end
      return true
    end
  end
end
