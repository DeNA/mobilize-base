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
      gsheet_path = s.params['source']
      out_tsv = Gsheet.find_by_path(gsheet_path,gdrive_slot).to_tsv
      #use Gridfs to cache result
      out_url = "gridfs://#{s.path}/out"
      Dataset.write_to_url(out_url,out_tsv)
    end

    def Gsheet.write_by_stage_path(stage_path)
      gdrive_slot = Gdrive.slot_worker_by_path(stage_path)
      #return blank response if there are no slots available
      return nil unless gdrive_slot
      s = Stage.where(:path=>stage_path).first
      target_path = s.params['target']
      source_dst = s.source_dsts(gdrive_slot).first
      tsv = source_dst.read
      sheet_name = target_path.split("/").last
      temp_path = [stage_path.gridsafe,sheet_name].join("/")
      temp_sheet = Gsheet.find_or_create_by_path(temp_path,gdrive_slot)
      temp_sheet.write(tsv)
      temp_sheet.check_and_fix(tsv)
      target_sheet = Gsheet.find_or_create_by_path(target_path,gdrive_slot)
      target_sheet.merge(temp_sheet)
      #delete the temp sheet's book
      temp_sheet.spreadsheet.delete
      status = "Write successful for #{target_path}"
      s.update_status(status)
      #use Gridfs to cache result
      out_url = "gridfs://#{s.path}/out"
      Dataset.write_to_url(out_url,status)
    end
  end
end
