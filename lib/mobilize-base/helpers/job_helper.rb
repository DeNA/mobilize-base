#this module adds convenience methods to the Job model
module Mobilize
  module JobHelper
    def name
      j = self
      j.path.split("/").last
    end

    def stages
      j = self
      #starts with the job path, followed by a slash
      Stage.where(:path=>/^#{j.path.escape_regex}\//).to_a.sort_by{|s| s.path}
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
      runner_path = j.path.split("/")[0..1].join("/")
      return Runner.where(:path=>runner_path).first
    end

    def is_working?
      j = self
      j.stages.select{|s| s.is_working?}.compact.length>0
    end
  end
end
