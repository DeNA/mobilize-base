module Mobilize
  class Stage
    include Mongoid::Document
    include Mongoid::Timestamps
    include Mobilize::StageHelper
    field :path, type: String
    field :handler, type: String
    field :call, type: String
    field :param_string, type: Array
    field :status, type: String
    field :response, type: Hash
    field :retries_done, type: Fixnum
    field :completed_at, type: Time
    field :started_at, type: Time
    field :failed_at, type: Time
    field :status_at, type: Time

    index({ path: 1})

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
      #get response by running method
      response = begin
                   "Mobilize::#{s.handler.humanize}".constantize.send("#{s.call}_by_stage_path",s.path)
                 rescue => exc
                   {'err_str'=>"#{exc.to_s}\n#{exc.backtrace.to_a.join("\n")}", 'signal'=>500}
                 end
      unless response
        #re-queue self if no response
        s.enqueue!
        return false
      end
      if response['signal'] == 0
        s.complete(response)
      elsif s.retries_done.to_i < s.params['retries'].to_i
        #retry
        s.update_attributes(:retries_done => s.retries_done.to_i + 1, :response => response)
        s.update_status(%{Retry #{s.retries_done.to_s} at #{Time.now.utc}})
        sleep s['delay'].to_i
        s.enqueue!
      else
        #sleep as much as user specifies
        s.fail(response)
      end
      return true
    end

    def complete(response)
      s = self
      s.update_attributes(:completed_at=>Time.now.utc,:response=>response)
      s.update_status("Completed at #{Time.now.utc.to_s}")
      j = s.job
      if s.idx == j.stages.length
        #check for any dependent jobs, if there are, enqueue them
        r = j.runner
        dep_jobs = r.jobs.select do |dj|
                                   dj.active==true and
                                     dj.trigger.strip.downcase == "after #{j.name.downcase}"
                                 end
        #put begin/rescue so all dependencies run
        dep_jobs.each do |dj|
                        begin
                          unless dj.is_working?
                            dj.stages.first.update_attributes(:retries_done=>0)
                            dj.stages.first.enqueue!
                          end
                        rescue
                          #job won't run if error, log it a failure
                          response = {"err_str" => "Unable to enqueue first stage of #{dj.path}"}
                          dj.stages.first.fail(response)
                        end
                      end
      else
        #queue up next stage
        s.next.update_attributes(:retries_done=>0)
        s.next.enqueue!
      end
      true
    end

    def fail(response,gdrive_slot=nil)
      #get random worker if one is not provided
      gdrive_slot ||= Gdrive.worker_emails.sort_by{rand}.first
      s = self
      j = s.job
      r = j.runner
      u = r.user
      j.update_attributes(:active=>false) if s.params['always_on'].to_s=="false"
      s.update_attributes(:failed_at=>Time.now.utc,:response=>response)
      stage_name = "#{j.name}_stage#{s.idx.to_s}.err"
      target_path =  (r.path.split("/")[0..-2] + [stage_name]).join("/")
      status_msg = "Failed at #{Time.now.utc.to_s}"
      #read err txt, add err sheet, write to it
      err_sheet = Gsheet.find_by_path(target_path,gdrive_slot)
      err_sheet.delete if err_sheet
      err_sheet = Gsheet.find_or_create_by_path(target_path,gdrive_slot)
      err_txt = if response['err_url']
                  Dataset.read_by_url(response['err_url'],u.name)
                elsif response['err_str']
                  response['err_str']
                end
      err_txt = ["response","\n",err_txt].join
      err_sheet.write(err_txt,u.name)
      #exception will be first row below "response" header
      s.update_status(status_msg)
      #raise the exception so it bubbles up to resque
      raise Exception,err_txt
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

    def target
      s = self
      params = s.params
      target_path = params['target']
      handler,path = target_path.split("://")
      #if the user has specified a url for a target
      #that is not this stage's handler, disallow
      if handler and path and handler != s.handler
        raise "incompatible target handler #{handler} for #{s.handler} stage"
      else
        begin
          #nil gdrive_slot for targets since there is no verification
          return "Mobilize::#{s.handler.downcase.capitalize}".constantize.path_to_dst(target_path,s.path,nil)
        rescue => exc
          raise "Could not get #{target_path} with error: #{exc.to_s}"
        end
      end
    end

    def sources(gdrive_slot)
      #returns an array of Datasets corresponding to
      #items listed as sources in the stage params
      s = self
      params = s.params
      job = s.job
      runner = job.runner
      source_paths = if params['sources']
                       params['sources']
                     elsif params['source']
                       [params['source']]
                     end
      return [] if (source_paths.class!=Array or source_paths.length==0)
      dsts = []
      source_paths.each do |source_path|
        if source_path.index(/^stage[1-5]$/)
          #stage arguments return the stage's output dst url
          source_stage_path = "#{runner.path}/#{job.name}/#{source_path}"
          source_stage = Stage.where(:path=>source_stage_path).first
          source_stage_out_url = source_stage.response['out_url']
          dsts << Dataset.find_by_url(source_stage_out_url)
        else
          handler = if source_path.index("://")
                      source_path.split("://").first
                    else
                      s.handler
                    end
          begin
            stage_path = s.path
            dsts << "Mobilize::#{handler.downcase.capitalize}".constantize.path_to_dst(source_path,stage_path,gdrive_slot)
          rescue => exc
            raise "Could not get #{source_path} with error: #{exc.to_s}"
          end
        end
      end
      return dsts
    end
  end
end
