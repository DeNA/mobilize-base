module Mobilize
  module Gdrive
    def Gdrive.config
      Base.config('gdrive')
    end

    def Gdrive.domain
      Gdrive.config['domain']
    end

    def Gdrive.owner_email
      Gdrive.config['owner']['email']
    end

    def Gdrive.password(email)
      if email == Gdrive.owner_email
        Gdrive.config['owner']['pw']
      else
        worker = Gdrive.workers(email)
        return worker['pw'] if worker
      end
    end

    def Gdrive.admins
      Gdrive.config['admins']
    end

    def Gdrive.workers(email=nil)
      if email.nil?
        Gdrive.config['workers']
      else
        Gdrive.workers.select{|w| w['email'] == email}.first
      end
    end

    def Gdrive.worker_emails
      Gdrive.workers.map{|w| w['email']}
    end

    def Gdrive.admin_emails
      Gdrive.admins.map{|w| w['email']}
    end

    #email management - used to make sure not too many emails get used at the same time
    def Gdrive.slot_worker_by_path(path)
      working_slots = Mobilize::Resque.jobs('working').map{|j| j['gdrive_slot'] if j['gdrive_slot']}.compact
      Gdrive.workers.sort_by{rand}.each do |w|
        unless working_slots.include?(w['email'])
          Mobilize::Resque.set_worker_args_by_path(path,{'gdrive_slot'=>w['email']})
          return w['email']
        end
      end
      #return false if none are available
      return false
    end

    def Gdrive.root(email=nil)
      email ||= Gdrive.owner_email
      pw = Gdrive.password(email)
      GoogleDrive.login(email,pw)
    end

    def Gdrive.files(email=nil,params={})
      root = Gdrive.root(email)
      root.files(params)
    end

    def Gdrive.books(email=nil,params={})
      Gdrive.files(email,params).select{|f| f.class==GoogleDrive::Spreadsheet}
    end
  end
end
