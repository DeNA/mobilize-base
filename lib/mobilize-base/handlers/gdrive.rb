module Mobilize
  module Gdrive
    def Gdrive.config
      Base.config('gdrive')
    end

    def Gdrive.domain
      Gdrive.config['domain']
    end

    def Gdrive.owner_email
      [Gdrive.config['owner']['name'],Gdrive.domain].join("@")
    end

    def Gdrive.owner_name
      Gdrive.config['owner']['name']
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
        Gdrive.workers.select{|w| [w['name'],Gdrive.domain].join("@") == email}.first
      end
    end

    def Gdrive.worker_emails
      Gdrive.workers.map{|w| [w['name'],Gdrive.domain].join("@")}
    end

    def Gdrive.admin_emails
      Gdrive.admins.map{|w| [w['name'],Gdrive.domain].join("@")}
    end

    #email management - used to make sure not too many emails get used at the same time
    def Gdrive.slot_worker_by_path(path)
      working_slots = Mobilize::Resque.jobs('working').map{|j| j['gdrive_slot'] if (j and j['gdrive_slot'])}.compact
      Gdrive.workers.sort_by{rand}.each do |w|
        unless working_slots.include?([w['name'],Gdrive.domain].join("@"))
          Mobilize::Resque.set_worker_args_by_path(path,{'gdrive_slot'=>[w['name'],Gdrive.domain].join("@")})
          return [w['name'],Gdrive.domain].join("@")
        end
      end
      #return false if none are available
      return false
    end

    def Gdrive.unslot_worker_by_path(path)
      begin
        Mobilize::Resque.set_worker_args_by_path(path,{'gdrive_slot'=>nil})
        return true
      rescue
        return false
      end
    end

    def Gdrive.root(gdrive_slot=nil)
      pw = Gdrive.password(gdrive_slot)
      GoogleDrive.login(gdrive_slot,pw)
    end

    def Gdrive.files(gdrive_slot=nil,params={})
      root = Gdrive.root(gdrive_slot)
      root.files(params)
    end

    def Gdrive.books(gdrive_slot=nil,params={})
      Gdrive.files(gdrive_slot,params).select{|f| f.class==GoogleDrive::Spreadsheet}
    end
  end
end
