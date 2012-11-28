module Mobilize
  class Job
    include Mongoid::Document
    include Mongoid::Timestamps
    field :requestor_id, type: String
    field :name, type: String
    field :active, type: Boolean #active, inactive
    field :schedule, type: String
    field :active_task, type: String
    field :tasks, type: String
    field :status, type: String
    field :last_error, type: String
    field :last_trace, type: String
    field :last_completed_at, type: Time
    field :datasets, type: String #name of data sources
    field :params, type: String #JSON
    field :destination, type: String #output destination - could be file, could be sheet

    index({ requestor_id: 1})
    index({ name: 1})

    before_destroy :destroy_output_dst_ids

    def worker
      j = self
      Mobilize::Resque.find_worker_by_mongo_id(j.id.to_s)
    end

    def dataset_array
      j = self
      r = j.requestor
      dsts = j.datasets.split(",").map{|dst| dst.strip}
      dsts.map do |ps|
        #prepend jobspec title if there is no path separator
        full_ps = ps.index("/") ? ps : [r.jobspec_title,ps].join("/")
        #find or create dataset for this sheet
        dst = Dataset.find_or_create_by_handler_and_name("gsheet",full_ps)
        dst.update_attributes(:requestor_id=>r.id.to_s) unless dst.requestor_id
        dst
      end
    end

    def task_array
      self.tasks.split(",").map{|t| t.strip}
    end

    def task_output_dsts
      j = self
      r = j.requestor
      dst_names = j.task_array.map{|tname| [r.name,j.name,tname].join("/")}
      dst_names.map do |dst_name|
        Dataset.find_or_create_by_requestor_id_and_handler_and_name(r.id.to_s,'mongodb',dst_name)
      end
    end

    def task_idx
      j = self
      j.task_array.index(j.active_task)
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
      r = j.requestor
      handler,method_name = j.active_task.split(".")
      begin
        j.update_status(%{Starting #{j.active_task} task at #{Time.now.utc}})
        task_output = "Mobilize::#{handler.humanize}".constantize.send("#{method_name}_by_job_id",id)
        #this allows user to return false if the stage didn't go as expected and needs to retry
        #e.g. tried to write to Google but all the accounts were in use
        return false if task_output == false
        task_output_dst = j.task_output_dsts[j.task_idx]
        task_output = task_output.to_s unless task_output.class == String
        task_output_dst.write_cache(task_output)
        if j.active_task == j.task_array.last
          j.active_task = nil
          j.last_error = ""
          j.last_trace = ""
          j.last_completed_at = Time.now.utc
          j.status = %{Completed all tasks at #{Time.now.utc}}
          j.save!
          #check for any dependent jobs, if there are, enqueue them
          r = j.requestor
          dep_jobs = Job.where(:active=>true, :requestor_id=>r.id.to_s, :schedule=>"after #{j.name}").to_a
          dep_jobs += Job.where(:active=>true, :schedule=>"after #{r.name}/#{j.name}").to_a
          #put begin/rescue so all dependencies run
          dep_jobs.each{|dj| begin;dj.enqueue! unless dj.is_working?;rescue;end}
        else
          #set next task
          j.active_task = j.task_array[j.task_idx+1]
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
      r = j.requestor
      j.update_attributes(:active_task=>j.task_array.first) if j.active_task.blank?
      ::Resque::Job.create("mobilize",Job,j.id.to_s,%{#{r.name}=>#{j.name}})
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
      task_idx = j.task_array.index(j.active_task)
      return nil if task_idx==0
      return j.task_array[task_idx-1]
    end

    def destination_url
      j = self
      return nil if j.destination.nil?
      destination = j.destination
      dst = if j.task_array.last == 'gsheet.write'
              destination = [j.requestor.jobspec_title,j.destination].join("/") if destination.split("/").length==1
              Dataset.find_by_handler_and_name('gsheet',destination)
            elsif j.task_array.last == 'gfile.write'
              #all gfiles must end in gz
              destination += ".gz" unless destination.ends_with?(".gz")
              destination = [s.requestor.name,"_"].join + destination unless destination.starts_with?([s.requestor.name,"_"].join)
              Dataset.find_by_handler_and_name('gfile',destination)
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
      return false if j.is_working? or j.active == false or j.schedule.to_s.starts_with?("after")
      last_run = j.last_completed_at
      #check schedule
      schedule = j.schedule
      return true if schedule == 'once'
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
