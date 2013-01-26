module Mobilize
  module Gsheet

    def Gsheet.config
      Base.config('gsheet')
    end

    def Gsheet.max_cells
      Gsheet.config['max_cells']
    end

    def Gsheet.write(path,tsv,gdrive_slot)
      sheet = Gsheet.find_or_create_by_path(path,gdrive_slot)
      sheet.write(tsv)
    end

    def Gsheet.find_by_path(path,gdrive_slot)
      book_path,sheet_name = path.split("/")
      book = Gdrive.books(gdrive_slot,{"title"=>book_path,"title-exact"=>"true"}).first
      return book.worksheet_by_title(sheet_name) if book
    end

    def Gsheet.find_or_create_by_path(path,gdrive_slot,rows=100,cols=20)
      book_path,sheet_name = path.split("/")
      book = Gbook.find_or_create_by_path(book_path,gdrive_slot)
      sheet = book.worksheet_by_title(sheet_name)
      if sheet.nil?
        sheet = book.add_worksheet(sheet_name,rows,cols)
        ("Created gsheet #{path} at #{Time.now.utc.to_s}").oputs
      end
      Dataset.find_or_create_by_handler_and_path("gsheet",path)
      return sheet
    end

    def Gsheet.read_by_stage_path(stage_path)
      #reserve gdrive_slot account for read
      gdrive_slot = Gdrive.slot_worker_by_path(stage_path)
      return false unless gdrive_slot
      s = Stage.where(:path=>stage_path).first
      user = s.job.runner.user.name
      source_dst = s.source_dsts(gdrive_slot).first
      out_tsv = source_dst.read(user)
      #use Gridfs to cache result
      out_url = "gridfs://#{s.path}/out"
      Dataset.write_by_url(out_url,out_tsv,Gdrive.owner_name)
    end

    def Gsheet.write_by_stage_path(stage_path)
      gdrive_slot = Gdrive.slot_worker_by_path(stage_path)
      #return blank response if there are no slots available
      return nil unless gdrive_slot
      s = Stage.where(:path=>stage_path).first
      user = s.job.runner.user
      target_path = s.params['target']
      target_path = "#{s.job.runner.title}/#{target_path}" unless target_path.index("/")
      source_dst = s.source_dsts(gdrive_slot).first
      tsv = source_dst.read(user.name)
      sheet_name = target_path.split("/").last
      temp_path = [stage_path.gridsafe,sheet_name].join("/")
      temp_sheet = Gsheet.find_or_create_by_path(temp_path,gdrive_slot)
      temp_sheet.write(tsv,Gdrive.owner_name)
      temp_sheet.check_and_fix(tsv)
      target_sheet = Gsheet.find_by_path(target_path,gdrive_slot)
      unless target_sheet
        #only give the user edit permissions if they're the ones
        #creating it
        target_sheet = Gsheet.find_or_create_by_path(target_path,gdrive_slot)
        target_sheet.spreadsheet.update_acl(user.email,"writer") unless target_sheet.spreadsheet.acl_entry(user.email).role=="owner"
        target_sheet.delete_sheet1
      end
      target_sheet.merge(temp_sheet,user.name)
      #delete the temp sheet's book
      temp_sheet.spreadsheet.delete
      status = "Write successful for #{target_path}"
      s.update_status(status)
      #use Gridfs to cache result
      out_url = "gridfs://#{s.path}/out"
      Dataset.write_by_url(out_url,status,Gdrive.owner_name)
    end
  end
end
