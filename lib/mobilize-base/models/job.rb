module Mobilize
  class Job
    include Mongoid::Document
    include Mongoid::Timestamps
    field :requestor_id, type: String
    field :name, type: String
    field :active, type: Boolean #active, inactive
    field :schedule, type: String
    field :active_task, type: String
    field :tasks, type: Hash
    field :status, type: String
    field :last_error, type: String
    field :last_trace, type: String
    field :last_completed_at, type: Time
    field :read_handler, type: String
    field :write_handler, type: String
    field :param_source, type: String #name of sheet on doc
    field :param_hash, type: String #JSON
    field :destination, type: String #output destination - could be file, could be sheet

    index({ requestor_id: 1})
    index({ name: 1})

    before_destroy :destroy_output_dst_ids

    def worker
      j = self
      Mobilize::Resque.find_worker_by_mongo_id(j.id.to_s)
    end

    def Job.find_by_name(name)
      Job.where(:name=>name).first
    end

    def Job.find_all_by_requestor_id(requestor_id)
      Job.where(:requestor_id=>requestor_id).to_a
    end

    def Job.find_or_create_by_requestor_id_and_name(requestor_id,name)
      j = Job.where(:requestor_id=>requestor_id, :name=>name).first
      j = Job.create(:requestor_id=>requestor_id, :name=>name) unless j
      return j
    end

    #called by Resque
    def Job.perform(id,*args)
      j = Job.find(id)
      task_params = j.tasks[j.active_task]
      begin
        j.update_status(%{Starting #{j.active_task} task at #{Time.now.utc}})
        task_output = "Mobilize::#{task_params['handler'].humanize}".constantize.send(j.active_task,id)
        #this allows user to return false if the stage didn't go as expected and needs to retry
        #e.g. tried to write to Google but all the accounts were in use
        return false if task_output == false
        task_output_dst_id = if task_output.to_s.length==24 and Dataset.find(task_output.to_s)
                              #user has returned dst as output from task
                              task_output
                            else
                              #store the output in a cache
                              dst = Dataset.find_or_create_by_requestor_id_and_handler_and_name(j.requestor.id.to_s,'mongoer',"#{j.id.to_s}/#{j.active_task}")
                              dst.write_cache(task_output.to_s)
                              dst.id.to_s
                            end
        j.tasks[j.active_task]['output_dst_id'] = task_output_dst_id
        if j.active_task == j.tasks.keys.last
          j.active_task = nil
          j.last_error = ""
          j.last_trace = ""
          j.last_completed_at = Time.now.utc
          j.status = %{Completed all tasks at #{Time.now.utc}}
          j.save!
          #check for any dependent jobs, if there are, enqueue them
          r = j.requestor
          dep_jobs = Job.where(:active=>true, :requestor_id=>r.id.to_s, :schedule=>"after #{j.name}").to_a
          dep_jobs += Job.where(:active=>true, :schedule=>"after #{r.name}|=>|#{j.name}").to_a
          #put begin/rescue so all dependencies run
          dep_jobs.each{|dj| begin;dj.enqueue! unless dj.is_working?;rescue;end}
        else
          task_names = j.tasks.keys
          stage_idx = task_names.index(j.active_task) + 1
          j.active_task = j.tasks.keys[stage_idx]
          j.save!
          #queue up next task
          j.enqueue!
        end
      rescue ScriptError,StandardError => exc
        #record the failure in Job so it appears on spec sheets
        j.status='failed'
        j.save!
        j.update_status("Failed at #{Time.now.utc.to_s}")
        j.update_attributes(:last_error=>exc.to_s,:last_trace=>exc.backtrace.to_s)
        [exc.to_s,exc.backtrace.to_s].join("=>").oputs
        #raising here will cause the failure to show on the Resque UI
        raise exc
      end
      return true
    end

    def enqueue!
      j = self
      #assign first task if none assigned
      if j.tasks.blank?
        #make a hash with the read/write tasks
        j.update_attributes(:tasks=>{"read_by_job_id"=>{'handler'=>j.read_handler},
                                     "write_by_job_id"=>{'handler'=>j.write_handler}})
      end
      j.update_attributes(:active_task=>"read_by_job_id") if j.active_task.blank?
      ::Resque::Job.create("mobilize",Job,j.id.to_s,%{#{j.requestor.name}=>#{j.name}})
      return true
    end

    #convenience methods
    def requestor
      j = self
      return Requestor.find(j.requestor_id)
    end

    def restart
      j = self
      j.update_attributes(:last_completed_at=>nil)
      return true
    end

    def prior_task
      j = self
      return nil if j.active_task.nil?
      task_idx = j.tasks.keys.index(j.active_task)
      return nil if task_idx==0
      return j.tasks.keys[task_idx-1]
    end

    def destination_url
      j = self
      return nil if j.destination.nil?
      destination = j.destination
      dst = if j.write_handler == 'gsheet'
              destination = [j.requestor.jobspec_title,j.destination].join("/") if destination.split("/").length==1
              Dataset.find_by_handler_and_name('gsheeter',destination)
            elsif j.write_handler == 'gtxt'
              #all gtxt files must end in gz
              destination += ".gz" unless destination.ends_with?(".gz")
              destination = [s.requestor.name,"_"].join + destination unless destination.starts_with?([s.requestor.name,"_"].join)
              Dataset.find_by_handler_and_name('gtxter',destination)
            end
      return dst.url if dst
    end

    def worker_args
      j = self
      Jobtracker.get_worker_args(j.worker)
    end

    def set_worker_args(args)
      j = self
      Jobtracker.set_worker_args(j.worker,args)
    end

    def cache_params
      j = self
      #go to paramsheet and read
      param_path = if j.paramsheet.split("/").length==1
                     [j.requestor.jobspec_title,j.paramsheet].join("/")
                   else
                     j.paramsheet
                   end
      param_sheet = j.requestor.find_or_create_gsheet_by_path(param_path)
      param_tsv = param_sheet.to_tsv
      param_dst = j.requestor.gsheets.select{|s| s.path == param_sheet.path}
      param_dst.cache.write(param_tsv)
      s.update_attributes(:param_dst_id=>paramdst.id.to_s)
      (s.requestor.name + "'s #{s.name} params cached").oputs
      return true
    end

    def update_status(msg)
      j = self
      j.update_attributes(:status=>msg)
      Mobilize::Resque.update_job_status(j.id.to_s,msg)
      return true
    end

    def is_working?
      j = self
      Mobilize::Resque.active_mongo_ids.include?(j.id.to_s)
    end

    def is_due?
      j = self
      return false if j.is_working? or j.schedule.to_s.starts_with?("after")
      last_run = j.last_completed_at
      #check schedule
      schedule = j.schedule
      return true if schedule == 'once' and j.active
      #strip the "every" from the front if present
      schedule = schedule.gsub("every","").gsub("."," ").strip
      value,unit,operator,job_utctime = schedule.split(" ")
      curr_utctime = Time.now.utc
      curr_utcdate = curr_utctime.to_date.strftime("%Y-%m-%d")
      if job_utctime
        job_utctime = job_utctime.split(" ").first
        job_utctime = Time.parse([curr_utcdate,job_utctime,"UTC"].join(" "))
      end
      #after is the only operator
      raise "Unknown #{operator.to_s} operator" if operator and operator != "after"
      if ["hour","hours"].include?(unit)
        #if it's later than the last run + hour tolerance, is due
        if last_run.nil? or curr_utctime > (last_run + value.to_i.hour)
          return true
        end
      elsif ["day","days"].include?(unit)
        if last_run.nil? or curr_utctime.to_date >= (last_run.to_date + value.to_i.day)
          if operator and job_utctime
            if curr_utctime>job_utctime and (job_utctime - curr_utctime).abs < 1.hour
              return true
            end
          elsif operator || job_utctime
            raise "Please specify both an operator and a time in UTC, or neither"
          else
            return true
          end
        end
      elsif unit == "day_of_week"
        if curr_utctime.wday==value and (last_run.nil? or last_run.to_date != curr_utctime.to_date)
          if operator and job_utctime
            if curr_utctime>job_utctime and (job_utctime - curr_utctime).abs < 1.hour
              return true
            end
          elsif operator || job_utctime
            raise "Please specify both an operator and a time in UTC, or neither"
          else
            return true
          end
        end
      elsif unit == "day_of_month"
        if curr_utctime.day==value and (last_run.nil? or last_run.to_date != curr_utctime.to_date)
          if operator and job_utctime
            if curr_utctime>job_utctime and (job_utctime - curr_utctime).abs < 1.hour
              return true
            end
          elsif operator || job_utctime
            raise "Please specify both an operator and a time in UTC, or neither"
          else
            return true
          end
        end
      else
        raise "Unknown #{unit.to_s} time unit"
      end
      #if nothing happens, return false
      return false
    end
  end
end
