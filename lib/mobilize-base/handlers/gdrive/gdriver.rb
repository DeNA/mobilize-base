class Gdriver

  def Gdriver.owner_account
    YAML.load_file('config/mobilize/gdriver.yml')['owner_account']
  end

  def Gdriver.password
    YAML.load_file('config/mobilize/gdriver.yml')['password']
  end

  def Gdriver.admin_accounts
    YAML.load_file('config/mobilize/gdriver.yml')['admin_accounts']
  end

  def Gdriver.worker_accounts
    YAML.load_file('config/mobilize/gdriver.yml')['worker_accounts']
  end

  #account management - used to make sure not too many accounts get used at the same time
  def Gdriver.get_worker_account
    active_accts = Jobtracker.worker_args.map{|a| a[1]['account'] if a[1]}.compact
    Gdriver.worker_accounts.sort_by{rand}.each do |ga|
      return ga unless active_accts.include?(ga)
    end
    #return false if none are available
    return false
  end

  def Gdriver.root(account=nil)
    account ||= Gdriver.owner_account
    #http
    GoogleDrive.login(account,Gdriver.password)
  end

  def Gdriver.files(account=nil)
    root = Gdriver.root(account)
    #http
    root.files
  end

  def Gdriver.books(account=nil)
    Gdriver.files(account).select{|f| f.class==GoogleDrive::Spreadsheet}
  end

  def Gdriver.txts(account=nil)
    Gdriver.files(account).select{|f| f.class==GoogleDrive::File and f.title.ends_with?("txt.gz")}
  end

end

