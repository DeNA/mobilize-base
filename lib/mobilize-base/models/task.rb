module Mobilize
  class Task
    include Mongoid::Document
    include Mongoid::Timestamps
    field :path, type: String
    field :handler, type: String
    field :call, type: String
    field :param_string, type: Array
    field :status, type: String
    field :last_completed_at, type: Time
    field :last_run_at, type: Time

    index({ path: 1})

    def idx
      t = self
      t.path.split("/").last.gsub("task","").to_i
    end

    def stdout_dataset
      t = self
      Dataset.find_or_create_by_handler_and_path("gridfs","#{t.path}/stdout")
    end

    def stderr_dataset
      t = self
      Dataset.find_or_create_by_handler_and_path("gridfs","#{t.path}/stderr")
    end

    def params
      t = self
      t.param_string.split(",").map do |p| 
        ps = p.strip
        ps = ps[1..-1] if ps[0] == '"'
        ps = ps[0..-2] if ps[-1] == '"'
        ps
      end
    end

    def job
      t = self
      job_path = t.path.split("/")[0..-2].join("/")
      Job.where(:path=>job_path).first
    end

    def Task.find_or_create_by_path(path)
      t = Task.where(:path=>path).first
      t = Task.create(:path=>path) unless t
      return t
    end

    def prior
      t = self
      j = t.job
      return nil if t.idx==1
      return j.tasks[t.idx-2]
    end

    def next
      t = self
      j = t.job
      return nil if t.idx == j.tasks.length
      return j.tasks[t.idx]
    end

    def Task.perform(id,*args)
      t = Task.where(:path=>id).first
      j = t.job
      t.update_status(%{Starting at #{Time.now.utc}})
      stdout, stderr = [nil,nil]
      begin
        stdout = "Mobilize::#{t.handler.humanize}".constantize.send("#{t.call}_by_task_path",t.path).to_s
      rescue ScriptError, StandardError => exc
        stderr = [exc.to_s,exc.backtrace.to_s].join("\n")
        #record the failure in Job so it appears on Runner
        j.update_attributes(:status=>"Failed at #{Time.now.utc.to_s}")
        t.update_attributes(:status=>"Failed at #{Time.now.utc.to_s}")
        raise exc
      end
      if stdout == false
        #re-queue self if output is false
        t.enqueue!
        return false
      end
      #write output to cache
      t.stdout_dataset.write_cache(stdout)
      t.update_attributes(:status=>"Completed at #{Time.now.utc.to_s}")
      if t.idx == j.tasks.length
        j.update_attributes(:status=>"Completed at #{Time.now.utc.to_s}",:last_completed_at=>Time.now.utc)
        j.update_attributes(:active=>false) if j.trigger.strip == "once"
        t.update_attributes(:status=>"Completed at #{Time.now.utc.to_s}",:last_completed_at=>Time.now.utc)
        #check for any dependent jobs, if there are, enqueue them
        r = j.runner
        dep_jobs = r.jobs.select{|dj| dj.active==true and dj.trigger=="after #{j.name}"}
        #put begin/rescue so all dependencies run
        dep_jobs.each{|dj| begin;dj.tasks.first.enqueue! unless dj.is_working?;rescue;end}
      else
        #queue up next task
        t.next.enqueue!
      end
      return true
    end

    def enqueue!
      t = self
      ::Resque::Job.create("mobilize",Task,t.path,{})
      return true
    end

    def worker
      t = self
      Mobilize::Resque.find_worker_by_path(t.path)
    end

    def worker_args
      t = self
      Jobtracker.get_worker_args(t.worker)
    end

    def set_worker_args(args)
      t = self
      Jobtracker.set_worker_args(t.worker,args)
    end

    def update_status(msg)
      t = self
      t.update_attributes(:status=>msg)
      Mobilize::Resque.set_worker_args_by_path(t.path,{'status'=>msg})
      return true
    end

    def is_working?
      t = self
      Mobilize::Resque.active_paths.include?(t.path)
    end
  end
end
