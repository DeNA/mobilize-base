module Mobilize
  class Gfile
    def Gfile.find_by_title(title,email=nil)
      Gdriver.files(email).select{|f| f.title==title}.first
    end

    def Gfile.find_by_dst_id(dst_id,email=nil)
      dst = Dataset.find(dst_id)
      Gfile.find_by_title(dst.path,email)
    end

    def Gfile.add_admin_acl_by_dst_id(dst_id)
      #adds admins and workers as writers
      file = Gfile.find_by_dst_id(dst_id)
      file.add_admin_acl
      return true
    end

    def Gfile.add_admin_acl_by_title(title)
      file = Gfile.find_by_title(title)
      file.add_admin_acl
      return true
    end

    def Gfile.add_worker_acl_by_title(title)
      file = Gfile.find_by_title(title)
      file.add_worker_acl
      return true
    end

    def Gfile.update_acl_by_dst_id(dst_id,email,role="writer",edit_email=nil)
      dst = Dataset.find(dst_id)
      Gfile.update_acl_by_title(dst.path,email,role,edit_email)
    end

    def Gfile.update_acl_by_title(title,email,role="writer",edit_email=nil)
      file = Gfile.find_by_title(title,edit_email)
      raise "File #{title} not found" unless file
      file.update_acl(email,role)
    end

    def Gfile.read_by_name()
      
    end

    def Gfile.read_by_url()
      
    end

    def Gfile.read_by_job_id(job_id)
      j = Job.find(job_id)
    end

  end
end
