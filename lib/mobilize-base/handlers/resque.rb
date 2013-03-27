module Mobilize
  module Resque
    def Resque.config
      Base.config('resque')
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
      workers = ::Resque.workers.select{|w| w.queues.first == Resque.queue_name}
      return workers if state == 'all'
      working_workers = workers.select{|w| w.job['queue']== Resque.queue_name}
      return working_workers if state == 'working'
      idle_workers = workers.select{|w| w.job['queue'].nil?}
      return idle_workers if state == 'idle'
      stale_workers = workers.select{|w| Time.parse(w.started) < Jobtracker.deployed_at}
      return stale_workers if state == 'stale'
      timeout_workers = workers.select{|w| w.job['payload'] and w.job['payload']['class']!='Jobtracker' and w.job['runat'] < (Time.now.utc - Jobtracker.max_run_time)}
      return timeout_workers if state == 'timeout'
      raise "invalid state #{state}"
    end

    def Resque.failures
      ::Resque::Failure.all(0,0).select{|f| f['queue'] == Resque.queue_name}
    end

    #active state refers to jobs that are either queued or working
    def Resque.jobs(state="active")
      working_jobs =  Resque.workers('working').map{|w| w.job['payload']}
      return working_jobs if state == 'working'
      queued_jobs = ::Resque.peek(Resque.queue_name,0,0).to_a
      return queued_jobs if state == 'queued'
      return working_jobs + queued_jobs if state == 'active'
      failed_jobs = Resque.failures.map{|f| f['payload']}
      return failed_jobs if state == 'failed'
      timeout_jobs = Resque.workers("timeout").map{|w| w.job['payload']}
      return timeout_jobs if state == 'timeout'
      return working_jobs + queued_jobs + failed_jobs if state == 'all'
      raise "invalid state #{state}"
    end

    def Resque.active_paths
      #first argument of the payload is the runner / stage path unless the worker is Jobtracker
      Resque.jobs('active').compact.map{|j| j['args'].first unless j['class']=='Jobtracker'}.compact
    end

    #Resque workers and methods to find
    def Resque.find_worker_by_path(path)
      Resque.workers('working').select{|w| w.job.ie{|j| j and j['payload'] and j['payload']['args'].first == path}}.first
    end

    def Resque.set_worker_args_by_path(path,args)
      #this only works on working workers
      worker = Resque.find_worker_by_path(path)
      args_string = args.map{|k,v| "#{k}: #{v}"}.join(";")
      #also fire a log, cap logfiles at 10 MB
      worker_string = worker ? worker.to_s : "no worker"
      info_msg = "[#{worker_string} for #{path}: #{Time.now.utc}] #{args_string}"
      Logger.new(Resque.log_path, 10, 1024*1000*10).info(info_msg)
      return false unless worker
      Resque.set_worker_args(worker,args)
      return true
    end

    def Resque.get_worker_args(worker)
      key = "worker:#{worker}"
      json = ::Resque.redis.get(key)
      if json
        hash = JSON.parse(json)
        hash['payload']['args'].last
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

    def Resque.new_failures_by_email
      fjobs = {}
      exc_to_s = Hash.new(0)
      Resque.failures.each_with_index do |f,f_i|
        #skip if already notified
        next if f['notified']
        #try to send message to stage owner, where appropriate
        stage_path = f['payload']['args'].first
        email = begin
                  s = Stage.where(:path=>stage_path).first
                  s.job.runner.user.email
                rescue
                  #jobs without stages are sent to first admin
                  Jobtracker.admin_emails.first
                end
        exc_to_s = f['error']
        if fjobs[email].nil?
          fjobs[email] = {stage_path => {exc_to_s => 1}}
        elsif fjobs[email][stage_path].nil?
          fjobs[email][stage_path] = {exc_to_s => 1}
        elsif fjobs[email][stage_path][exc_to_s].nil?
          fjobs[email][stage_path][exc_to_s] = 1
        else
          fjobs[email][stage_path][exc_to_s] += 1
        end
        #add notified flag to redis
        f['notified'] = true
        #tag stage with email
        ::Resque.redis.lset(:failed, f_i, ::Resque.encode(f))
      end
      return fjobs
    end

    def Resque.start_workers(count=1)
      count.times do
        dir_envs = "MOBILIZE_ENV=#{Base.env} " +
                   "MOBILIZE_CONFIG_DIR=#{Base.config_dir} " +
                   "MOBILIZE_LOG_DIR=#{Base.log_dir}"
        "(cd #{Base.root};rake #{dir_envs} mobilize_base:work) >> #{Resque.log_path} 2>&1 &".bash
      end
    end

    def Resque.kill_idle_workers(count=nil)
      idle_pids = Resque.workers('idle').select{|w| w.job=={}}.map{|w| w.to_s.split(":").second}
      if count.to_i > idle_pids.length or count == 0
        return false
      elsif count
        "kill #{idle_pids[0..count-1].join(" ")}".bash(false)
      else
        "kill #{idle_pids.join(" ")}".bash(false)
      end
      return true
    end

    def Resque.kill_idle_and_stale_workers
      idle_pids = Resque.workers('idle').select{|w| w.job=={}}.map{|w| w.to_s.split(":").second}
      stale_pids = Resque.workers('stale').select{|w| w.job=={}}.map{|w| w.to_s.split(":").second}
      idle_stale_pids = (idle_pids & stale_pids)
      if idle_stale_pids.length == 0
        return false
      else
        "kill #{idle_stale_pids.join(" ")}".bash(false)
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
