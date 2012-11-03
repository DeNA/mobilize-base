module GoogleDrive
  class ClientLoginFetcher
    def request_raw(method, url, data, extra_header, auth)
      uri = URI.parse(url)
      http = @proxy.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      #set higher to allow for large downloads
      http.read_timeout = 600
      http.start() do
        path = uri.path + (uri.query ? "?#{uri.query}" : "")
        header = auth_header(auth).merge(extra_header)
        if method == :delete || method == :get
          return http.__send__(method, path, header)
        else
          return http.__send__(method, path, data, header)
        end
      end
    end
  end
  class AclEntry
    def to_xml()  #:nodoc:
      etag_attr = self.etag ? "gd:etag='#{h(self.etag)}'" : ""
      value_attr = self.scope ? "value='#{h(self.scope)}'" : ""
      if self.with_key
        role_tag = <<-EOS
            <gAcl:withKey key='[ACL KEY]'>
              <gAcl:role value='#{h(self.role)}'/>
            </gAcl:withKey>
        EOS
      else
        role_tag = <<-EOS
          <gAcl:role value='#{h(self.role)}'/>
        EOS
      end
      
      return <<-EOS
        <entry
            xmlns='http://www.w3.org/2005/Atom'
            xmlns:gAcl='http://schemas.google.com/acl/2007'
            xmlns:gd='http://schemas.google.com/g/2005'
            #{etag_attr}>
          <category scheme='http://schemas.google.com/g/2005#kind'
              term='http://schemas.google.com/acl/2007#accessRule'/>
          #{role_tag}
          <gAcl:scope type='#{h(self.scope_type)}' #{value_attr}/>
        </entry>
      EOS
    end
  end
  class Acl
    def update_role(entry, role) #:nodoc:
      #do not send email notifications
      url_suffix = "?send-notification-emails=false"
      puts url_suffix
      header = {"GData-Version" => "3.0", "Content-Type" => "application/atom+xml"}
      doc = @session.request(
          :put, %{#{entry.edit_url}#{url_suffix}}, :data => entry.to_xml(), :header => header, :auth => :writely)

      entry.params = entry_to_params(doc.root)
      return entry
    end

    def push(entry)
      #do not send email notifications
      entry = AclEntry.new(entry) if entry.is_a?(Hash)
      url_suffix = "?send-notification-emails=false"
      puts url_suffix
      header = {"GData-Version" => "3.0", "Content-Type" => "application/atom+xml"}
      doc = @session.request(:post, "#{@acls_feed_url}#{url_suffix}", :data => entry.to_xml(), :header => header, :auth => :writely)
      entry.params = entry_to_params(doc.root)
      @acls.push(entry)
      return entry
    end
  end

  class File

    def add_worker_acl
      f = self
      return true if f.has_worker_acl?
      Mobilize::Gdriver.worker_emails.each do |a| 
        f.update_acl(a)
      end
    end

    def add_admin_acl
      f = self
      #admin includes workers
      return true if f.has_admin_acl?
      (Mobilize::Gdriver.admin_emails + Mobilize::Gdriver.worker_emails).each do |a| 
        f.update_acl(a)
      end
    end

    def has_admin_acl?
      f = self
      curr_emails = f.acls.map{|a| a.scope}.sort
      admin_emails = Mobilize::Gdriver.admin_emails.sort
      if (curr_emails & admin_emails) == admin_emails
        return true
      else
        return false
      end
    end

    def has_worker_acl?
      f = self
      curr_emails = f.acls.map{|a| a.scope}.sort
      worker_emails = Mobilize::Gdriver.worker_emails.sort
      if (curr_emails & worker_emails) == worker_emails
        return true
      else
        return false
      end
    end

    def update_acl(email,role="writer")
      f = self
      #need these flags for HTTP retries
      update_complete = false
      retries = 0
      #create req_acl hash to add to current acl
      if entry = f.acl_entry(email)
        if [nil,"none","delete"].include?(role)
          f.acl.delete(entry)
        elsif entry.role != role and ['reader','writer','owner'].include?(role)
          entry.role=role
          f.acl.update_role(entry,entry.role)
        elsif !['reader','writer','owner'].include?(role)
          raise "Invalid role #{role}"
        end
      else
        f.acl.push({:scope_type=>"user",:scope=>email,:role=>role})
      end
      return true
    end
    def acls
      f = self
      f.acl.to_enum.to_a
    end
    def acl_entry(email)
      f = self
      curr_acls = f.acls
      curr_emails = curr_acls.map{|a| a.scope}
      f.acls.select{|a| ['group','user'].include?(a.scope_type) and a.scope == email}.first
    end

    def entry_hash
      f = self
      dfe_xml = f.document_feed_entry.to_xml
      begin
        Hash.from_xml(dfe_xml)[:entry]
      rescue
        {}
      end
    end
  end

  class Worksheet
    def to_tsv
      sheet = self
      #http
      sheet.rows.map{|r| r.join("\t")}.join("\n")
    end
    def write(tsv,check=true,job_id=nil)
      sheet = self
      tsvrows = tsv.split("\n")
      #no rows, no write
      return true if tsvrows.length==0
      headers = tsvrows.first.split("\t")
      #cap cells at 400k
      if (tsvrows.length*headers.length)>Mobilize::Gsheeter.max_cells
        raise "Too many cells in dataset"
      end
      batch_start = 0
      batch_length = 80
      rows_written = 0
      rowscols = nil
      #http
      curr_rows = sheet.num_rows
      curr_cols = sheet.num_cols
      pct_tens_complete =["0"]
      curr_pct_complete = "00"
      #make sure sheet is at least as big as necessary
      if tsvrows.length != curr_rows
        sheet.max_rows = tsvrows.length
        sheet.save
      end
      if headers.length != curr_cols
        sheet.max_cols = headers.length
        sheet.save
      end
      #write to sheet in batches of batch_length
      while batch_start < tsvrows.length
        batch_end = batch_start + batch_length
        tsvrows[batch_start..batch_end].each_with_index do |row,row_i|
          rowcols = row.split("\t")
          rowcols.each_with_index do |col_v,col_i|
            sheet[row_i+batch_start+1,col_i+1]= %{#{col_v}}
          end
        end
        sheet.save
        batch_start += (batch_length + 1)
        rows_written+=batch_length
        if batch_start>tsvrows.length+1
          if job_id
            newstatus = "100 pct written at #{Time.now.utc}"
            Mobilize::Job.find(job_id).update_status(newstatus)
            newstatus.oputs
          end
          break
        else
          #pad digit
          curr_pct_complete = "%02d" % ((rows_written+1).to_f*100/tsvrows.length.to_f).round(0)
          if !pct_tens_complete.include?(curr_pct_complete.first)
            if job_id
              newstatus = "#{curr_pct_complete} pct written at #{Time.now.utc}"
              Mobilize::Job.find(job_id).update_status(newstatus)
              newstatus.oputs
              pct_tens_complete << curr_pct_complete.first
            end
          end
        end
      end
      #checksum it against the source
      sheet.checksum(tsv) if check
      true
    end
    def checksum(tsv)
      sheet = self
      sheet.reload
      #loading remote data for checksum
      rem_tsv = sheet.to_tsv
      rem_table = rem_tsv.split("\n").map{|r| r.split("\t").map{|v| v.googlesafe}}
      loc_table = tsv.split("\n").map{|r| r.split("\t").map{|v| v.googlesafe}}
      re_col_vs = []
      errcnt = 0
      #checking cells
      loc_table.each_with_index do |loc_row,row_i|
        loc_row.each_with_index do |loc_v,col_i|
          rem_row = rem_table[row_i]
          if rem_row.nil?
            errcnt+=1
            "No Row #{row_i} for Write Dst".oputs
            break
          else
            rem_v = rem_table[row_i][col_i]
            if loc_v != rem_v
              if loc_v.starts_with?('rp') and rem_v.starts_with?('Rp')
                # some other math bs
                sheet[row_i+1,col_i+1] = %{'#{loc_v}}
                re_col_vs << {'row_i'=>row_i+1,'col_i'=>col_i+1,'col_v'=>%{'#{loc_v}}}
              elsif (loc_v.to_s.count('e')==1 or loc_v.to_s.count('e')==0) and
                loc_v.to_s.sub('e','').to_i.to_s==loc_v.to_s.sub('e','').gsub(/\A0+/,"") #trim leading zeroes
                #this is a string in scentific notation, or a numerical string with a leading zero
                #GDocs handles this poorly, need to rewrite write_dst cells by hand with a leading apostrophe for text
                sheet[row_i+1,col_i+1] = %{'#{loc_v}}
                re_col_vs << {'row_i'=>row_i+1,'col_i'=>col_i+1,'col_v'=>%{'#{loc_v}}}
              elsif loc_v.class==Float or loc_v.class==Fixnum
                if (loc_v - rem_v.to_f).abs>0.0001
                  "row #{row_i.to_s} col #{col_i.to_s}: Local=>#{loc_v.to_s} , Remote=>#{rem_v.to_s}".oputs
                  errcnt+=1
                end
              elsif rem_v.class==Float or rem_v.class==Fixnum
                if (rem_v - loc_v.to_f).abs>0.0001
                  "row #{row_i.to_s} col #{col_i.to_s}: Local=>#{loc_v.to_s} , Remote=>#{rem_v.to_s}".oputs
                  errcnt+=1
                end
              elsif loc_v.to_s.is_time?
                rem_time = begin
                             Time.parse(rem_v.to_s)
                           rescue
                             nil
                           end
                if rem_time.nil? || ((loc_v - rem_time).abs>1)
                  "row #{row_i.to_s} col #{col_i.to_s}: Local=>#{loc_v} , Remote=>#{rem_v}".oputs
                  errcnt+=1
                end
              else
                #"loc_v=>#{loc_v.to_s},rem_v=>#{rem_v.to_s}".oputs
                if loc_v.force_encoding("UTF-8") != rem_v.force_encoding("UTF-8")
                #make sure it's not an ecoding issue
                  "row #{row_i.to_s} col #{col_i.to_s}: Local=>#{loc_v} , Remote=>#{rem_v}".oputs
                  errcnt+=1
                end
              end
            end
          end
        end
      end
      if errcnt==0
        if re_col_vs.length>0
          sheet.save
          "rewrote:#{re_col_vs.to_s}".oputs
        else
          true
        end
      else
        raise "#{errcnt} errors found in checksum"
      end
    end
  end
end
