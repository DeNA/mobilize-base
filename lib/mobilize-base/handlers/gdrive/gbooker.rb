class Gbooker

  def Gbooker.find_or_create_by_title(title,account)
    books = Gdriver.books(account).select{|b| b.title==title}
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
          ititle = (b.title + "_invalid_" + Time.now.utc.to_s)
          #http
          b.title=ititle
          ("Renamed duplicate book to #{ititle}").oputs
        end
      end
    else
      book = books.first
    end
    if book.nil?
      #add book using owner account
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

  def Gbooker.find_or_create_by_dst_id(dst_id,account=nil)
    #creates by title, updates acl, updates dataset with url
    dst = dst_id.dst
    r = dst.requestor_id.r
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
          book = Gbooker.find_or_create_by_title(dst.name,account)
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
