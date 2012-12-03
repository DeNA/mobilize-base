module Mobilize
  class Job
    include Mongoid::Document
    include Mongoid::Timestamps
    field :handler, type: String
    field :path, type: String
    field :active, type: Boolean
    field :trigger, type: String
    field :status, type: String
    field :last_completed_at, type: Time

    index({ path: 1})

    def tasks
      j = self
      Task.where(:path=>/^#{j.path}/).to_a.sort_by{|t| t.path}
    end

    def Job.find_or_create_by_handler_and_path(handler,path)
      j = Job.where(:handler=>handler, :path=>path).first
      j = Job.create(:handler=>handler, :path=>path) unless j
      return j
    end

    #convenience methods
    def runner
      j = self
      return Runner.where(:handler=>j.handler,:path=>j.path.split("/")[0..-3].join("/")).first
    end

    def is_due?
      j = self
      return false if j.is_working? or j.active == false or j.trigger.to_s.starts_with?("after")
      last_run = j.last_completed_at
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
