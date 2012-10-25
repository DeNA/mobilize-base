module Resque
  class Resque::Mobilize
    def Mobilize.resqueued_job_ids
      return (Resque.queues.map{|q| Resque.peek(q,0,0).to_a}.compact + Resque.workers.map{|w| w.job['payload']}.compact).flatten.map{|j| j['args'].first}
    end

    def Mobilize.working_jobs
      return Job.where(:status=>'working',:id=>{:$nin=>Mobilize.resqueued_job_ids},:stages=>{:$ne=>[]}).to_a.select{|j| j.spec if j.spec_id}.compact
    end

    def Mobilize.max_timeout_jobs
      return Mobilize.working_jobs.select{|j| j.updated_at < Time.now.utc - Jobtracker.max_run_time}
    end

    #Resque workers and methods to find 
    def Mobilize.worker_by_id(id)
      resque_job = Mobilize.active_jobs.select{|job| job['payload']['args'][0] == id}.first
      if resque_job
        rhash = Resque.redis.get("worker:#{resque_job['worker']}").json_to_hash
        rhash['key'] = resque_job['worker']
        return rhash
      end
    end

    def Mobilize.update_worker_status(worker,msg)
      Mobilize.set_worker_args(worker,{"status"=>msg})
      #also fire a log
      Logger.new(Mobilize::Base.log_path, 10, 1024000).info("[#{worker} #{Mobilize.env} #{Time.now.utc}] #{msg}")
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
  end
end
