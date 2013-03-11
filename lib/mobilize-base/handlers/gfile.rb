module Mobilize
  module Gfile

    def Gfile.url(path,*args)
      return "gfile://#{path}"
    end

    def Gfile.read_by_dataset_path(dst_path,user_name,*args)
      #expects gdrive slot as first arg, otherwise chooses random
      gdrive_slot = args
      worker_emails = Gdrive.worker_emails.sort_by{rand}
      gdrive_slot = worker_emails.first unless worker_emails.include?(gdrive_slot)
      file = Gfile.find_by_path(dst_path)
      file.read(user_name) if file
    end

    def Gfile.write_by_dataset_path(dst_path,string,user_name,*args)
      #ignores *args as all files must be created and owned by owner
      file = Gfile.find_by_path(dst_path)
      file.delete if file
      owner_root = Gdrive.root(Gdrive.owner_email)
      file = owner_root.upload_from_string(string,
                                    dst_path,
                                    :content_type=>"test/plain",
                                    :convert=>false)
      file.add_admin_acl
      #make sure user is owner or can edit
      u = User.where(:name=>user_name).first
      entry = file.acl_entry(u.email)
      unless entry and ['writer','owner'].include?(entry.role)
        file.update_acl(u.email)
      end
      #update http url for file
      dst = Dataset.find_by_handler_and_path("gfile",dst_path)
      dst.update_attributes(:http_url=>file.human_url)
      true
    end

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
      if file
        dst.update_attributes(:http_url=>file.human_url)
        file.add_admin_acl
      end
      return file
    end
  end
end
