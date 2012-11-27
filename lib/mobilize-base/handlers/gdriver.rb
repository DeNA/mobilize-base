module Mobilize
  module Gdriver
    def Gdriver.config
      Base.config('gdrive')[Base.env]
    end

    def Gdriver.owner_email
      Gdriver.config['owner']['email']
    end

    def Gdriver.password(email)
      if email == Gdriver.owner_email
        Gdriver.config['owner']['pw']
      else
        worker = Gdriver.workers(email)
        return worker['pw'] if worker
      end
    end

    def Gdriver.admins
      Gdriver.config['admins']
    end

    def Gdriver.workers(email=nil)
      if email.nil?
        Gdriver.config['workers']
      else
        Gdriver.workers.select{|w| w['email'] == email}.first
      end
    end

    def Gdriver.worker_emails
      Gdriver.workers.map{|w| w['email']}
    end

    def Gdriver.admin_emails
      Gdriver.admins.map{|w| w['email']}
    end

    #email management - used to make sure not too many emails get used at the same time
    def Gdriver.get_worker_email_by_mongo_id(mongo_id)
      active_emails = Mobilize::Resque.jobs('working').map{|j| j['email'] if j['email']}.compact
      Gdriver.workers.sort_by{rand}.each do |w|
        if !(active_emails.include?(w['email']))
          Mobilize::Resque.update_job_email(mongo_id,w['email'])
          return w['email']
        end
      end
      #return false if none are available
      return false
    end

    def Gdriver.root(email=nil)
      email ||= Gdriver.owner_email
      pw = Gdriver.password(email)
      GoogleDrive.login(email,pw)
    end

    def Gdriver.files(email=nil,params={})
      root = Gdriver.root(email)
      root.files(params)
    end

    def Gdriver.books(email=nil,params={})
      Gdriver.files(email,params).select{|f| f.class==GoogleDrive::Spreadsheet}
    end
  end

  class Gfiler
    def Gfiler.find_by_title(title,email=nil)
      Gdriver.files(email).select{|f| f.title==title}.first
    end

    def Gfiler.find_by_dst_id(dst_id,email=nil)
      dst = Dataset.find(dst_id)
      Gfiler.find_by_title(dst.path,email)
    end

    def Gfiler.add_admin_acl_by_dst_id(dst_id)
      #adds admins and workers as writers
      file = Gfiler.find_by_dst_id(dst_id)
      file.add_admin_acl
      return true
    end

    def Gfiler.add_admin_acl_by_title(title)
      file = Gfiler.find_by_title(title)
      file.add_admin_acl
      return true
    end

    def Gfiler.add_worker_acl_by_title(title)
      file = Gfiler.find_by_title(title)
      file.add_worker_acl
      return true
    end

    def Gfiler.update_acl_by_dst_id(dst_id,email,role="writer",edit_email=nil)
      dst = Dataset.find(dst_id)
      Gfiler.update_acl_by_title(dst.path,email,role,edit_email)
    end

    def Gfiler.update_acl_by_title(title,email,role="writer",edit_email=nil)
      file = Gfiler.find_by_title(title,edit_email)
      raise "File #{title} not found" unless file
      file.update_acl(email,role)
    end
  end

  module Gbooker
    def Gbooker.find_all_by_title(title,email=nil)
      Gdriver.books(email,{"title"=>title,"title-exact"=>"true"})
    end
    def Gbooker.find_or_create_by_title(title,email)
      books = Gdriver.books(email,{"title"=>title,"title-exact"=>"true"})
      #there should only be one book with each title, otherwise we have fail
      book = nil
      if books.length>1
        #some idiot process created a duplicate book.
        #Fix by renaming all but one with dst entry's key
        dst = Dataset.find_by_handler_and_name('gbooker',title)
        dkey = dst.url.split("key=").last
        books.each do |b|
          bkey = b.resource_id.split(":").last
          if bkey == dkey
            book = b
          else
            #delete the invalid book
            b.delete
            ("Deleted duplicate book #{title}").oputs
          end
        end
      else
        book = books.first
      end
      if book.nil?
        #add book using owner email
        #http
        book = Gdriver.root.create_spreadsheet(title)
        ("Created book #{title} at #{Time.now.utc.to_s}").oputs
      end
      #delete Sheet1 if there are other sheets
      #http
      if (sheets = book.worksheets).length>1
        sheet1 = sheets.select{|s| s.title == "Sheet1"}.first
        #http
        sheet1.delete if sheet1
      end
      #always make sure books have admin acl
      book.add_admin_acl
      return book
    end

    def Gbooker.find_or_create_by_dst_id(dst_id,email=nil)
      #creates by title, updates acl, updates dataset with url
      dst = Dataset.find(dst_id)
      r = Requestor.find(dst.requestor_id)
      book = nil
      #http
      book = Gdriver.root.spreadsheet_by_url(dst.url) if dst.url
      #manually try 5 times to validate sheet since we can't just try again and again
      5.times.each do
        begin
          book.resource_id
          #if no error then break loop
          break
        rescue=>exc
          if book.nil? or exc.to_s.index('Invalid document id')
            book = Gbooker.find_or_create_by_title(dst.name,email)
            #if invalid doc then update url w new book and break loop
            dst.update_attributes(:url=>book.human_url)
            break
          end
        end
      end
      #add requestor write access
      book.update_acl(r.email)
      return book
    end
  end

  module Gsheeter

    def Gsheeter.max_cells
      400000
    end

    def Gsheeter.read(name,email=nil)
      sheet = Gsheeter.find_or_create_by_name(name,email)
      sheet.to_tsv
    end

    def Gsheeter.write(name,tsv,email=nil)
      sheet = Gsheeter.find_or_create_by_name(name,email)
      sheet.write(tsv)
    end

    def Gsheeter.find_all_by_name(name,email)
      book_title,sheet_title = name.split("/")
      books = Gdriver.books(email,{"title"=>book_title,"title-exact"=>"true"})
      sheets = books.map{|b| b.worksheets}.flatten.select{|w| w.title == sheet_title }
      sheets
    end

    def Gsheeter.find_or_create_by_name(name,email=nil,rows=100,cols=20)
      book_title,sheet_title = name.split("/")
      book = Gbooker.find_or_create_by_title(book_title,email)
      #http
      sheet = book.worksheets.select{|w| w.title==sheet_title}.first
      if sheet.nil?
        #http
        sheet = book.add_worksheet(sheet_title,rows,cols)
        ("Created sheet #{name} at #{Time.now.utc.to_s}").oputs
      end
      return sheet
    end

    def Gsheeter.find_or_create_by_dst_id(dst_id,email=nil)
      #creates by title, updates acl, updates dataset with url
      dst = Dataset.find(dst_id)
      r = Requestor.find(dst.requestor_id)
      name = dst.name
      book_title,sheet_title = name.split("/")
      #make sure book exists and is assigned to this user
      r.find_or_create_gbook_by_title(book_title,email)
      #add admin write access
      sheet = Gsheeter.find_or_create_by_name(name)
      sheet_title = nil
      return sheet
    end

    def Gsheeter.read_by_job_id(job_id)
      j = Job.find(job_id)
      r = j.requestor
      #reserve email account for read
      email = Gdriver.get_worker_email_by_mongo_id(job_id)
      return false unless email
      #only take the first sheet
      source = j.param_sheets.split(",").first
      book,sheet = source.split("/")
      #assume jobspec source if none given
      source = [r.jobspec_title,source].join("/") if sheet.nil?
      tsv = Gsheeter.find_or_create_by_name(source,email).to_tsv
      book = nil
      return tsv
    end

    def Gsheeter.read_by_dst_id(dst_id,email=nil)
      dst = Dataset.find(dst_id)
      name = dst.name
      sheet = Gsheeter.find_or_create_by_name(name,email)
      output = sheet.to_tsv
      return output
    end

    def Gsheeter.write_by_dst_id(dst_id,tsv,email=nil)
      dst = Dataset.find(dst_id)
      #see if this is a specific cell
      name = dst.name
      return false unless email
      #create temp tab, write data to it, checksum it against the source
      tempsheet = Gsheeter.find_or_create_by_name("#{name}_temp")
      tempsheet.write(tsv)
      #delete current sheet, replace it with temp one
      sheet = Gsheeter.find_or_create_by_name(dst.name)
      title = sheet.title
      #http
      sheet.delete
      begin
        tempsheet.rename(title)
      rescue
        #need this because sometimes it gets confused and tries to rename twice
      end
      "Write successful for #{write_name}".oputs
      return true
    end

    def Gsheeter.write_by_job_id(job_id)
      j = Job.find(job_id)
      r = j.requestor
      tgt_name = if j.destination.split("/").length==1
                    "#{r.jobspec_title}#{"/"}#{j.destination}"
                  else
                    j.destination
                  end
      sheet_dst = Dataset.find_or_create_by_handler_and_name('gsheeter',tgt_name)
      sheet_dst.update_attributes(:requestor_id=>r.id.to_s) if sheet_dst.requestor_id.nil?
      email = Gdriver.get_worker_email_by_mongo_id(job_id)
      #return false if there are no emails available
      return false unless email
      #create temp tab, write data to it, checksum it against the source
      tempsheet_dst = Dataset.find_or_create_by_handler_and_name('gsheeter',"#{tgt_name}_temp")
      tempsheet_dst.update_attributes(:requestor_id=>r.id.to_s) if tempsheet_dst.requestor_id.nil?
      tempsheet = Gsheeter.find_or_create_by_dst_id(tempsheet_dst.id.to_s)
      #tsv is the second to last stage's output (the last is the write)
      tsv = Dataset.find(j.tasks[j.prior_task]['output_dst_id']).read
      tempsheet.write(tsv,true,job_id)
      #delete current sheet, replace it with temp one
      sheet = Gsheeter.find_or_create_by_name(tgt_name,email)
      title = sheet.title
      #http
      sheet.delete
      tempsheet.title = title
      tempsheet.save
      sheet_dst.update_attributes(:url=>tempsheet.spreadsheet.human_url)
      "Write successful for #{tgt_name}".oputs
      return true
    end
  end
end
