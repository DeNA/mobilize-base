module Mobilize
  class Task
    include Mongoid::Document
    include Mongoid::Timestamps
    field :path, type: String
    field :handler, type: String
    field :call, type: String
    field :param_string, type: Array
    field :status, type: String
    field :completed_at, type: Time
    field :started_at, type: Time
    field :failed_at, type: Time
    field :status_at, type: Time

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

    def log_dataset
      t = self
      Dataset.find_or_create_by_handler_and_path("gridfs","#{t.path}/log")
    end

    def params
      t = self
      #evaluates param_string to ruby hash
      #using YAML parser
      #TODO: eliminate ridiculousness
      begin
        YAML.load(t.param_string)
        raise "Must resolve to Hash" unless result.class==Hash
      rescue
        sub_param_string = t.param_string.gsub(":\"",": \"").gsub(":'",": '").gsub(":[",": [").gsub(":{",": {").gsub(/(:[0-9])/,'taskparamsgsub\1').gsub('taskparamsgsub:',': ')
        YAML.load("{#{sub_param_string}}")
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
      t.update_attributes(:started_at=>Time.now.utc)
      t.update_status(%{Starting at #{Time.now.utc}})
      stdout, stderr = [nil,nil]
      begin
        stdout,log = "Mobilize::#{t.handler.humanize}".constantize.send("#{t.call}_by_task_path",t.path).to_s
        #write to log if method returns an array w 2 members
        t.log_dataset.write_cache(log) if log
      rescue ScriptError, StandardError => exc
        stderr = [exc.to_s,exc.backtrace.to_s].join("\n")
        #record the failure in Job so it appears on Runner, turn it off
        #so it doesn't run again
        j.update_attributes(:active=>false)
        t.update_attributes(:failed_at=>Time.now.utc)
        t.update_status("Failed at #{Time.now.utc.to_s}")
        raise exc
      end
      if stdout == false
        #re-queue self if output is false
        t.enqueue!
        return false
      end
      #write output to cache
      t.stdout_dataset.write_cache(stdout)
      t.update_attributes(:completed_at=>Time.now.utc)
      t.update_status("Completed at #{Time.now.utc.to_s}")
      if t.idx == j.tasks.length
        #job has completed
        j.update_attributes(:active=>false) if j.trigger.strip.downcase == "once"
        #check for any dependent jobs, if there are, enqueue them
        r = j.runner
        dep_jobs = r.jobs.select{|dj| dj.active==true and dj.trigger.strip.downcase == "after #{j.name}"}
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
      t.update_attributes(:status=>msg,:status_at=>Time.now.utc)
      Mobilize::Resque.set_worker_args_by_path(t.path,{'status'=>msg})
      return true
    end

    def is_working?
      t = self
      Mobilize::Resque.active_paths.include?(t.path)
    end
  end
end
