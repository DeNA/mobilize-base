module Mobilize
  require 'action_mailer'
  class Gmail < ActionMailer::Base
    ActionMailer::Base.delivery_method = :smtp
    
    ActionMailer::Base.smtp_settings = {
    :address              => "smtp.gmail.com",
    :port                 => 587,
    :domain               => Gdrive.domain,
    :user_name            => Gdrive.owner_email,
    :password             => Gdrive.password(Gdrive.owner_email),
    :authentication       => 'plain',
    :enable_starttls_auto => true  }

    def write(params)
      mail(:from=>Gdrive.owner_email,
           :to=>params['to'], 
           :subject=>params['subject'], 
           :body=>params['body'],
           :bcc=>params['bcc'])
    end
  end
end
