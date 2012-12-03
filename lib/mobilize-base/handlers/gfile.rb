module Mobilize
  class Gfile
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

    def Gfile.update_acl_by_path(path,gdrive_slot,role="writer",edit_email=nil)
      file = Gfile.find_by_path(path,edit_email)
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

    def Gsheet.write_by_task_path(task_path)
      gdrive_slot = Gdrive.slot_worker_by_path(path)
      #return false if there are no emails available
      return false unless email
      t = Task.find_by_task_path(task_path)
      source = t.params.first
      target_path = t.params.second
      source_job_name, source_task_name = if source.index("/")
                                            source.split("/")
                                          else
                                            [nil, source]
                                          end
      source_task_path = "#{t.job.runner.path}/#{source_job_name || t.job.name}/#{source_task_name}"
      source_task = Task.find_by_path(source_task_path)
      tsv = source_task.out_dataset.read_cache
      temp_sheet = Gsheet.find_or_create_by_path("#{task_path}:#{target}",gdrive_slot)
      temp_sheet.write(tsv)
      temp_sheet.check_and_fix(tsv)
      target_sheet = Gsheet.find_or_create_by_path(target_path,gdrive_slot)
      target_sheet.merge(temp_sheet)
      #delete the temp sheet's book
      temp_sheet.spreadsheet.delete
      "Write successful for #{target_path}".oputs
      return true
    end
  end
end
