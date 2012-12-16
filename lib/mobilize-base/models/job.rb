module Mobilize
  class Job
    include Mongoid::Document
    include Mongoid::Timestamps
    field :path, type: String
    field :active, type: Boolean
    field :trigger, type: String

    index({ path: 1})

    def name
      j = self
      j.path.split("/").last
    end

    def stages
      j = self
      Stage.where(:path=>/^#{j.path.escape_regex}/).to_a.sort_by{|s| s.path}
    end

    def Job.find_or_create_by_path(path)
      j = Job.where(:path=>path).first
      j = Job.create(:path=>path) unless j
      return j
    end

    def status
      #last stage status
      j = self
      j.active_stage.status if j.active_stage
    end

    def active_stage
      j = self
      #latest started at or first
      j.stages.select{|s| s.started_at}.sort_by{|s| s.started_at}.last || j.stages.first
    end

    def completed_at
      j = self
      j.stages.last.completed_at if j.stages.last
    end

    def failed_at
      j = self
      j.active_stage.failed_at if j.active_stage
    end

    def status_at
      j = self
      j.active_stage.status_at if j.active_stage
    end

    #convenience methods
    def runner
      j = self
      runner_path = j.path.split("/")[0..-2].join("/")
      return Runner.where(:path=>runner_path).first
    end

    def is_working?
      j = self
      j.stages.select{|s| s.is_working?}.compact.length>0
    end

    def is_due?
      j = self
      return false if j.is_working? or j.active == false or j.trigger.to_s.starts_with?("after")
      last_run = j.completed_at
      #check trigger
      trigger = j.trigger
      return true if trigger == 'once'
      #strip the "every" from the front if present
      trigger = trigger.gsub("every","").gsub("."," ").strip
      value,unit,operator,job_utctime = trigger.split(" ")
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
