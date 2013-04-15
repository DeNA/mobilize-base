module Mobilize
  class Job
    include Mongoid::Document
    include Mongoid::Timestamps
    include Mobilize::JobHelper
    field :path, type: String
    field :active, type: Boolean
    field :trigger, type: String

    index({ path: 1})

    #takes a hash of job parameters (name, active, trigger, stages)
    #and creates/updates a job with it
    def Job.update_by_user_name_and_hash(user_name,hash)
      j = Job.find_or_create_by_path("Runner_#{user_name}/jobs/#{hash['name']}")
      #update top line params
      j.update_attributes(:active => hash['active'],
                          :trigger => hash['trigger'])
      (1..5).to_a.each do |s_idx|
        stage_string = hash["stage#{s_idx.to_s}"]
        s = Stage.find_by_path("#{j.path}/stage#{s_idx.to_s}")
        if stage_string.to_s.length==0
          #delete this stage and all stages after
          if s
            j = s.job
            j.stages[(s.idx-1)..-1].each{|ps| ps.delete}
            #just in case
            s.delete
          end
          break
        elsif s.nil?
          #create this stage
          s = Stage.find_or_create_by_path("#{j.path}/stage#{s_idx.to_s}")
        end
        #parse command string, update stage with it
        s_handler, call, param_string = [""*3]
        stage_string.split(" ").ie do |spls|
          s_handler = spls.first.split(".").first
          call = spls.first.split(".").last
          param_string = spls[1..-1].join(" ").strip
        end
        s.update_attributes(:call=>call, :handler=>s_handler, :param_string=>param_string)
      end
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
