module Mobilize
  module Gfile
    def Gfile.add_admin_acl_by_path(path)
      file = Gfile.find_by_path(path)
      file.add_admin_acl
      return true
    end

    def Gfile.add_worker_acl_by_path(path)
      file = Gfile.find_by_path(path)
      file.add_worker_acl
      return true
    end

    def Gfile.update_acl_by_path(path,gdrive_slot,role="writer",target_email=nil)
      file = Gfile.find_by_path(path,target_email)
      raise "File #{path} not found" unless file
      file.update_acl(gdrive_slot,role)
    end

    def Gfile.find_by_path(path,gdrive_slot)
      Gdrive.files(gdrive_slot,{"title"=>path,"title-exact"=>"true"}).first
    end

    def Gfile.read_by_task_path(task_path)
      #reserve gdrive_slot account for read
      gdrive_slot = Gdrive.slot_worker_by_path(t.path)
      return false unless gdrive_slot
      t = Task.where(:path=>task_path)
      gfile_path = t.params.first
      Gfile.find_by_path(gfile_path,gdrive_slot).read
    end
  end
end
