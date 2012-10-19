class Gfiler
  def Gfiler.find_by_title(title,account=nil)
    Gdriver.files(account).select{|f| f.title==title}.first
  end

  def Gfiler.find_by_dst_id(dst_id,account=nil)
    dst = dst_id.dst
    Gfiler.find_by_title(dst.path,account)
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

  def Gfiler.update_acl_by_dst_id(dst_id,account,role="writer",edit_account=nil)
    dst = dst_id.dst
    Gfiler.update_acl_by_title(dst.path,account,role,edit_account)
  end

  def Gfiler.update_acl_by_title(title,account,role="writer",edit_account=nil)
    file = Gfiler.find_by_title(title,edit_account)
    raise "File #{title} not found" unless file
    file.update_acl(account,role)
  end
end

class GoogleDrive::File

  def add_worker_acl
    f = self
    return true if f.has_worker_acl?
    (Gdriver.worker_accounts).each do |a| 
      f.update_acl(a)
    end
  end

  def add_admin_acl
    f = self
    #admin includes workers
    return true if f.has_admin_acl?
    (Gdriver.admin_accounts + Gdriver.worker_accounts).each do |a| 
      f.update_acl(a)
    end
  end

  def has_admin_acl?
    f = self
    curr_accounts = f.acls.map{|a| a.scope}.sort
    admin_accounts = Gdriver.admin_accounts.sort
    if (curr_accounts & admin_accounts) == admin_accounts
      return true
    else
      return false
    end
  end

  def has_worker_acl?
    f = self
    curr_accounts = f.acls.map{|a| a.scope}.sort
    worker_accounts = Gdriver.worker_accounts.sort
    if (curr_accounts & worker_accounts) == worker_accounts
      return true
    else
      return false
    end
  end

  def update_acl(account,role="writer")
    f = self
    #need these flags for HTTP retries
    update_complete = false
    retries = 0
    #create req_acl hash to add to current acl
    if entry = f.acl_entry(account)
      if [nil,"none","delete"].include?(role)
        f.acl.delete(entry)
      elsif entry.role != role and ['reader','writer','owner'].include?(role)
        entry.role=role
        f.acl.update_role(entry,entry.role,notify=false)
      elsif !['reader','writer','owner'].include?(role)
        raise "Invalid role #{role}"
      end
    else
      f.acl.push({:scope_type=>"user",:scope=>account,:role=>role},notify=false)
    end
    return true
  end
  def acls
    f = self
    f.acl.to_enum.to_a
  end
  def acl_entry(account)
    f = self
    curr_acls = f.acls
    curr_accounts = curr_acls.map{|a| a.scope}
    f.acls.select{|a| ['group','user'].include?(a.scope_type) and a.scope == account}.first
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

