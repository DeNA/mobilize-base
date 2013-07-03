#this module adds convenience methods to the Runner model
module Mobilize
  module RunnerHelper
    def headers
      %w{name active trigger status stage1 stage2 stage3 stage4 stage5}
    end

    def title
      r = self
      r.path.split("/").first
    end

    def worker
      r = self
      Mobilize::Resque.find_worker_by_path(r.path)
    end

    def dataset
      r = self
      Dataset.find_or_create_by_handler_and_path("gsheet",r.path)
    end

    def gbook(gdrive_slot)
      r = self
      title = r.path.split("/").first
      Gbook.find_by_path(title,gdrive_slot)
    end

    def gsheet(gdrive_slot)
      r = self
      u = r.user
      jobs_sheet = Gsheet.find_by_path(r.path,gdrive_slot)
      #make sure the user has a runner with a jobs sheet and has write privileges on the spreadsheet
      unless (jobs_sheet and jobs_sheet.spreadsheet.acl_entry(u.email).ie{|e| e and e.role=="writer"})
        #only give the user edit permissions if they're the ones
        #creating it
        jobs_sheet = Gsheet.find_or_create_by_path(r.path,gdrive_slot)
        unless jobs_sheet.spreadsheet.acl_entry(u.email).ie{|e| e and e.role=="owner"}
          jobs_sheet.spreadsheet.update_acl(u.email)
        end
        jobs_sheet.add_headers(r.headers)
        begin;jobs_sheet.delete_sheet1;rescue;end #don't care if sheet1 deletion fails
      end
      return jobs_sheet
    end

    def jobs(jname=nil)
      r = self
      js = Job.where(:path=>/^#{r.path.escape_regex}/).to_a
      if jname
        return js.sel{|j| j.name == jname}.first
      else
        return js
      end
    end

    def user
      r = self
      user_name = r.path.split("_")[1..-1].join("_").split("(").first.split("/").first
      User.where(:name=>user_name).first
    end

    def update_status(msg)
      r = self
      r.update_attributes(:status=>msg, :status_at=>Time.now.utc)
      Mobilize::Resque.set_worker_args_by_path(r.path,{'status'=>msg})
      return true
    end

    def is_working?
      r = self
      Mobilize::Resque.active_paths.include?(r.path)
    end

    def is_due?
      r = self.reload
      u = r.user
      #make sure we're on the right server
      resque_server = u.resque_server
      current_server = begin;Socket.gethostbyname(Socket.gethostname);rescue;nil;end
      return false unless ['127.0.0.1',current_server].include?(resque_server)
      return false if r.is_working?
      prev_due_time = Time.now.utc - Jobtracker.runner_read_freq
      return true if r.started_at.nil? or r.started_at < prev_due_time
    end

  end
end
