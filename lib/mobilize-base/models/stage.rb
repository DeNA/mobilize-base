module Mobilize
  class Stage
    include Mongoid::Document
    include Mongoid::Timestamps
    field :path, type: String
    field :handler, type: String
    field :call, type: String
    field :param_string, type: Array
    field :status, type: String
    field :response, type: Hash
    field :retries, type: Fixnum
    field :completed_at, type: Time
    field :started_at, type: Time
    field :failed_at, type: Time
    field :status_at, type: Time

    index({ path: 1})

    def idx
      s = self
      s.path.split("/").last.gsub("stage","").to_i
    end

    def out_dst
      #this gives a dataset that points to the output
      #allowing you to determine its size
      #before committing to a read or write
      s = self
      Dataset.find_by_url(s.response['out_url']) if s.response and s.response['out_url']
    end

    def err_dst
      #this gives a dataset that points to the output
      #allowing you to determine its size
      #before committing to a read or write
      s = self
      Dataset.find_by_url(s.response['err_url']) if s.response and s.response['err_url']
    end

    def params
      s = self
      p = YAML.easy_load(s.param_string)
      raise "Must resolve to Hash" unless p.class==Hash
      return p
    end

    def job
      s = self
      job_path = s.path.split("/")[0..-2].join("/")
      Job.where(:path=>job_path).first
    end

    def Stage.find_or_create_by_path(path)
      s = Stage.where(:path=>path).first
      s = Stage.create(:path=>path) unless s
      return s
    end

    def Stage.find_by_path(path)
      s = Stage.where(:path=>path).first
      return s
    end

    def prior
      s = self
      j = s.job
      return nil if s.idx==1
      return j.stages[s.idx-2]
    end

    def next
      s = self
      j = s.job
      return nil if s.idx == j.stages.length
      return j.stages[s.idx]
    end

    def Stage.perform(id,*args)
      s = Stage.where(:path=>id).first
      s.update_attributes(:started_at=>Time.now.utc)
      s.update_status(%{Starting at #{Time.now.utc}})
      begin
        #get response by running method
        response = "Mobilize::#{s.handler.humanize}".constantize.send("#{s.call}_by_stage_path",s.path)
        unless response
          #re-queue self if no response
          s.enqueue!
          return false
        end
        if response['signal'] == 0
          s.complete(response)
        elsif s.params['retries'].to_i < s.retries.to_i
          #retry
          s.update_attributes(:retries => s.retries.to_i + 1, :response=>response)
          s.enqueue!
        else
          s.fail(response)
        end
      rescue ScriptError, StandardError => exc
        s.fail(exc)
      end
      return true
    end

    def complete(response)
      s = self
      s.update_attributes(:completed_at=>Time.now.utc)
      s.update_status("Completed at #{Time.now.utc.to_s}")
      j = s.job
      if s.idx == j.stages.length
        #check for any dependent jobs, if there are, enqueue them
        r = j.runner
        dep_jobs = r.jobs.select do |dj|
                                   dj.active==true and
                                     dj.trigger.strip.downcase == "after #{j.name}"
                                 end
        #put begin/rescue so all dependencies run
        dep_jobs.each do |dj|
                        begin
                          unless dj.is_working?
                            dj.stages.first.update_attributes(:retries=>0)
                            dj.stages.first.enqueue!
                          end
                        rescue
                          #job won't run if error, log it a failure
                          response = {"err_txt" => "Unable to enqueue first stage of #{dj.path}"}
                          dj.stages.first.fail(response)
                        end
                      end
      else
        #queue up next stage
        s.next.update_attributes(:retries=>0)
        s.next.enqueue!
      end
      true
    end

    def fail(response)
      s = self
      s.job.update_attributes(:active=>false)
      s.update_attributes(:failed_at=>Time.now.utc,:response=>response)
      s.update_status("Failed at #{Time.now.utc.to_s}")
      true
    end

    def enqueue!
      s = self
      ::Resque::Job.create("mobilize",Stage,s.path,{})
      return true
    end

    def worker
      s = self
      Mobilize::Resque.find_worker_by_path(s.path)
    end

    def worker_args
      s = self
      Jobtracker.get_worker_args(s.worker)
    end

    def set_worker_args(args)
      s = self
      Jobtracker.set_worker_args(s.worker,args)
    end

    def update_status(msg)
      s = self
      s.update_attributes(:status=>msg,:status_at=>Time.now.utc)
      Mobilize::Resque.set_worker_args_by_path(s.path,{'status'=>msg})
      return true
    end

    def is_working?
      s = self
      Mobilize::Resque.active_paths.include?(s.path)
    end

    def target_url
      s = self
      params = s.params
      target_path = params['target']
      handler,path = target_path.split("://")
      #if the user has specified a url for a target
      #that is not this stage's handler, disallow
      if handler and path and handler != s.handler
        raise "incompatible target handler #{handler} for #{s.handler} stage"
      else
        path = target_path
      end
      s.handler.downcase.capitalize.constantize.url(path)
    end

    def source_urls
      #returns an array of Datasets corresponding to 
      #gridfs caches for stage outputs, gsheets and gfiles
      #or dataset pointers for other handlers
      s = self
      params = s.params
      source_paths = if params['sources']
                       params['sources']
                     elsif params['source']
                       [params['source']]
                     end
      return [] if (source_paths.class!=Array or source_paths.length==0)
      urls = []
      source_paths.each do |source_path|
        if source_path.index(/^stage[1-5]$/)
          #stage arguments return the stage's output dst url
          source_stage_path = "#{s.job.runner.path}/#{s.job.name}/#{source_path}"
          source_stage = Stage.where(:path=>source_stage_path).first
          urls << source_stage.out_dst.url
        elsif source_path.index("://")
          handler,path = source_path.split("://")
          begin
            urls << handler.downcase.capitalize.constantize.url(path)
          rescue => exc
            raise "Could not get url for #{source_path} with error: #{exc.to_s}"
          end
        else
          urls << s.handler.capitalize.constantize.url(source_path)
        end
      end
      return urls
    end
  end
end
