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

    def Gfile.read_by_stage_path(stage_path)
      #reserve gdrive_slot account for read
      gdrive_slot = Gdrive.slot_worker_by_path(s.path)
      return false unless gdrive_slot
      s = Stage.where(:path=>stage_path)
      gfile_path = s.params['file']
      out_tsv = Gfile.find_by_path(gfile_path,gdrive_slot).read
      #use Gridfs to cache result
      out_url = "gridfs://#{s.path}/out"
      Dataset.write_to_url(out_url,out_tsv,s.job.runner.user.name)
    end

    def Gfile.find_by_path(path)
      #file must be owned by owner
      gdrive_slot = Gdrive.owner_email
      files = Gdrive.files(gdrive_slot,{"title"=>path,"title-exact"=>"true"})
      dst = Dataset.find_or_create_by_handler_and_path('gfile',path)
      #there should only be one file with each path, otherwise we have fail
      file = nil
      if files.length>1
        #keep most recent file, delete the rest
        files.sort_by do |f| 
          (f.entry_hash[:published] || Time.now).to_time
          end.reverse.each_with_index do |f,f_i|
          if f_i == 0
            file = f
          else
            #delete the old file
            f.delete
            ("Deleted duplicate file #{path}").oputs
          end
        end
      else
        file = files.first
      end
      #always make sure dataset http URL is up to date
      #and that it has admin acl
      dst.update_attributes(:http_url=>file.human_url)
      file.add_admin_acl
      return file
    end
  end
end
