module Mobilize
  class User
    include Mongoid::Document
    include Mongoid::Timestamps
    field :active, type: Boolean
    field :email, type: String
    field :last_run, type: Time

    def User.find_or_create_by_email(email)
      u = User.where(:email => email).first
      u = User.create(:email => email) unless u
      return u
    end

    def runner
      u = self
      Runner.find_or_create_by_path(u.runner_path)
    end

    def jobs(jname=nil)
      u = self
      return u.runners.map{|r| r.jobs(jname)}.flatten
    end

    def name
      u = self
      u.email.split("@").first
    end

    def runner_path
      u = self
      prefix = "Runner - "
      suffix = ""
      if Base.env == 'development'
        suffix = "(dev)"
      elsif Base.env == 'test'
        suffix = "(test)"
      elsif Base.env == 'production'
        suffix = ""
      else
        raise "Invalid environment"
      end
      title = [prefix,u.name,suffix,"/jobs"].join
      return title
    end
  end
end
