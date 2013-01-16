module Mobilize
  class Stage
    include Mongoid::Document
    include Mongoid::Timestamps
    field :path, type: String
    field :handler, type: String
    field :call, type: String
    field :param_string, type: Array
    field :status, type: String
    field :out_url, type: String
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
      Dataset.find_by_url(s.out_url) if s.out_url
    end

    def params
      s = self
      #evaluates param_string to ruby hash
      #using YAML parser
      #TODO: eliminate ridiculousness
      begin
        YAML.load(s.param_string)
        raise "Must resolve to Hash" unless result.class==Hash
      rescue
        sub_param_string = s.param_string.gsub(":\"",": \"").gsub(":'",": '").gsub(":[",": [").gsub(":{",": {").gsub(/(:[0-9])/,'stageparamsgsub\1').gsub('stageparamsgsub:',': ')
        YAML.load("{#{sub_param_string}}")
      end
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
      j = s.job
      s.update_attributes(:started_at=>Time.now.utc)
      s.update_status(%{Starting at #{Time.now.utc}})
      begin
        #get response by running method
        s.out_url = "Mobilize::#{s.handler.humanize}".constantize.send("#{s.call}_by_stage_path",s.path)
        s.save!
        unless s.out_url
          #re-queue self if no response
          s.enqueue!
          return false
        end
      rescue ScriptError, StandardError => exc
        j.update_attributes(:active=>false)
        s.update_attributes(:failed_at=>Time.now.utc)
        s.update_status("Failed at #{Time.now.utc.to_s}")
        raise exc
      end
      s.update_attributes(:completed_at=>Time.now.utc)
      s.update_status("Completed at #{Time.now.utc.to_s}")
      if s.idx == j.stages.length
        #job has completed
        j.update_attributes(:active=>false) if j.trigger.strip.downcase == "once"
        #check for any dependent jobs, if there are, enqueue them
        r = j.runner
        dep_jobs = r.jobs.select{|dj| dj.active==true and dj.trigger.strip.downcase == "after #{j.name}"}
        #put begin/rescue so all dependencies run
        dep_jobs.each{|dj| begin;dj.stages.first.enqueue! unless dj.is_working?;rescue;end}
      else
        #queue up next stage
        s.next.enqueue!
      end
      return true
    end

    def source_dsts(gdrive_slot)
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
      dsts = []
      source_paths.each do |source_path|
        if source_path.index(/^stage[1-5]$/)
          source_stage_path = "#{s.job.runner.path}/#{s.job.name}/#{source_path}"
          source_stage = Stage.where(:path=>source_stage_path).first
          dsts << source_stage.out_dst
        elsif source_path.index("://")
          #find or create by url
          dsts << Dataset.find_or_create_by_url(source_path)
        else
          if source_path.index("/")
            #slashes mean sheets
            out_tsv = Gsheet.find_by_path(source_path,gdrive_slot).to_tsv
          else
            #check sheets in runner
            r = s.job.runner
            runner_sheet = r.gbook.worksheet_by_title(source_path)
            out_tsv = if runner_sheet
                        runner_sheet.to_tsv
                      else
                        #check for gfile. will fail if there isn't one.
                        Gfile.find_by_path(source_path).read
                      end
          end
          #use Gridfs to cache gdrive results
          file_name = source_path.split("/").last
          out_url = "gridfs://#{s.path}/#{file_name}"
          Dataset.write_to_url(out_url,out_tsv)
          dsts << Dataset.find_by_url(out_url)
        end
      end 
      return dsts
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
  end
end
