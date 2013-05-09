module Mobilize
  module Gfile
    def Gfile.path_to_dst(path,stage_path,gdrive_slot)
      #don't need the ://
      path = path.split("://").last if path.index("://")
      if Gfile.find_by_path(path)
        handler = "gfile"
        Dataset.find_or_create_by_url("#{handler}://#{path}")
      else
        raise "unable to find #{path}"
      end
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
      #make sure user is owner
      u = User.where(:name=>user_name).first
      entry = file.acl_entry(u.email)
      unless entry and entry.role == "owner"
        file.update_acl(u.email,"owner")
      end
      #update http url for file
      dst = Dataset.find_by_handler_and_path("gfile",dst_path)
      api_url = file.human_url.split("&").first
      dst.update_attributes(:http_url=>api_url)
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
      file.update_acl(gdrive_slot,"user",role)
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
        api_url = file.human_url.split("&").first
        dst.update_attributes(:http_url=>api_url)
        file.add_admin_acl
      end
      return file
    end

    def Gfile.write_by_stage_path(stage_path)
      gdrive_slot = Gdrive.slot_worker_by_path(stage_path)
      #return blank response if there are no slots available
      return nil unless gdrive_slot
      s = Stage.where(:path=>stage_path).first
      u = s.job.runner.user
      begin
        #get tsv to write from stage
        source = s.sources(gdrive_slot).first
        raise "Need source for gfile write" unless source
        tsv = source.read(u.name,gdrive_slot)
        raise "No data source found for #{source.url}" unless tsv.to_s.length>0
        tsv_row_count = tsv.to_s.split("\n").length
        tsv_col_count = tsv.to_s.split("\n").first.to_s.split("\t").length
        tsv_cell_count = tsv_row_count * tsv_col_count
        if tsv_cell_count > Gfile.max_cells
          raise "Too many datapoints; you have #{tsv_cell_count.to_s}, max is #{Gfile.max_cells.to_s}"
        end
        stdout = if tsv_row_count == 0
             #soft error; no data to write. Stage will complete.
             "Write skipped for #{s.target.url}"
           else
             Dataset.write_by_url(s.target.url,tsv,u.name,gdrive_slot,crop)
             #update status
             "Write successful for #{s.target.url}"
           end
        Gdrive.unslot_worker_by_path(stage_path)
        stderr = nil
        s.update_status(stdout)
        signal = 0
      rescue => exc
        stdout = nil
        stderr = [exc.to_s,"\n",exc.backtrace.join("\n")].join
        signal = 500
      end
      return {'out_str'=>stdout, 'err_str'=>stderr, 'signal' => signal}
    end
  end
end
