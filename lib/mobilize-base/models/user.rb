module Mobilize
  class User
    include Mongoid::Document
    include Mongoid::Timestamps
    field :active, type: Boolean
    field :name, type: String
    field :ssh_public_key, type: String
    field :last_run, type: Time

    def User.find_or_create_by_name(name)
      u = User.where(:name => name).first
      u = User.create(:name => name) unless u
      return u
    end

    def email
      u = self
      "#{u.name}@#{Gdrive.domain}"
    end

    def runner
      u = self
      Runner.find_or_create_by_path(u.runner_path)
    end

    def jobs(jname=nil)
      u = self
      return u.runner.jobs
    end

    def runner_path
      u = self
      prefix = "Runner_"
      suffix = (Base.env == 'production' ? "" : "(#{Base.env})")
      title = [prefix,u.name,suffix,"/jobs"].join
      return title
    end
  end
end
