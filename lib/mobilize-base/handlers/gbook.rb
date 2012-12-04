module Mobilize
  module Gbook
    def Gbook.find_all_by_path(path,gdrive_slot)
      Gdrive.books(gdrive_slot,{"title"=>path,"title-exact"=>"true"})
    end
    def Gbook.find_or_create_by_path(path,gdrive_slot)
      books = Gdrive.books(gdrive_slot,{"title"=>path,"title-exact"=>"true"})
      dst = Dataset.find_or_create_by_handler_and_path('gbook',path)
      #there should only be one book with each path, otherwise we have fail
      book = nil
      if books.length>1 and dst.url.to_s.length>0
        #some idiot process created a duplicate book.
        #Fix by renaming all but one with dst entry's key
        dkey = dst.url.split("key=").last
        books.each do |b|
          bkey = b.resource_id.split(":").last
          if bkey == dkey
            book = b
          else
            #delete the invalid book
            b.delete
            ("Deleted duplicate book #{path}").oputs
          end
        end
      else
        book = books.first
      end
      if book.nil?
        #always use owner email to make sure all books are owned by owner account
        book = Gdrive.root(Gdrive.owner_email).create_spreadsheet(path)
        ("Created book #{path} at #{Time.now.utc.to_s}; Access at #{book.human_url}").oputs
      end
      #always make sure book dataset URL is up to date
      #and that book has admin acl
      dst.update_attributes(:url=>book.human_url)
      book.add_admin_acl
      return book
    end
  end
end
