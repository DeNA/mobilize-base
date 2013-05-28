module Mobilize
  class Job
    include Mongoid::Document
    include Mongoid::Timestamps
    include Mobilize::JobHelper
    field :path, type: String
    field :active, type: Boolean
    field :trigger, type: String

    index({ path: 1})

    def Job.find_or_create_by_path(path)
      j = Job.where(:path=>path).first
      j = Job.create(:path=>path) unless j
      return j
    end

    def parent
      j = self
      u = j.runner.user
      if j.trigger.strip[0..4].downcase == "after"
        parent_name = j.trigger[5..-1].to_s.strip
        parent_j = u.jobs.select{|job| job.name == parent_name}.first
        return parent_j
      else
        return nil
      end
    end

    def children
      j = self
      u = j.runner.user
      u.jobs.select do |job|
        parent_name = job.trigger[5..-1].to_s.strip
        job.trigger.strip[0..4].downcase == "after" and
          parent_name == j.name
      end
    end

    #takes a hash of job parameters (name, active, trigger, stages)
    #and creates/updates a job with it
    def update_from_hash(hash)
      j = self
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
      return j.reload
    end

    def is_due?
      j = self
      #working or inactive jobs are not due
      if j.is_working? or j.active == false
        return false
      end

      #if job contains handlers not loaded by jobtracker, not due
      loaded_handlers = Jobtracker.config['extensions'].map{|m| m.split("-").last}
      job_handlers = j.stages.map{|s| s.handler}.uniq
      #base handlers are the ones in mobilize-base/handlers
      if (job_handlers - loaded_handlers - Base.handlers).length>0
        return false
      end

      #once
      if j.trigger.strip.downcase=='once'
        #active and once means due
        return true
      end

      #depedencies
      if j.parent
        #if parent is not working and completed more recently than self, is due
        if !j.parent.is_working? and
          j.parent.completed_at and (j.completed_at.nil? or j.parent.completed_at > j.completed_at)
          return true
        else
          return false
        end
      end

      #time based
      last_comp_time = j.completed_at
      #check trigger; strip the "every" from the front if present, change dot to space
      trigger = j.trigger.strip.gsub("every","").gsub("."," ").strip
      number, unit, operator, mark = trigger.split(" ").map{|t_node| t_node.downcase}
      #operator is not used
      operator = nil
      #get time for time-based evaluations
      curr_time = Time.now.utc
      if ["hour","hours","day","days"].include?(unit)
        if mark
          last_mark_time = Time.at_marks_ago(number,unit,mark)
          if last_comp_time.nil? or last_comp_time < last_mark_time
            return true
          else
            return false
          end
        elsif last_comp_time.nil? or last_comp_time < (curr_time - number.to_i.send(unit))
          return true
        else
          return false
        end
      elsif unit == "day_of_week"
        if curr_time.wday==number and (last_comp_time.nil? or last_comp_time.to_date != curr_time.to_date)
          if mark
            #check if it already ran today
            last_mark_time = Time.at_marks_ago(1,"day",mark)
            if last_comp_time < last_mark_time
              return true
            else
              return false
            end
          else
            return true
          end
        end
      elsif unit == "day_of_month"
        if curr_time.day==number and (last_comp_time.nil? or last_comp_time.to_date != curr_time.to_date)
          if mark
            #check if it already ran today
            last_mark_time = Time.at_marks_ago(1,"day",mark)
            if last_comp_time < last_mark_time
              return true
            else
              return false
            end
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
